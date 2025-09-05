defmodule Hailstorm.Scenario.StartTask do
  use Task
  alias Hailstorm.Scenario

  def start_link(scenario) do
    Task.start_link(__MODULE__, :start_workers, [scenario])
  end

  def start_workers(scenario) do
    Scenario.System.register_start_task(scenario.name)
    plan = rampup(scenario.vus, scenario.rampup_duration, scenario.rampup_step)

    {:ok, data} = Scenario.DataSource.get_data(scenario.name, scenario.vus)

    execute_plan(plan, data, scenario)
  end

  defp execute_plan([], _, _), do: :ok

  defp execute_plan([{:spawn, n} | rest], data, scenario) do
    {data, rest_data} = Enum.split(data, n)

    for {d, _idx} <- data do
      spec =
        scenario.worker.child_spec(%{scenario: scenario, data: d})
        # don't restart workers (for now)
        |> Map.put(:restart, :temporary)

      {:ok, pid} =
        DynamicSupervisor.start_child(Scenario.System.via_worker_sup_name(scenario.name), spec)

      Scenario.Reaper.monitor_worker(scenario.name, pid)
    end

    execute_plan(rest, rest_data, scenario)
  end

  defp execute_plan([{:sleep, t} | rest], data, scenario) do
    :timer.sleep(t)
    execute_plan(rest, data, scenario)
  end

  @doc """
  returns a list of action so that over `total_duration`, `total_actions` are
  evenly spread, while sleeping by durations multiple of `sleep_step`
  """
  @spec rampup(total_actions :: integer(), total_duration :: number(), sleep_step :: integer()) ::
          [
            {:spawn, non_neg_integer()} | {:sleep, integer()}
          ]
  def rampup(n, t, step \\ 1) do
    cond do
      t == 0 || n == 1 -> [{:spawn, n}]
      true -> do_rampup(n, t, step, t / (n - 1), 0, [])
    end
  end

  defp do_rampup(n, remaining, step, dt, time_to_wait, actions) do
    cond do
      n <= 0 ->
        Enum.reverse(actions)

      remaining < step ->
        do_rampup(0, remaining, step, dt, time_to_wait, [{:spawn, n} | actions])

      time_to_wait >= step ->
        ttw_i = trunc(time_to_wait)
        to_wait = div(ttw_i, step) * step
        actions = [{:sleep, to_wait} | actions]
        do_rampup(n, remaining - to_wait, step, dt, time_to_wait - to_wait, actions)

      true ->
        to_spawn = ((step - time_to_wait) / dt) |> ceil() |> min(n)
        to_wait = to_spawn * dt

        if to_spawn <= 0 do
          # by that point, step - time_to_wait ≠ 0, and then with ceil(x)
          # `to_spawn` is guaranteed to be greater than 0
          raise "unreachable"
        end

        actions = [{:spawn, to_spawn} | actions]
        do_rampup(n - to_spawn, remaining, step, dt, time_to_wait + to_wait, actions)
    end
  end
end
