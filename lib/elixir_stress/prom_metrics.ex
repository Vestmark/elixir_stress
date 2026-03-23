defmodule ElixirStress.PromMetrics do
  @moduledoc false

  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus.Core, metrics: prom_metrics(), name: :elixir_stress_prom},
      {:telemetry_poller, measurements: measurements(), period: 5_000, name: :prom_poller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def prom_metrics do
    import Telemetry.Metrics

    [
      # =============================================
      # VM Metrics
      # =============================================
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.system", unit: :byte),
      last_value("vm.memory.code", unit: :byte),
      last_value("vm.memory.atom_used", unit: :byte),

      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),

      # =============================================
      # Scheduler Utilization
      # =============================================
      last_value("vm.scheduler.utilization.weighted", description: "Weighted avg scheduler utilization 0-100%"),
      last_value("vm.scheduler.utilization.max", description: "Most loaded scheduler utilization 0-100%"),

      # =============================================
      # Reductions
      # =============================================
      last_value("vm.reductions.rate", description: "Reductions per second"),

      # =============================================
      # GC Metrics
      # =============================================
      last_value("vm.gc.count_rate", description: "GC runs per second"),
      last_value("vm.gc.duration_rate", description: "GC pause microseconds per second"),
      last_value("vm.gc.words_reclaimed_rate", description: "GC words reclaimed per second"),

      # =============================================
      # IO Metrics
      # =============================================
      last_value("vm.io.input_rate", unit: :byte, description: "Bytes input per second"),
      last_value("vm.io.output_rate", unit: :byte, description: "Bytes output per second"),

      # =============================================
      # ETS Global
      # =============================================
      last_value("vm.ets.table_count", description: "Total ETS tables"),
      last_value("vm.ets.total_memory", unit: :byte, description: "Total ETS memory across all tables"),

      # =============================================
      # HTTP Request Metrics
      # =============================================
      distribution("vm.http.request.duration",
        tags: [:path, :status],
        unit: :millisecond,
        description: "HTTP request duration by path and status",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),
      counter("vm.http.request.count", tags: [:path, :status], description: "HTTP request count by path and status"),

      # =============================================
      # Worker Lifecycle (existing)
      # =============================================
      counter("elixir_stress.worker.start.count", tags: [:worker]),
      counter("elixir_stress.worker.stop.count", tags: [:worker]),
      counter("elixir_stress.worker.cycle.count", tags: [:worker]),
      sum("elixir_stress.worker.cycle.value", tags: [:worker]),

      counter("elixir_stress.run.start.count"),
      counter("elixir_stress.run.stop.count"),
      distribution("elixir_stress.run.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [100, 500, 1000, 5000, 15000, 30000, 60000, 120_000]]
      ),
      distribution("plug.cowboy.request.stop.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [1, 5, 10, 50, 100, 500, 1000]]
      ),

      # =============================================
      # Application Metrics — Cycle Duration (histogram-like via summary)
      # Template: "How long does each operation take?"
      # =============================================
      distribution("elixir_stress.app.cycle_duration.duration",
        tags: [:worker],
        unit: :microsecond,
        description: "Duration of each worker cycle in microseconds",
        reporter_options: [buckets: [1000, 5000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000]]
      ),

      # =============================================
      # Application Metrics — Memory Operations
      # Template: "How much is being allocated/released?"
      # =============================================
      sum("elixir_stress.app.memory.allocated.bytes",
        tags: [:worker],
        description: "Total bytes allocated"
      ),
      counter("elixir_stress.app.memory.allocated.count",
        tags: [:worker],
        description: "Number of allocation events"
      ),
      sum("elixir_stress.app.memory.released.bytes",
        tags: [:worker],
        description: "Total bytes released"
      ),
      counter("elixir_stress.app.memory.released.count",
        tags: [:worker],
        description: "Number of release events"
      ),
      last_value("elixir_stress.app.memory.held.bytes",
        tags: [:worker],
        description: "Currently held bytes (gauge)"
      ),
      last_value("elixir_stress.app.memory.held.chunks",
        tags: [:worker],
        description: "Currently held chunk count (gauge)"
      ),

      # =============================================
      # Application Metrics — Disk I/O
      # Template: "How much data is moving through the system?"
      # =============================================
      sum("elixir_stress.app.disk.written.bytes",
        tags: [:worker],
        description: "Total bytes written to disk"
      ),
      counter("elixir_stress.app.disk.written.count",
        tags: [:worker],
        description: "Number of disk write operations"
      ),
      sum("elixir_stress.app.disk.read.bytes",
        tags: [:worker],
        description: "Total bytes read from disk"
      ),
      counter("elixir_stress.app.disk.read.count",
        tags: [:worker],
        description: "Number of disk read operations"
      ),

      # =============================================
      # Application Metrics — Process Churn
      # Template: "How much concurrency churn is happening?"
      # =============================================
      sum("elixir_stress.app.processes.spawned.count",
        tags: [:worker],
        description: "Total processes spawned"
      ),
      sum("elixir_stress.app.processes.killed.count",
        tags: [:worker],
        description: "Total processes killed"
      ),
      last_value("elixir_stress.app.processes.alive.count",
        tags: [:worker],
        description: "Currently alive stress processes (gauge)"
      ),

      # =============================================
      # Application Metrics — Messages
      # Template: "What is the throughput of the messaging system?"
      # =============================================
      sum("elixir_stress.app.messages.sent.count",
        tags: [:worker],
        description: "Total messages sent"
      ),

      # =============================================
      # Application Metrics — Ports
      # Template: "How many external resources are being churned?"
      # =============================================
      sum("elixir_stress.app.ports.opened.count",
        tags: [:worker],
        description: "Total ports opened"
      ),
      sum("elixir_stress.app.ports.closed.count",
        tags: [:worker],
        description: "Total ports closed"
      ),

      # =============================================
      # Application Metrics — Distributed Calls
      # Template: "How are downstream services performing?"
      # =============================================
      distribution("elixir_stress.app.distributed.call.duration",
        tags: [:endpoint, :status],
        unit: :millisecond,
        description: "Duration of distributed HTTP calls",
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000, 10_000]]
      ),
      counter("elixir_stress.app.distributed.call.count",
        tags: [:endpoint, :status],
        description: "Count of distributed calls by endpoint and status"
      ),
      counter("elixir_stress.app.distributed.error.count",
        tags: [:endpoint],
        description: "Count of distributed call errors"
      ),

      # =============================================
      # OTel Stress (Tier 4)
      # =============================================
      counter("elixir_stress.otel.metric_flood.count",
        tags: [:endpoint, :method],
        description: "Metric flood events"
      ),
      sum("elixir_stress.otel.metric_flood.value",
        tags: [:endpoint, :method],
        description: "Metric flood values"
      )
    ]
  end

  defp measurements do
    [
      {__MODULE__, :measure_scheduler_utilization, []},
      {__MODULE__, :measure_reductions, []},
      {__MODULE__, :measure_gc, []},
      {__MODULE__, :measure_io, []},
      {__MODULE__, :measure_ets, []},
      {__MODULE__, :measure_memory_extra, []}
    ]
  end

  # --- Scheduler utilization via wall time ---
  def measure_scheduler_utilization do
    case :persistent_term.get({__MODULE__, :prev_scheduler_wall_time}, nil) do
      nil ->
        :erlang.system_flag(:scheduler_wall_time, true)
        :persistent_term.put({__MODULE__, :prev_scheduler_wall_time}, :erlang.statistics(:scheduler_wall_time))

      prev ->
        current = :erlang.statistics(:scheduler_wall_time)

        utils =
          Enum.zip(Enum.sort(prev), Enum.sort(current))
          |> Enum.map(fn {{_, a0, t0}, {_, a1, t1}} ->
            dt = t1 - t0
            if dt > 0, do: (a1 - a0) / dt * 100, else: 0.0
          end)

        weighted = if length(utils) > 0, do: Enum.sum(utils) / length(utils), else: 0.0
        max_util = if length(utils) > 0, do: Enum.max(utils), else: 0.0

        :telemetry.execute([:vm, :scheduler, :utilization], %{weighted: round(weighted * 100) / 100, max: round(max_util * 100) / 100})
        :persistent_term.put({__MODULE__, :prev_scheduler_wall_time}, current)
    end
  end

  # --- Reductions per second ---
  def measure_reductions do
    {total, _since_last} = :erlang.statistics(:reductions)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, :prev_reductions}, nil) do
      nil ->
        :persistent_term.put({__MODULE__, :prev_reductions}, {total, now})

      {prev_total, prev_time} ->
        dt = max(now - prev_time, 1)
        rate = (total - prev_total) / dt * 1000
        :telemetry.execute([:vm, :reductions], %{rate: round(rate)})
        :persistent_term.put({__MODULE__, :prev_reductions}, {total, now})
    end
  end

  # --- GC metrics ---
  def measure_gc do
    {gc_count, gc_words, _} = :erlang.statistics(:garbage_collection)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, :prev_gc}, nil) do
      nil ->
        :persistent_term.put({__MODULE__, :prev_gc}, {gc_count, gc_words, now})

      {prev_count, prev_words, prev_time} ->
        dt = max(now - prev_time, 1) / 1000
        count_rate = (gc_count - prev_count) / dt
        words_rate = (gc_words - prev_words) / dt

        :telemetry.execute([:vm, :gc], %{
          count_rate: round(count_rate),
          duration_rate: 0,
          words_reclaimed_rate: round(words_rate)
        })

        :persistent_term.put({__MODULE__, :prev_gc}, {gc_count, gc_words, now})
    end
  end

  # --- IO bytes in/out per second ---
  def measure_io do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, :prev_io}, nil) do
      nil ->
        :persistent_term.put({__MODULE__, :prev_io}, {input, output, now})

      {prev_input, prev_output, prev_time} ->
        dt = max(now - prev_time, 1) / 1000
        input_rate = (input - prev_input) / dt
        output_rate = (output - prev_output) / dt

        :telemetry.execute([:vm, :io], %{input_rate: round(input_rate), output_rate: round(output_rate)})
        :persistent_term.put({__MODULE__, :prev_io}, {input, output, now})
    end
  end

  # --- ETS global stats ---
  def measure_ets do
    tables = :ets.all()
    table_count = length(tables)

    total_memory =
      Enum.reduce(tables, 0, fn tab, acc ->
        try do
          acc + :ets.info(tab, :memory) * :erlang.system_info(:wordsize)
        rescue
          _ -> acc
        end
      end)

    :telemetry.execute([:vm, :ets], %{table_count: table_count, total_memory: total_memory})
  end

  # --- Extra memory breakdowns ---
  def measure_memory_extra do
    mem = :erlang.memory()
    code = Keyword.get(mem, :code, 0)

    atom_used =
      try do
        :erlang.memory(:atom_used)
      rescue
        _ -> 0
      end

    :telemetry.execute([:vm, :memory], %{code: code, atom_used: atom_used})
  end

  def scrape do
    TelemetryMetricsPrometheus.Core.scrape(:elixir_stress_prom)
  rescue
    _ -> ""
  end
end
