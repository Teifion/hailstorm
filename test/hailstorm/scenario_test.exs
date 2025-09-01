defmodule Hailstorm.ScenarioTest do
  use ExUnit.Case

  describe "rampup" do
    import Hailstorm.Scenario.Supervisor, only: [rampup: 3]
    def check_total_actions([], total, _, _) when total <= 0, do: :ok

    def check_total_actions(actions, total, _, _) do
      t =
        for action <- actions do
          case action do
            {:spawn, i} -> i
            {:sleep, _} -> 0
          end
        end
        |> Enum.sum()

      if t == total,
        do: :ok,
        else: {:error, "Expected #{total} actions but got #{t}"}
    end

    def check_total_sleep(actions, _, duration, _) do
      t =
        for action <- actions do
          case action do
            {:spawn, _} -> 0
            {:sleep, i} -> i
          end
        end
        |> Enum.sum()

      if t <= duration,
        do: :ok,
        else: {:error, "Expected at most #{duration} sleep time but got #{t}"}
    end

    @doc """
    make sure there is no sleep at either end
    """
    def check_no_wasted_sleep(actions, _, _, _) do
      case {actions, Enum.reverse(actions)} do
        {[{:sleep, _} | _], _} -> {:error, "Cannot start by sleeping"}
        {_, [{:sleep, _} | _]} -> {:error, "Cannot end with sleep"}
        _ -> :ok
      end
    end

    def check_valid_sleeps(actions, _, _, step) do
      problem =
        Enum.find(actions, fn
          {:spawn, _} ->
            false

          {:sleep, t} ->
            not (is_integer(t) && rem(t, step) == 0)
        end)

      case problem do
        nil -> :ok
        {:sleep, t} -> {:error, "found invalid sleep time: #{t}, not a multiple of step #{step}"}
      end
    end

    def check_actions(actions, total, duration, step) do
      checks = [
        &check_total_actions/4,
        &check_total_sleep/4,
        &check_no_wasted_sleep/4,
        &check_valid_sleeps/4
      ]

      errors =
        Enum.reduce(
          checks,
          [],
          fn check, errors ->
            case check.(actions, total, duration, step) do
              :ok -> errors
              {:error, msg} -> [msg | errors]
            end
          end
        )

      case errors do
        [] -> :ok
        _ -> {:error, errors}
      end
    end

    test "no actions" do
      assert rampup(0, 10, 1) == []
    end

    test "negative actions" do
      assert rampup(-1, 10, 1) == []
    end

    test "single action" do
      assert rampup(1, 10, 1) == [{:spawn, 1}]
    end

    test "no duration" do
      assert rampup(1, 0, 1) == [{:spawn, 1}]
      assert rampup(10, 0, 1) == [{:spawn, 10}]
    end

    test "as many actions as duration" do
      assert rampup(3, 3, 1) == [
               {:spawn, 1},
               {:sleep, 1},
               {:spawn, 1},
               {:sleep, 2},
               {:spawn, 1}
             ]
    end

    test "duration one less than action" do
      assert rampup(3, 2, 1) == [
               {:spawn, 1},
               {:sleep, 1},
               {:spawn, 1},
               {:sleep, 1},
               {:spawn, 1}
             ]
    end

    test "evenly distributed actions" do
      assert rampup(2, 10, 1) == [{:spawn, 1}, {:sleep, 10}, {:spawn, 1}]
    end

    test "step greater than duration" do
      assert rampup(2, 1, 10) == [{:spawn, 2}]
    end

    test "more actions than step in duration" do
      assert rampup(5, 3, 1) == [
               {:spawn, 2},
               {:sleep, 1},
               {:spawn, 1},
               {:sleep, 1},
               {:spawn, 1},
               {:sleep, 1},
               {:spawn, 1}
             ]
    end

    test "less actions than step in duration" do
      assert rampup(2, 3, 1) == [
               {:spawn, 1},
               {:sleep, 3},
               {:spawn, 1}
             ]
    end

    test "step equal to duration" do
      assert rampup(2, 2, 2) == [{:spawn, 1}, {:sleep, 2}, {:spawn, 1}]
    end

    test "various random values" do
      for n <- Enum.concat(-1..5, [10, 11, 13, 20, 399, 400, 401]),
          duration <- Enum.concat(0..10, [11, 13, 14, 15, 20, 200, 399, 400, 401]),
          step <- [1, 2, 3, 5, 10, 11, 100, 400, 1000] do
        actions = rampup(n, duration, step)

        case check_actions(actions, n, duration, step) do
          :ok ->
            nil

          {:error, err} ->
            flunk(
              "check_actions(#{n}, #{duration}, #{step}) produced #{inspect(actions)} and failed because #{err}"
            )
        end
      end
    end
  end
end
