defmodule Hailstorm.Monitoring do
  @moduledoc false

  alias Hailstorm.Scenario

  use PromEx.Plugin

  @worker_count_metrics_event_name [:prom_ex, :plugin, :hailstorm, :worker]

  @impl Plugin
  def event_metrics(_opts) do
    Event.build(
      :hailstorm_even_metrics,
      [
        counter(
          [:hailstorm, :worker_error],
          event_name: [:hailstorm, :worker_error],
          measurement: fn _m -> 1 end,
          tags: [:scenario]
        )
      ]
    )
  end

  @impl Plugin
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 1_000)

    [
      hailstorm_worker_metrics(poll_rate)
    ]
  end

  defp hailstorm_worker_metrics(poll_rate) do
    Polling.build(
      :hailstorm_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_hailstorm_worker_metrics, []},
      [
        last_value(
          [:hailstorm, :worker],
          event_name: @worker_count_metrics_event_name,
          description: "how many workers across all scenarios",
          measurement: :count
        )
      ]
    )
  end

  @doc false
  def execute_hailstorm_worker_metrics do
    count = Scenario.count_workers()

    :telemetry.execute(@worker_count_metrics_event_name, %{count: count}, %{})
  end
end
