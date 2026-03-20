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
      # VM Memory
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.memory.atom", unit: :byte),
      last_value("vm.memory.system", unit: :byte),

      # Run queues
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io"),

      # System counts
      last_value("vm.system_counts.process_count"),
      last_value("vm.system_counts.atom_count"),
      last_value("vm.system_counts.port_count"),

      # Stress worker metrics
      counter("elixir_stress.worker.start.count", tags: [:worker]),
      counter("elixir_stress.worker.stop.count", tags: [:worker]),
      counter("elixir_stress.worker.cycle.count", tags: [:worker]),
      sum("elixir_stress.worker.cycle.value", tags: [:worker]),

      # Stress run
      counter("elixir_stress.run.start.count"),
      counter("elixir_stress.run.stop.count"),
      summary("elixir_stress.run.stop.duration", unit: {:native, :millisecond}),

      # HTTP requests
      summary("plug.cowboy.request.stop.duration", unit: {:native, :millisecond})
    ]
  end

  defp measurements do
    []
  end

  def scrape do
    TelemetryMetricsPrometheus.Core.scrape(:elixir_stress_prom)
  rescue
    _ -> ""
  end
end
