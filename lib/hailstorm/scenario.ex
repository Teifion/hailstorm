defmodule Hailstorm.Scenario do
  @enforce_keys [:name, :worker]
  defstruct [
    :name,
    :worker,
    worker_args: %{},
    vus: 1,
    duration: 10_000,
    rampup_duration: 0,
    rampup_step: 1
  ]

  alias Hailstorm.Scenario.StartTask

  def start_scenario(scenario) do
    result =
      DynamicSupervisor.start_child(
        Hailstorm.TopLevelScenarioSupervisor,
        {Hailstorm.Scenario.Supervisor, scenario}
      )

    case result do
      {:ok, _pid} ->
        result

      {:error, {:already_started, pid}} ->
        DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, pid)
        start_scenario(scenario)

      other ->
        other
    end
  end

  defdelegate stop_scenario(name), to: Hailstorm.Scenario.System

  def add_more_workers(scenario) do
    StartTask.start_worker_task(scenario)
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
  catch
    :error, {:noproc, _} -> 0
  end
end
