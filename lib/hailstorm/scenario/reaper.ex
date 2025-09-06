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

  def monitor_scenario(scenario_name, pid) do
    GenServer.cast(via_tuple(scenario_name), {:monitor_scenario, pid})
  end

  def monitor_worker(scenario_name, pid) do
    GenServer.cast(via_tuple(scenario_name), {:monitor, pid})
  end

  def stop_scenario(scenario_name) do
    GenServer.call(via_tuple(scenario_name), :stop_scenario)
  catch
    :exit, {:noproc, _} -> :ok
  end

  def start_link(scenario) do
    GenServer.start_link(__MODULE__, scenario, name: via_tuple(scenario.name))
  end

  @impl true
  def init(scenario) do
    Logger.metadata(label: "#{scenario.name}", user_id: "reaper")
    :timer.send_after(scenario.duration, :shutdown_workers)

    {:ok,
     %{
       scenario: scenario,
       monitored_count: 0,
       scenario_pid: nil,
       scenario_ref: nil,
       stop_callers: []
     }}
  end

  @impl true
  def handle_call(:stop_scenario, from, state) do
    if state.stop_callers == [], do: shutdown_workers(state)
    state = Map.update!(state, :stop_callers, fn cs -> [from | cs] end)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:monitor_scenario, pid}, state) do
    ref = Process.monitor(pid)
    {:noreply, %{state | scenario_pid: pid, scenario_ref: ref}}
  end

  def handle_cast({:monitor, pid}, state) do
    Process.monitor(pid)
    {:noreply, Map.update!(state, :monitored_count, &(&1 + 1))}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, state) when ref == state.scenario_ref do
    # the supervision tree for the entire scenario is no more, so the reaper process
    # has no purpose to serve anymore
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    if reason not in [:normal, :shutdown, {:remote, :closed}],
      do: Logger.warning("worker down because: #{inspect(reason)}")

    state = Map.update!(state, :monitored_count, &(&1 - 1))

    if state.monitored_count == 0,
      do: {:noreply, state, {:continue, :terminate}},
      else: {:noreply, state}
  end

  @impl true
  def handle_info(:shutdown_workers, state) do
    shutdown_workers(state)
    {:noreply, state}
  end

  @impl true
  def handle_continue(:terminate, state) do
    Logger.info("terminating supervisor for scenario #{state.scenario.name}")

    for caller <- state.stop_callers, do: GenServer.reply(caller, :ok)

    # because this process is itself under this supervisor, terminating it is going
    # to abruptly terminate the reaper process as well.
    spawn(fn ->
      DynamicSupervisor.terminate_child(Hailstorm.TopLevelScenarioSupervisor, state.scenario_pid)
    end)

    {:stop, :normal, state}
  end

  defp shutdown_workers(state) do
    Logger.info("Stopping workers for scenario #{state.scenario.name}")

    # in case the task that responsible for spawning workers
    # is still running, stop that first
    case Scenario.System.start_task_pid(state.scenario.name) do
      pid when is_pid(pid) -> Process.exit(pid, :kill)
      _ -> nil
    end

    DynamicSupervisor.which_children(Scenario.System.via_worker_sup_name(state.scenario.name))
    |> Enum.each(fn
      {_, pid, _, _} when is_pid(pid) -> state.scenario.worker.shutdown(pid)
      _ -> nil
    end)
  end
end
