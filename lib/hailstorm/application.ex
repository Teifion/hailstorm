defmodule Hailstorm.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Hailstorm.PromEx,
      HailstormWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:hailstorm, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hailstorm.PubSub},
      {Task.Supervisor, name: Hailstorm.TaskSupervisor},
      # {Hailstorm.TestMetricsTask, 1},

      Hailstorm.Scenario.System,

      # Start a worker by calling: Hailstorm.Worker.start_link(arg)
      # {Hailstorm.Worker, arg},
      # Start to serve requests, typically the last entry
      HailstormWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hailstorm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HailstormWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
