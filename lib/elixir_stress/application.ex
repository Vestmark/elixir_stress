defmodule ElixirStress.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    worker_service_spec =
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: ElixirStress.WorkerService,
        options: [port: 4003]
      )
      |> Map.put(:id, :worker_service_cowboy)

    children = [
      ElixirStress.Telemetry,
      ElixirStress.PromMetrics,
      ElixirStress.OtelLogger,
      {Plug.Cowboy, scheme: :http, plug: ElixirStress.Router, options: [port: 4001]},
      worker_service_spec,
      ElixirStress.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ElixirStress.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
