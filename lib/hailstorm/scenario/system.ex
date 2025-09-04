defmodule Hailstorm.Scenario.System do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children = [
      # to register individual scenarios
      {Registry, name: Hailstorm.ScenarioRegistry, keys: :unique},
      # for the toplevel scenarios
      {DynamicSupervisor, name: Hailstorm.TopLevelScenarioSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def via_scenario_name(scenario_name) do
    {:via, Registry, {Hailstorm.ScenarioRegistry, scenario_name, scenario_name}}
  end

  def via_reaper_name(scenario_name), do: via_scenario_name({:reaper, scenario_name})
  def via_worker_sup_name(scenario_name), do: via_scenario_name({:supervisor, scenario_name})

  def register_start_task(scenario_name) do
    Registry.register(Hailstorm.ScenarioRegistry, {:start_task, scenario_name}, nil)
  end

  def start_task_pid(scenario_name) do
    case Registry.lookup(Hailstorm.ScenarioRegistry, {:start_task, scenario_name}) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  def list_running_scenarios() do
    Registry.select(Hailstorm.ScenarioRegistry, [{{:_, :_, :"$1"}, [], [:"$1"]}])
    |> Enum.filter(fn x -> is_binary(x) end)
  catch
    :error, %ArgumentError{} ->
      # the registry may not be started yet, and then you get ArgumentError
      []
  end
end
