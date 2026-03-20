defmodule ElixirStress.WorkerService do
  @moduledoc """
  Tier 5: A second HTTP service (port 4003) that simulates a downstream microservice.
  The main stress test makes HTTP calls here with W3C traceparent headers,
  creating real distributed traces across service boundaries.
  """

  use Plug.Router
  require OpenTelemetry.Tracer, as: Tracer
  alias ElixirStress.OtelLogger

  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :match
  plug :dispatch

  post "/work/compute" do
    extract_context(conn)

    Tracer.with_span "worker_service.compute",
      attributes: %{"service.name": "worker_service", operation: "compute"} do
      OtelLogger.info("worker_service: compute request received", %{operation: "compute"})
      intensity = conn.body_params["intensity"] || 1000

      Tracer.with_span "compute.fibonacci" do
        result = fib(Enum.min([intensity, 35]))
        Tracer.set_attributes(%{fib_n: intensity, fib_result: result})
        Tracer.add_event("fibonacci_complete", %{n: intensity, result: result})
      end

      Tracer.with_span "compute.sort" do
        data = for _ <- 1..100_000, do: :rand.uniform(1_000_000)
        sorted = Enum.sort(data)
        Tracer.add_event("sort_complete", %{elements: 100_000, first: hd(sorted)})
      end

      Tracer.with_span "compute.hash" do
        blob = :crypto.strong_rand_bytes(1_048_576)

        hash =
          Enum.reduce(1..100, blob, fn _, acc -> :crypto.hash(:sha256, acc) end)
          |> Base.encode16(case: :lower)
          |> binary_part(0, 16)

        Tracer.add_event("hash_complete", %{rounds: 100, hash_prefix: hash})
      end

      OtelLogger.info("worker_service: compute complete", %{operation: "compute"})
      send_json(conn, 200, %{status: "computed", intensity: intensity})
    end
  end

  post "/work/store" do
    extract_context(conn)

    Tracer.with_span "worker_service.store",
      attributes: %{"service.name": "worker_service", operation: "store"} do
      OtelLogger.info("worker_service: store request received", %{operation: "store"})
      rows = conn.body_params["rows"] || 10_000

      table = :ets.new(:worker_store, [:set, :public])

      Tracer.with_span "store.insert", attributes: %{row_count: rows} do
        Enum.each(1..rows, fn i ->
          :ets.insert(table, {i, :crypto.strong_rand_bytes(256), System.monotonic_time()})
        end)

        Tracer.add_event("rows_inserted", %{count: rows})
      end

      Tracer.with_span "store.scan" do
        total = :ets.foldl(fn {_, data, _}, acc -> byte_size(data) + acc end, 0, table)
        Tracer.add_event("scan_complete", %{total_bytes: total})
      end

      Tracer.with_span "store.cleanup" do
        :ets.delete(table)
        Tracer.add_event("table_deleted", %{})
      end

      OtelLogger.info("worker_service: store complete", %{operation: "store", rows: rows})
      send_json(conn, 200, %{status: "stored", rows: rows})
    end
  end

  post "/work/transform" do
    extract_context(conn)

    Tracer.with_span "worker_service.transform",
      attributes: %{"service.name": "worker_service", operation: "transform"} do
      OtelLogger.info("worker_service: transform request received", %{operation: "transform"})
      size = conn.body_params["size"] || 50_000

      Tracer.with_span "transform.generate", attributes: %{size: size} do
        data = for i <- 1..size, do: %{id: i, value: :rand.uniform(1_000_000), label: "item_#{i}"}
        Tracer.add_event("data_generated", %{count: size})

        Tracer.with_span "transform.filter" do
          filtered = Enum.filter(data, fn %{value: v} -> rem(v, 3) == 0 end)
          Tracer.add_event("data_filtered", %{kept: length(filtered)})

          Tracer.with_span "transform.aggregate" do
            grouped =
              Enum.group_by(filtered, fn %{value: v} -> div(v, 100_000) end)
              |> Enum.map(fn {bucket, items} ->
                {bucket, length(items), Enum.sum(Enum.map(items, & &1.value))}
              end)

            Tracer.add_event("aggregation_complete", %{buckets: length(grouped)})
          end
        end
      end

      OtelLogger.info("worker_service: transform complete", %{operation: "transform", size: size})
      send_json(conn, 200, %{status: "transformed", size: size})
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp extract_context(conn) do
    headers =
      Enum.map(conn.req_headers, fn {k, v} -> {k, v} end)

    :otel_propagator_text_map.extract(headers)
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp fib(0), do: 0
  defp fib(1), do: 1
  defp fib(n) when n > 1, do: fib(n - 1) + fib(n - 2)
end
