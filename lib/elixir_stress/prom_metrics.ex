defmodule ElixirStress.PromMetrics do
  @moduledoc """
  Prometheus metrics exporter and custom telemetry poller measurements.

  ## OTEL Overview
  This module defines all Prometheus metrics and polls the BEAM VM for deep metrics every 5 seconds.

  ### OTEL Gathering (inputs)
  - Telemetry events from stress.ex, otel_stress.ex, and router.ex via `:telemetry.execute/3`
  - BEAM VM statistics via :erlang.statistics/1, :erlang.memory/0, :erlang.system_info/1
  - Custom poller measurements every 5s: scheduler utilization, reductions, GC, IO, ETS, memory

  ### OTEL Output (destinations)
  - All metrics are exposed at GET /metrics on port 4001 in Prometheus text format
  - OTel Collector scrapes /metrics every 5s (configured in otel-collector-config.yml)
  - Flow: :telemetry events → TelemetryMetricsPrometheus.Core → /metrics → OTel Collector → Mimir
  - **Grafana locations by metric group:**
    - VM Memory → "Elixir Stress Test" → "BEAM Resources" → "Memory Usage"
    - Run Queues → "Elixir Stress Test" → "BEAM Resources" → "Run Queue Lengths"
    - System Counts → "Elixir Stress Test" → "BEAM Resources" → "Process / Port / Atom Counts"
    - Scheduler Util → "Elixir Stress Test" → "BEAM Deep Metrics" → "Scheduler Utilization"
    - Reductions → "Elixir Stress Test" → "BEAM Deep Metrics" → "Reductions/sec"
    - GC → "Elixir Stress Test" → "BEAM Deep Metrics" → "GC Rate"
    - IO → "Elixir Stress Test" → "BEAM Deep Metrics" → "System I/O Throughput"
    - ETS → "Elixir Stress Test" → "BEAM Deep Metrics" → "ETS Tables & Memory" + "ETS Table Count"
    - Code/Atom Memory → "Elixir Stress Test" → "BEAM Deep Metrics" → "Code & Atom Memory"
    - HTTP Requests → "Elixir Stress Test" → "BEAM Deep Metrics" → "HTTP Request Duration p95" + "HTTP Request Rate"
    - Worker lifecycle → "Elixir Stress Test" → "Worker Activity" → all panels
    - App metrics → "Elixir Stress - Application Metrics" → all panels
    - OTel metric flood → "Elixir Stress Test" → "OTel Pipeline Stress" → "Metric Flood Events/s"
  """

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

  ## OTEL Output: Defines all Prometheus metrics that are scraped by the OTel Collector
  ##   Each metric maps a :telemetry event to a Prometheus metric type (counter/gauge/histogram)
  ##   Flow: :telemetry.execute → TelemetryMetricsPrometheus.Core → /metrics endpoint → OTel Collector → Mimir
  def prom_metrics do
    import Telemetry.Metrics

    [
      # =============================================
      # VM Metrics (from :telemetry_poller built-in VM measurements)
      # OTEL Gathering: telemetry_poller emits [:vm, :memory] every 10s (built-in)
      # OTEL Output: Prometheus gauges scraped every 5s
      #   → Mimir → Grafana: "Elixir Stress Test" → "BEAM Resources" → "Memory Usage"
      # =============================================
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.system", unit: :byte),
      ## OTEL Gathering: From measure_memory_extra/0 custom poller (code memory from :erlang.memory)
      last_value("vm.memory.code", unit: :byte),
      ## OTEL Gathering: From measure_memory_extra/0 custom poller (:erlang.memory(:atom_used))
      last_value("vm.memory.atom_used", unit: :byte),

      # OTEL Gathering: telemetry_poller emits [:vm, :total_run_queue_lengths] every 10s (built-in)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Resources" → "Run Queue Lengths"
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      # OTEL Gathering: telemetry_poller emits [:vm, :system_counts] every 10s (built-in)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Resources" → "Process / Port / Atom Counts"
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),

      # =============================================
      # Scheduler Utilization (custom poller)
      # OTEL Gathering: From measure_scheduler_utilization/0 → :erlang.statistics(:scheduler_wall_time)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "Scheduler Utilization"
      # =============================================
      last_value("vm.scheduler.utilization.weighted", description: "Weighted avg scheduler utilization 0-100%"),
      last_value("vm.scheduler.utilization.max", description: "Most loaded scheduler utilization 0-100%"),

      # =============================================
      # Reductions (custom poller)
      # OTEL Gathering: From measure_reductions/0 → :erlang.statistics(:reductions)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "Reductions/sec"
      # =============================================
      last_value("vm.reductions.rate", description: "Reductions per second"),

      # =============================================
      # GC Metrics (custom poller)
      # OTEL Gathering: From measure_gc/0 → :erlang.statistics(:garbage_collection)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "GC Rate"
      # =============================================
      last_value("vm.gc.count_rate", description: "GC runs per second"),
      last_value("vm.gc.duration_rate", description: "GC pause microseconds per second"),
      last_value("vm.gc.words_reclaimed_rate", description: "GC words reclaimed per second"),

      # =============================================
      # IO Metrics (custom poller)
      # OTEL Gathering: From measure_io/0 → :erlang.statistics(:io)
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "System I/O Throughput"
      # =============================================
      last_value("vm.io.input_rate", unit: :byte, description: "Bytes input per second"),
      last_value("vm.io.output_rate", unit: :byte, description: "Bytes output per second"),

      # =============================================
      # ETS Global (custom poller)
      # OTEL Gathering: From measure_ets/0 → :ets.all() + :ets.info/2
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "ETS Tables & Memory" + "ETS Table Count"
      # =============================================
      last_value("vm.ets.table_count", description: "Total ETS tables"),
      last_value("vm.ets.total_memory", unit: :byte, description: "Total ETS memory across all tables"),

      # =============================================
      # HTTP Request Metrics
      # OTEL Gathering: From router.ex measure_request plug → [:vm, :http, :request] telemetry events
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "HTTP Request Duration p95" + "HTTP Request Rate"
      # =============================================
      distribution("vm.http.request.duration",
        tags: [:path, :status],
        unit: :millisecond,
        description: "HTTP request duration by path and status",
        reporter_options: [buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),
      counter("vm.http.request.count", tags: [:path, :status], description: "HTTP request count by path and status"),

      # =============================================
      # Worker Lifecycle
      # OTEL Gathering: From stress.ex propagated_worker → [:elixir_stress, :worker, :start/:stop/:cycle]
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "Worker Activity" → all panels
      # =============================================
      counter("elixir_stress.worker.start.count", tags: [:worker]),
      counter("elixir_stress.worker.stop.count", tags: [:worker]),
      counter("elixir_stress.worker.cycle.count", tags: [:worker]),
      sum("elixir_stress.worker.cycle.value", tags: [:worker]),

      # OTEL Gathering: From stress.ex run/1 and router.ex /stress trigger → [:elixir_stress, :run, :start/:stop]
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "Worker Activity" → "Stress Runs"
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
      # Application Metrics — Cycle Duration
      # OTEL Gathering: From stress.ex timed_cycle/2 → [:elixir_stress, :app, :cycle_duration]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Cycle Duration by Worker"
      # =============================================
      distribution("elixir_stress.app.cycle_duration.duration",
        tags: [:worker],
        unit: :microsecond,
        description: "Duration of each worker cycle in microseconds",
        reporter_options: [buckets: [1000, 5000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000, 10_000_000]]
      ),

      # =============================================
      # Application Metrics — Memory Operations
      # OTEL Gathering: From stress.ex memory_hog → [:elixir_stress, :app, :memory, :allocated/:released/:held]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Memory Operations"
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
      # OTEL Gathering: From stress.ex disk_thrash → [:elixir_stress, :app, :disk, :written/:read]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Disk I/O"
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
      # OTEL Gathering: From stress.ex process_explosion → [:elixir_stress, :app, :processes, :spawned/:killed/:alive]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Process Churn"
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
      # OTEL Gathering: From stress.ex message_queue_pressure → [:elixir_stress, :app, :messages, :sent]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Messages"
      # =============================================
      sum("elixir_stress.app.messages.sent.count",
        tags: [:worker],
        description: "Total messages sent"
      ),

      # =============================================
      # Application Metrics — Ports
      # OTEL Gathering: From stress.ex port_churn → [:elixir_stress, :app, :ports, :opened/:closed]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Ports"
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
      # OTEL Gathering: From stress.ex distributed_call → [:elixir_stress, :app, :distributed, :call/:error]
      # OTEL Output → Mimir → Grafana: "App Metrics" → "Distributed Calls"
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
      # OTEL Gathering: From otel_stress.ex metric_flood → [:elixir_stress, :otel, :metric_flood]
      # OTEL Output → Mimir → Grafana: "Elixir Stress Test" → "OTel Pipeline Stress" → "Metric Flood Events/s"
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

  ## OTEL Gathering: Custom telemetry_poller measurements executed every 5 seconds
  ##   Each function gathers BEAM VM statistics and emits telemetry events
  ##   which are then converted to Prometheus metrics by TelemetryMetricsPrometheus.Core
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
  ## OTEL Gathering: Reads :erlang.statistics(:scheduler_wall_time) to compute per-scheduler
  ##   utilization as a percentage. Calculates weighted average and max utilization across all schedulers.
  ##   Uses :persistent_term to store previous readings for delta calculation.
  ## OTEL Output: Telemetry event [:vm, :scheduler, :utilization] with {weighted, max} measurements
  ##   → Prometheus: vm_scheduler_utilization_weighted, vm_scheduler_utilization_max
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "Scheduler Utilization"
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
  ## OTEL Gathering: Reads :erlang.statistics(:reductions) — total reductions since VM start
  ##   Computes rate by comparing with previous reading stored in :persistent_term
  ## OTEL Output: Telemetry event [:vm, :reductions] with {rate} measurement (reductions/sec)
  ##   → Prometheus: vm_reductions_rate
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "Reductions/sec"
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
  ## OTEL Gathering: Reads :erlang.statistics(:garbage_collection) — {gc_count, gc_words, 0}
  ##   Computes rates by comparing with previous readings stored in :persistent_term
  ## OTEL Output: Telemetry event [:vm, :gc] with {count_rate, duration_rate, words_reclaimed_rate}
  ##   → Prometheus: vm_gc_count_rate, vm_gc_duration_rate, vm_gc_words_reclaimed_rate
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "GC Rate"
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
  ## OTEL Gathering: Reads :erlang.statistics(:io) — {{:input, bytes_in}, {:output, bytes_out}}
  ##   Computes bytes/sec rates by comparing with previous readings stored in :persistent_term
  ## OTEL Output: Telemetry event [:vm, :io] with {input_rate, output_rate} in bytes/sec
  ##   → Prometheus: vm_io_input_rate_bytes, vm_io_output_rate_bytes
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "System I/O Throughput"
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
  ## OTEL Gathering: Iterates :ets.all() to count tables and sum memory across all ETS tables
  ##   Memory is calculated as: :ets.info(tab, :memory) * :erlang.system_info(:wordsize)
  ## OTEL Output: Telemetry event [:vm, :ets] with {table_count, total_memory}
  ##   → Prometheus: vm_ets_table_count, vm_ets_total_memory_bytes
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "ETS Tables & Memory" + "ETS Table Count"
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
  ## OTEL Gathering: Reads :erlang.memory() for code memory and :erlang.memory(:atom_used) for used atoms
  ## OTEL Output: Telemetry event [:vm, :memory] with {code, atom_used}
  ##   → Prometheus: vm_memory_code_bytes, vm_memory_atom_used_bytes
  ##   → OTel Collector → Mimir → Grafana: "Elixir Stress Test" → "BEAM Deep Metrics" → "Code & Atom Memory"
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

  ## OTEL Output: Scrapes all accumulated Prometheus metrics as text format
  ##   Called by router.ex GET /metrics endpoint
  ##   → OTel Collector scrapes this every 5s (configured in otel-collector-config.yml)
  ##   → Mimir → Grafana: all metric panels across both dashboards
  def scrape do
    TelemetryMetricsPrometheus.Core.scrape(:elixir_stress_prom)
  rescue
    _ -> ""
  end
end
