defmodule Hailstorm.Scenario do
  @enforce_keys [:name, :worker]
  defstruct [
    :name,
    :worker,
    worker_args: %{},
    vus: 1,
    duration: 10_000,
    data_path: "./local-users.jsonl",
    rampup_duration: 0,
    rampup_step: 1
  ]

  alias Hailstorm.Scenario.{Reaper, StartTask, System}

  def start_scenario(scenario) do
    result =
      DynamicSupervisor.start_child(
        Hailstorm.TopLevelScenarioSupervisor,
        {Hailstorm.Scenario.Supervisor, scenario}
      )

    case result do
      {:ok, pid} ->
        Reaper.monitor_scenario(scenario.name, pid)
        result

      {:error, {:already_started, pid}} ->
        DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, pid)
        start_scenario(scenario)

      other ->
        other
    end
  end

  def abort_scenario(%__MODULE__{name: name}), do: abort_scenario(name)

  def abort_scenario(scenario_name) when is_binary(scenario_name) do
    case System.scenario_pid(scenario_name) do
      nil -> nil
      p -> abort_scenario(p)
    end
  end

  def abort_scenario(scenario_pid) when is_pid(scenario_pid),
    do: DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, scenario_pid)

  defdelegate stop_scenario(name), to: Hailstorm.Scenario.Reaper

  defdelegate add_workers(scenario), to: StartTask

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
