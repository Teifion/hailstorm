defmodule Hailstorm.Scenario.Supervisor do
  use Supervisor
  require Logger
  alias Hailstorm.Scenario

  def start_link(scenario) do
    Supervisor.start_link(__MODULE__, scenario,
      name: Scenario.System.via_scenario_name(scenario.name)
    )
  end

  @impl true
  def init(scenario) do
    children = [
      {DynamicSupervisor,
       name: Scenario.System.via_worker_sup_name(scenario.name), strategy: :one_for_one},

      {Scenario.StartTask, scenario}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def stop_scenario(scenario_name) do
    case Registry.lookup(Hailstorm.ScenarioRegistry, scenario_name) do
      [{pid, _}] ->
        Logger.info("terminating supervisor for scenario #{scenario_name}: #{inspect(pid)}")
        DynamicSupervisor.terminate_child(Hailstorm.Scenario.Supervisor, pid)

      _ ->
        :ok
    end
  end
end
