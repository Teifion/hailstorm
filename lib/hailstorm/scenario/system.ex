defmodule Hailstorm.Scenario.System do
  use Supervisor

  require Logger

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

  def via_worker_sup_name(scenario_name), do: via_scenario_name({:supervisor, scenario_name})

  def register_scenario(scenario_name) do
    Registry.register(Hailstorm.ScenarioRegistry, {:scenario, scenario_name}, nil)
  end

  def register_start_task(scenario_name, pid \\ self()) do
    Registry.register(Hailstorm.ScenarioRegistry, {:start_task, scenario_name, pid}, nil)
  end

  def register_worker(scenario_name, user_id, _pid \\ self()) do
    Registry.register(Hailstorm.ScenarioRegistry, {:worker, user_id}, {:worker, scenario_name})
  end

  @doc """
  list of ws connection pid
  """
  def list_workers(scenario_name) do
    spec = [
      {{:_, :"$2", {:"$3", :"$4"}}, [{:==, :"$3", :worker}, {:==, :"$4", scenario_name}], [:"$2"]}
    ]

    Registry.select(Hailstorm.ScenarioRegistry, spec)
  end

  def stop_scenario(scenario_name) do
    case Registry.lookup(Hailstorm.ScenarioRegistry, {:scenario, scenario_name}) do
      [] ->
        nil

      [{pid, _}] ->
        Logger.info("terminating scenario #{scenario_name} under #{inspect(pid)}")
        # because we want to give the worker some time to properly disconnect
        # we first terminate them before removing the entire supervisor.
        # This means we should first stop the start task in case it is still
        # spawning additional workers
        # There is a race there since a worker registers upon connection, so
        # there could be some workers that are starting but not yet registered
        # when we terminate workers.
        # This isn't much of a problem though since tearing down the supervisor
        # ensure no stray task is left behind. It'll just make a few client
        # disconnect abruptly and leave the session around in teiserver.
        terminate_start_tasks(scenario_name)
        terminate_workers(scenario_name)
        DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, pid)
    end
  end

  def scenario_pid(scenario_name) do
    case Registry.lookup(Hailstorm.ScenarioRegistry, scenario_name) do
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

    :error, {:noproc, _} ->
      # same
      []
  end

  def terminate_start_tasks(scenario_name) do
    spec = [
      {{{:"$1", :"$2", :_}, :"$3", :_}, [{:==, :"$1", :start_task}, {:==, :"$2", scenario_name}],
       [:"$3"]}
    ]

    Registry.select(Hailstorm.ScenarioRegistry, spec)
    |> Enum.each(fn pid ->
      Process.exit(pid, :shutdown)
    end)

    :ok
  end

  def terminate_workers(scenario_name) do
    pids = list_workers(scenario_name)

    Task.async(fn ->
      Enum.map(pids, fn pid ->
        ref = Process.monitor(pid)
        Hailstorm.TachyonWorker.shutdown(pid)
        ref
      end)
      |> wait_downs()
    end)
    |> Task.await()
  end

  defp wait_downs([]), do: :ok

  defp wait_downs([ref | rest]) do
    receive do
      {:DOWN, ^ref, :process, _obj, _reason} -> wait_downs(rest)
    end
  end
end
