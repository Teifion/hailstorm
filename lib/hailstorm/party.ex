defmodule Hailstorm.Party do
  use WebSockex
  require Logger

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

    state = %{scenario: arg.scenario, data: arg.data, status: :connecting}

    WebSockex.start_link("ws://localhost:4000/tachyon", __MODULE__, state, conn_opts)
  end

  def shutdown(pid), do: WebSockex.cast(pid, :shutdown)

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

  def handle_frame({:text, msg}, state) do
    parsed = Jason.decode!(msg)

    case parsed do
      %{"commandId" => "user/self"} ->
        if parsed["data"]["user"]["party"] == nil,
          do: send(self(), :create_party),
          else: send(self(), :leave_party)

        {:ok, state}

      %{"commandId" => "party/create", "type" => "response", "status" => "success"} ->
        state = Map.put(state, :party_id, parsed["data"]["partyId"])
        :telemetry.execute([:hailstorm, :party_count], %{count: 1})
        :timer.send_after(300, :leave_party)
        {:ok, state}

      %{"commandId" => "party/leave", "type" => "response"} ->
        :timer.send_after(300, :create_party)
        :telemetry.execute([:hailstorm, :party_count], %{count: -1})
        {:ok, Map.delete(state, :party_id)}

      _ ->
        IO.inspect(parsed, label: "ignored message")
        {:ok, state}
    end
  end

  def handle_info(:create_party, state) do
    msg = request("party/create") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:leave_party, state) do
    msg = request("party/leave") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_cast(:shutdown, state) do
    msg = request("system/disconnect") |> Jason.encode!()
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

  defp request(cmd_id),
    do: %{commandId: cmd_id, messageId: to_string(UUIDv7.generate()), type: "request"}
end
