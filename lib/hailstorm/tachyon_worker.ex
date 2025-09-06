defmodule Hailstorm.TachyonWorker do
  @moduledoc """
  abstract away the boilerplate of connection and termination for tachyon
  """

  defmacro __using__(_opts) do
    quote location: :keep do
      use WebSockex

      require Logger

      @doc false
      def start_link(arg) do
        conn_opts = [
          extra_headers: [
            {"authorization", "Bearer #{arg.data["access_token"]}"},
            {"sec-websocket-protocol", "v0.tachyon"}
          ],
          socket_connect_timeout: 10_000,
          handle_initial_conn_failure: true,
          async: true
        ]

        state =
          %{scenario: arg.scenario, data: arg.data, status: :connecting}
          |> Map.merge(init_state(arg) || %{})

        WebSockex.start_link("ws://localhost:4000/tachyon", __MODULE__, state, conn_opts)
      end

      def handle_connect(_conn, state) do
        Logger.metadata(user_id: state.data["id"], label: state.scenario.name)
        Logger.info("connected")
        :telemetry.execute([:hailstorm, :worker_count], %{count: 1})
        {:ok, %{state | status: :running}}
      end

      def handle_disconnect(connection_status_map, state) do
        # do not attempt to reconnect at all (at least for now)
        case state.status do
          :closing ->
            nil

          _ ->
            Logger.warning(
              "disconnecting because #{inspect(connection_status_map.reason)} #{inspect(state)}"
            )

            :telemetry.execute([:hailstorm, :worker_error], %{count: 1})
        end

        {:ok, state}
      end

      def handle_ping(_ping_frame, state), do: {:reply, :pong, state}
      def handle_pong(_ping_frame, state), do: {:ok, state}

      def handle_cast(:shutdown, state) do
        msg = Hailstorm.TachyonWorker.request("system/disconnect") |> Jason.encode!()
        WebSockex.cast(self(), :do_shutdown)
        {:reply, {:text, msg}, state}
      end

      def handle_cast(:do_shutdown, state) do
        Logger.info("shutting down")
        {:close, %{state | status: :closing}}
      end

      def terminate(reason, _state) do
        case reason do
          {:local, _} -> nil
          {:remote, 1000, _} -> nil
          {:remote, :closed} -> nil
          :shutdown -> nil
          _ -> Logger.info("ws abnormal termination: #{inspect(reason)}")
        end

        :telemetry.execute([:hailstorm, :worker_count], %{count: -1})
      end

      def shutdown(pid), do: WebSockex.cast(pid, :shutdown)
      def init_state(arg), do: %{}

      def handle_frame(_, state), do: {:ok, state}

      defoverridable init_state: 1, handle_frame: 2
    end
  end

  def request(cmd_id),
    do: %{commandId: cmd_id, messageId: to_string(UUIDv7.generate()), type: "request"}

  def request(cmd_id, data) do
    request(cmd_id)
    |> Map.put(:data, data)
  end
end
