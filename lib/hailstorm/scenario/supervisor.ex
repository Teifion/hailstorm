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
      {Hailstorm.Scenario.Reaper, scenario},
      {DynamicSupervisor,
       name: Scenario.System.via_worker_sup_name(scenario.name), strategy: :one_for_one},
      {Scenario.StartTask, scenario}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
