defmodule Hailstorm.Scenario.Supervisor do
  use Supervisor
  alias Hailstorm.Scenario

  def start_link(scenario) do
    Supervisor.start_link(__MODULE__, scenario,
      name: Scenario.System.via_scenario_name(scenario.name)
    )
  end

  @impl true
  def init(scenario) do
    Scenario.System.register_scenario(scenario.name)

    children = [
      {DynamicSupervisor,
       name: Scenario.System.via_worker_sup_name(scenario.name), strategy: :one_for_one},
      {Scenario.StartTask, scenario},
      {Task,
       fn ->
         :timer.sleep(scenario.duration)
         Task.start(Scenario.System, :stop_scenario, [scenario.name])
       end}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
