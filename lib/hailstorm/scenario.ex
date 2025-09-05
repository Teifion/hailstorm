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
        {:ok, _} =
          DynamicSupervisor.start_child(
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

  defdelegate list_running_scenarios(), to: Hailstorm.Scenario.System

  def count_workers() do
    list_running_scenarios()
    |> Enum.map(&count_workers/1)
    |> Enum.sum()
  end

  def count_workers(%__MODULE__{} = scenario), do: count_workers(scenario.name)

  def count_workers(name) do
    DynamicSupervisor.count_children(Hailstorm.Scenario.System.via_worker_sup_name(name))
    |> Map.get(:workers)
  end
end
