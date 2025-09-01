defmodule Hailstorm.Scenario.Reaper do
  @moduledoc """
  monitor workers for a scenario and terminate the entire supervision tree
  once they are all done.
  """

  use GenServer
  require Logger
  alias Hailstorm.Scenario

  def via_tuple(scenario_name) do
    Scenario.System.via_reaper_name(scenario_name)
  end

  def monitor_worker(scenario_name, pid) do
    GenServer.call(via_tuple(scenario_name), {:monitor, pid})
  end

  def start_link({scenario, _scenario_pid} = arg) do
    GenServer.start_link(__MODULE__, arg, name: via_tuple(scenario.name))
  end

  @impl true
  def init({scenario, scenario_pid}) do
    :timer.send_after(scenario.duration, :shutdown_workers)
    ref = Process.monitor(scenario_pid)

    {:ok,
     %{scenario: scenario, terminated_count: 0, scenario_pid: scenario_pid, scenario_ref: ref}}
  end

  @impl true
  def handle_call({:monitor, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, state) when ref == state.scenario_ref do
    # the supervision tree for the entire scenario is no more, so the reaper process
    # has no purpose to serve anymore
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, _, _}, state) do
    state = Map.update!(state, :terminated_count, &(&1 + 1))

    if state.terminated_count == state.scenario.vus,
      do: {:noreply, state, {:continue, :terminate}},
      else: {:noreply, state}
  end

  @impl true
  def handle_info(:shutdown_workers, state) do
    Logger.info("Stopping workers for scenario #{state.scenario.name}")

    # # in case the task that responsible for spawning workers
    # # is still running, stop that first
    # Process.exit(start_pid, :kill)
    case Scenario.System.start_task_pid(state.scenario.name) do
      pid when is_pid(pid) -> Process.exit(pid, :kill)
      _ -> nil
    end

    DynamicSupervisor.which_children(Scenario.System.via_worker_sup_name(state.scenario.name))
    |> Enum.each(fn
      {_, pid, _, _} when is_pid(pid) -> state.scenario.worker.shutdown(pid)
      _ -> nil
    end)

    {:noreply, state}
  end

  @impl true
  def handle_continue(:terminate, state) do
    Logger.info("terminating supervisor for scenario #{state.scenario.name}")
    # Scenario.Supervisor.stop_scenario(state.scenario.name)
    :ok = DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, state.scenario_pid)
    {:stop, :normal, state}
  end
end
