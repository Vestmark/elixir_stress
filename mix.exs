defmodule ElixirStress.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_stress,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :os_mon, :inets, :ssl],
      mod: {ElixirStress.Application, []}
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.7"},
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},

      # OpenTelemetry
      {:opentelemetry, "~> 1.4"},
      {:opentelemetry_api, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.7"},
      {:opentelemetry_telemetry, "~> 1.1"},
      {:opentelemetry_process_propagator, "~> 0.3"},

      # Prometheus metrics
      {:telemetry_metrics_prometheus_core, "~> 1.2"},

      # HTTP client for multi-service calls
      {:req, "~> 0.5"}
    ]
  end
end
