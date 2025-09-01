defmodule Hailstorm.Scenario do
  @enforce_keys [:name, :worker]
  defstruct [
    :name,
    :worker,
    vus: 1,
    duration: 10_000,
    data_path: "./local-users.jsonl",
    rampup_duration: 0,
    rampup_step: 1
  ]

  def start_scenario(scenario) do
    result =
      DynamicSupervisor.start_child(
        Hailstorm.TopLevelScenarioSupervisor,
        {Hailstorm.Scenario.Supervisor, scenario}
      )

    case result do
      {:ok, pid} ->
        # Hailstorm.Scenario.Supervisor.start_scenario(scenario)
        {:ok, _} =
          DynamicSupervisor.start_child(
            # Hailstorm.Scenario.System.via_scenario_name(scenario.name),
            Hailstorm.TopLevelScenarioSupervisor,
            {Hailstorm.Scenario.Reaper, {scenario, pid}}
          )

        result

      {:error, {:already_started, pid}} ->
        DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, pid)
        start_scenario(scenario)

      other ->
        other
    end
  end
end
