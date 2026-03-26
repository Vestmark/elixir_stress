defmodule ElixirStress.OtelLogger do
  @moduledoc """
  Structured logger that sends logs to the OTel collector via OTLP HTTP.
  Enriches every log record with trace_id and span_id from the current OTel context.
  Logs flow: this module -> OTLP HTTP (localhost:4318) -> OTel Collector -> Loki.

  ## OTEL Overview
  This is the central log output module. All structured logs from stress.ex, otel_stress.ex,
  and worker_service.ex flow through here.

  ### OTEL Gathering
  - Reads current OTel span context via `OpenTelemetry.Tracer.current_span_ctx()`
  - Extracts trace_id and span_id for log-trace correlation
  - This allows clicking a log entry in Grafana/Loki to jump directly to the correlated trace in Tempo

  ### OTEL Output
  - Builds OTLP JSON payload (resourceLogs format) with:
    - Resource attributes: service.name="elixir_stress", service.instance.id, host.name
    - Scope: "elixir_stress.logger" v0.1.0
    - Per-record: timeUnixNano, severityNumber/Text, body, attributes, traceId, spanId
  - Sends via HTTP POST to localhost:4318/v1/logs (OTLP HTTP endpoint)
  - Flow: OtelLogger → OTLP HTTP → OTel Collector → Loki
  - **Grafana locations:**
    - "Elixir Stress Test" dashboard → "Structured Logs" → "Application Logs" (all logs)
    - "Elixir Stress Test" dashboard → "Structured Logs" → "Log Volume by Severity" (stacked by level)
    - "Elixir Stress Test" dashboard → "Structured Logs" → "Error Logs" (ERROR only)
    - "Elixir Stress Test" dashboard → "Distributed Tracing" → "Worker Service Logs"
    - Grafana Explore → Loki → {service_name="elixir_stress"}
    - Each log entry has trace_id link → click to jump to Tempo trace
  """

  use GenServer

  @flush_interval 1_000
  ## OTEL Output: OTLP HTTP endpoint for log export
  ##   Logs are POSTed here as JSON every @flush_interval (1 second)
  ##   → OTel Collector → Loki → Grafana
  @otlp_endpoint ~c"http://localhost:4318/v1/logs"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## OTEL Gathering: Captures trace_id and span_id from the CURRENT OTel span context
  ##   at the moment the log is created (not when it's flushed). This ensures correct
  ##   correlation even though logs are buffered and sent asynchronously.
  ##   trace_id: 32-char hex string (128-bit), span_id: 16-char hex string (64-bit)
  ##   These are included in the OTLP log payload for log-trace correlation in Grafana
  def log(level, message, metadata \\ %{}) do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()

    trace_id =
      case :otel_span.trace_id(span_ctx) do
        0 -> ""
        id -> id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
      end

    span_id =
      case :otel_span.span_id(span_ctx) do
        0 -> ""
        id -> id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(16, "0")
      end

    record = %{
      time: System.system_time(:nanosecond),
      severity: level,
      body: message,
      attributes: metadata,
      trace_id: trace_id,
      span_id: span_id
    }

    GenServer.cast(__MODULE__, {:log, record})
  end

  def info(msg, meta \\ %{}), do: log(:info, msg, meta)
  def warning(msg, meta \\ %{}), do: log(:warning, msg, meta)
  def error(msg, meta \\ %{}), do: log(:error, msg, meta)
  def debug(msg, meta \\ %{}), do: log(:debug, msg, meta)

  # GenServer callbacks

  @impl true
  def init(_opts) do
    schedule_flush()
    {:ok, %{buffer: []}}
  end

  @impl true
  def handle_cast({:log, record}, state) do
    {:noreply, %{state | buffer: [record | state.buffer]}}
  end

  @impl true
  def handle_info(:flush, %{buffer: []} = state) do
    schedule_flush()
    {:noreply, state}
  end

  def handle_info(:flush, %{buffer: buffer} = state) do
    records = Enum.reverse(buffer)
    spawn(fn -> send_logs(records) end)
    schedule_flush()
    {:noreply, %{state | buffer: []}}
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  ## OTEL Output: Sends buffered log records as OTLP JSON to the OTel Collector
  ##   HTTP POST to localhost:4318/v1/logs with Content-Type: application/json
  ##   → OTel Collector logs pipeline → Loki
  ##   → Grafana: "Elixir Stress Test" → "Structured Logs" section (all panels)
  defp send_logs(records) do
    payload = build_otlp_payload(records)
    body = Jason.encode!(payload)

    :httpc.request(
      :post,
      {@otlp_endpoint, [{~c"content-type", ~c"application/json"}], ~c"application/json",
       String.to_charlist(body)},
      [],
      []
    )
  rescue
    _ -> :ok
  end

  ## OTEL Output: Builds OTLP resourceLogs JSON payload
  ##   Structure: { resourceLogs: [{ resource: { attributes: [...] }, scopeLogs: [{ scope: {...}, logRecords: [...] }] }] }
  ##   Resource attributes identify the service: service.name, service.instance.id, host.name
  ##   Each logRecord includes: timeUnixNano, severityNumber/Text, body, attributes, traceId, spanId
  defp build_otlp_payload(records) do
    %{
      "resourceLogs" => [
        %{
          "resource" => %{
            "attributes" => [
              %{"key" => "service.name", "value" => %{"stringValue" => "elixir_stress"}},
              %{
                "key" => "service.instance.id",
                "value" => %{"stringValue" => node() |> Atom.to_string()}
              },
              %{"key" => "host.name", "value" => %{"stringValue" => hostname()}}
            ]
          },
          "scopeLogs" => [
            %{
              "scope" => %{"name" => "elixir_stress.logger", "version" => "0.1.0"},
              "logRecords" => Enum.map(records, &format_record/1)
            }
          ]
        }
      ]
    }
  end

  defp format_record(record) do
    base = %{
      "timeUnixNano" => Integer.to_string(record.time),
      "observedTimeUnixNano" => Integer.to_string(record.time),
      "severityNumber" => severity_number(record.severity),
      "severityText" => record.severity |> Atom.to_string() |> String.upcase(),
      "body" => %{"stringValue" => record.body},
      "attributes" =>
        Enum.map(record.attributes, fn {k, v} ->
          %{"key" => to_string(k), "value" => otlp_value(v)}
        end)
    }

    base
    |> maybe_put("traceId", record.trace_id)
    |> maybe_put("spanId", record.span_id)
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp otlp_value(v) when is_integer(v), do: %{"intValue" => Integer.to_string(v)}
  defp otlp_value(v) when is_float(v), do: %{"doubleValue" => v}
  defp otlp_value(v) when is_boolean(v), do: %{"boolValue" => v}
  defp otlp_value(v), do: %{"stringValue" => to_string(v)}

  defp severity_number(:debug), do: 5
  defp severity_number(:info), do: 9
  defp severity_number(:warning), do: 13
  defp severity_number(:error), do: 17
  defp severity_number(_), do: 0

  defp hostname do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end
end
