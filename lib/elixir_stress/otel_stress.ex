defmodule ElixirStress.OtelStress do
  @moduledoc """
  Tier 4: Workers that stress the OpenTelemetry pipeline itself.
  These generate massive volumes of spans, high-cardinality attributes,
  large payloads, and metric floods to test collector backpressure,
  Tempo ingestion, and Mimir write throughput.
  """

  require OpenTelemetry.Tracer, as: Tracer
  alias ElixirStress.OtelLogger

  # --- Span Flood: thousands of micro-spans per second ---

  def span_flood(seconds) do
    Tracer.with_span "otel_stress.span_flood", attributes: %{duration_seconds: seconds} do
      OtelLogger.info("OTel stress: span flood starting", %{worker: "span_flood"})
      deadline = deadline(seconds)
      span_flood_loop(deadline, 0)
    end
  end

  defp span_flood_loop(deadline, count) do
    if past?(deadline) do
      OtelLogger.info("OTel stress: span flood complete", %{
        worker: "span_flood",
        total_spans: count
      })

      {:span_flood, spans_created: count}
    else
      batch_size = Enum.random([50, 100, 200])

      new =
        Enum.reduce(1..batch_size, 0, fn i, acc ->
          Tracer.with_span "flood.micro_span",
            attributes: %{
              batch_seq: i,
              total_seq: count + acc + 1,
              timestamp: System.system_time(:microsecond)
            } do
            Tracer.add_event("tick", %{value: :rand.uniform(1000)})

            Tracer.with_span "flood.inner" do
              :erlang.phash2(:rand.uniform(1_000_000))
            end
          end

          acc + 1
        end)

      emit_cycle(:span_flood)
      span_flood_loop(deadline, count + new)
    end
  end

  # --- High Cardinality: unique attribute values to stress indexing ---

  def high_cardinality(seconds) do
    Tracer.with_span "otel_stress.high_cardinality", attributes: %{duration_seconds: seconds} do
      OtelLogger.info("OTel stress: high cardinality starting", %{worker: "high_cardinality"})
      deadline = deadline(seconds)
      high_cardinality_loop(deadline, 0)
    end
  end

  defp high_cardinality_loop(deadline, count) do
    if past?(deadline) do
      OtelLogger.info("OTel stress: high cardinality complete", %{
        worker: "high_cardinality",
        total_spans: count
      })

      {:high_cardinality, spans_created: count}
    else
      for _ <- 1..50 do
        unique_id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

        Tracer.with_span "cardinality.operation",
          attributes: %{
            unique_request_id: unique_id,
            user_id: "user_#{:rand.uniform(100_000)}",
            session_id: "sess_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}",
            request_path: "/api/v1/resource/#{:rand.uniform(10_000)}",
            http_method: Enum.random(["GET", "POST", "PUT", "DELETE", "PATCH"]),
            status_code: Enum.random([200, 201, 204, 400, 401, 403, 404, 500, 502, 503]),
            region: Enum.random(["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"]),
            version: "v#{:rand.uniform(50)}.#{:rand.uniform(100)}.#{:rand.uniform(999)}",
            correlation_id: "corr_#{:erlang.unique_integer([:positive])}"
          } do
          Tracer.add_event("request_processed", %{
            duration_ms: :rand.uniform(5000),
            bytes_in: :rand.uniform(1_000_000),
            bytes_out: :rand.uniform(5_000_000),
            cache_hit: Enum.random([true, false])
          })
        end
      end

      emit_cycle(:high_cardinality)
      high_cardinality_loop(deadline, count + 50)
    end
  end

  # --- Large Payloads: spans with massive event data ---

  def large_payloads(seconds) do
    Tracer.with_span "otel_stress.large_payloads", attributes: %{duration_seconds: seconds} do
      OtelLogger.info("OTel stress: large payloads starting", %{worker: "large_payloads"})
      deadline = deadline(seconds)
      large_payloads_loop(deadline, 0)
    end
  end

  defp large_payloads_loop(deadline, count) do
    if past?(deadline) do
      OtelLogger.info("OTel stress: large payloads complete", %{
        worker: "large_payloads",
        total_spans: count
      })

      {:large_payloads, spans_created: count}
    else
      for _ <- 1..10 do
        Tracer.with_span "payload.heavy_span",
          attributes: %{
            payload_id: "pay_#{:erlang.unique_integer([:positive])}",
            data_classification: "stress_test"
          } do
          large_str = String.duplicate("abcdefghijklmnop", 256)

          Tracer.add_event("large_request_body", %{
            body_preview: large_str,
            headers: "#{for i <- 1..50, into: "", do: "X-Header-#{i}: value-#{i}\n"}",
            query_params:
              "#{for i <- 1..30, into: "", do: "param#{i}=#{:crypto.strong_rand_bytes(32) |> Base.encode64()}&"}"
          })

          Tracer.add_event("large_response_body", %{
            body_preview: String.duplicate("response_data_chunk_", 200),
            total_size: :rand.uniform(10_000_000),
            compressed_size: :rand.uniform(1_000_000)
          })

          Tracer.add_event("stack_trace", %{
            trace:
              for(
                i <- 1..20,
                into: "",
                do:
                  "  at module_#{i}.function_#{i}(file_#{i}.ex:#{:rand.uniform(500)})\n"
              )
          })
        end
      end

      emit_cycle(:large_payloads)
      large_payloads_loop(deadline, count + 10)
    end
  end

  # --- Metric Flood: emit thousands of telemetry events per second ---

  def metric_flood(seconds) do
    Tracer.with_span "otel_stress.metric_flood", attributes: %{duration_seconds: seconds} do
      OtelLogger.info("OTel stress: metric flood starting", %{worker: "metric_flood"})
      deadline = deadline(seconds)
      metric_flood_loop(deadline, 0)
    end
  end

  defp metric_flood_loop(deadline, count) do
    if past?(deadline) do
      OtelLogger.info("OTel stress: metric flood complete", %{
        worker: "metric_flood",
        total_events: count
      })

      {:metric_flood, events_emitted: count}
    else
      batch = 500

      Enum.each(1..batch, fn _ ->
        :telemetry.execute(
          [:elixir_stress, :otel, :metric_flood],
          %{
            value: :rand.uniform(10_000),
            latency: :rand.uniform(5000),
            size: :rand.uniform(1_000_000)
          },
          %{
            worker: "metric_flood",
            endpoint: Enum.random(["/api/users", "/api/orders", "/api/products", "/api/health"]),
            method: Enum.random(["GET", "POST", "PUT", "DELETE"])
          }
        )
      end)

      emit_cycle(:metric_flood)
      metric_flood_loop(deadline, count + batch)
    end
  end

  # --- Log Flood: stress the Loki pipeline ---

  def log_flood(seconds) do
    Tracer.with_span "otel_stress.log_flood", attributes: %{duration_seconds: seconds} do
      OtelLogger.info("OTel stress: log flood starting", %{worker: "log_flood"})
      deadline = deadline(seconds)
      log_flood_loop(deadline, 0)
    end
  end

  defp log_flood_loop(deadline, count) do
    if past?(deadline) do
      OtelLogger.info("OTel stress: log flood complete", %{
        worker: "log_flood",
        total_logs: count
      })

      {:log_flood, logs_sent: count}
    else
      batch = 100

      Enum.each(1..batch, fn i ->
        level = Enum.random([:debug, :info, :warning, :error])

        OtelLogger.log(level, "Stress log entry ##{count + i}: #{String.duplicate("payload ", 10)}", %{
          worker: "log_flood",
          sequence: count + i,
          level: level,
          random_value: :rand.uniform(100_000),
          module: Enum.random(["UserController", "OrderService", "PaymentGateway", "AuthMiddleware"]),
          action: Enum.random(["create", "read", "update", "delete", "validate", "transform"])
        })
      end)

      Process.sleep(10)
      emit_cycle(:log_flood)
      log_flood_loop(deadline, count + batch)
    end
  end

  defp emit_cycle(worker_name) do
    :telemetry.execute([:elixir_stress, :worker, :cycle], %{count: 1, value: 1}, %{
      worker: Atom.to_string(worker_name)
    })
  end

  defp deadline(seconds), do: System.monotonic_time(:second) + seconds
  defp past?(deadline), do: System.monotonic_time(:second) >= deadline
end
