defmodule Hailstorm.TachyonWorker do
  @moduledoc """
  abstract away the boilerplate of connection and termination for tachyon
  """

  alias Ecto.UUID

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Hailstorm.DataSource
      alias Hailstorm.TachyonWorker

      use WebSockex

      require Logger

      @doc false
      def start_link(arg) do
        {:ok, user} = DataSource.acquire_user()

        conn_opts = [
          extra_headers: [
            {"authorization", "Bearer #{user.access_token}"},
            {"sec-websocket-protocol", "v0.tachyon"}
          ],
          socket_connect_timeout: 10_000,
          handle_initial_conn_failure: true,
          async: true
        ]

        state =
          %{scenario: arg.scenario, user: user, status: :connecting, retry_conn_count: 0}
          |> Map.merge(init_state(arg))

        cfg = Application.get_env(:hailstorm, :tachyon)
        scheme = if cfg[:use_tls?], do: "wss://", else: "ws://"
        url = "#{scheme}#{cfg[:host]}:#{cfg[:port]}/tachyon"

        WebSockex.start_link(url, __MODULE__, state, conn_opts)
      end

      def handle_connect(_conn, state) do
        Logger.metadata(user_id: state.user.id, label: state.scenario.name)
        Logger.info("connected")
        Hailstorm.Scenario.System.register_worker(state.scenario.name, state.user.id)
        :telemetry.execute([:hailstorm, :worker_count], %{count: 1})
        {:ok, %{state | status: :running}}
      end

      def handle_disconnect(connection_status_map, state) do
        cond do
          state.status == :closing ->
            {:ok, state}

          state.status == :connecting && Map.get(connection_status_map.reason, :code) == 401 &&
              state.retry_conn_count == 0 ->
            new_user = DataSource.refresh_user(state.user)

            state =
              state
              |> Map.replace!(:user, new_user)
              |> Map.update!(:retry_conn_count, &(&1 + 1))

            new_conn =
              Map.update!(connection_status_map.conn, :extra_headers, fn hdrs ->
                Enum.map(hdrs, fn
                  {"authorization", _any} ->
                    {"authorization", "Bearer #{new_user.access_token}"}

                  h ->
                    h
                end)
              end)

            {:reconnect, new_conn, state}

          true ->
            Logger.warning(
              "disconnecting because #{inspect(connection_status_map.reason)} #{inspect(state)}"
            )

            :telemetry.execute([:hailstorm, :worker_error], %{count: 1}, %{
              scenario: state.scenario.name
            })

            {:ok, state}
        end
      end

      def handle_ping(_ping_frame, state), do: {:reply, :pong, state}
      def handle_pong(_ping_frame, state), do: {:ok, state}

      def handle_cast(:shutdown, state) do
        msg = TachyonWorker.request("system/disconnect") |> Jason.encode!()
        WebSockex.cast(self(), :do_shutdown)
        {:reply, {:text, msg}, state}
      end

      def handle_cast(:do_shutdown, state) do
        Logger.info("shutting down")
        {:close, %{state | status: :closing}}
      end

      def terminate(reason, _state) do
        Logger.info("terminating connection because #{inspect(reason)}")

        case reason do
          {:local, _any} -> nil
          {:remote, 1000, _any} -> nil
          {:remote, :closed} -> nil
          :shutdown -> nil
          _any -> Logger.info("ws abnormal termination: #{inspect(reason)}")
        end

        :telemetry.execute([:hailstorm, :worker_count], %{count: -1})
      end

      def init_state(arg), do: %{}

      def handle_frame(_any, state), do: {:ok, state}

      defoverridable init_state: 1, handle_frame: 2
    end
  end

  def shutdown(pid), do: WebSockex.cast(pid, :shutdown)

  def request(cmd_id),
    do: %{commandId: cmd_id, messageId: to_string(UUID.generate(version: 7)), type: "request"}

  def request(cmd_id, data) do
    request(cmd_id)
    |> Map.put(:data, data)
  end
end
