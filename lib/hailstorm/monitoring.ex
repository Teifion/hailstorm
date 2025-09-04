defmodule Hailstorm.Monitoring do
  use PromEx.Plugin

  @worker_count_metrics_event_name [:prom_ex, :plugin, :hailstorm, :worker]

  @impl true
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
  def execute_hailstorm_worker_metrics() do
    count = Hailstorm.Scenario.count_workers()

    :telemetry.execute(@worker_count_metrics_event_name, %{count: count}, %{})
  end
end
