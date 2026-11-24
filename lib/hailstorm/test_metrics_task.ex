defmodule Hailstorm.TestMetricsTask do
  @moduledoc false

  use Task

  def start_link(step) do
    Task.start_link(__MODULE__, :run, [step])
  end

  def run(step) do
    val = if :rand.uniform() <= 0.6, do: 0, else: step

    :telemetry.execute([:tachyon, :test], %{value: val})
    :timer.sleep(1_000)
    run(step)
  end
end
