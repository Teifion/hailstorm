defmodule Hailstorm.Party.Creator do
  @moduledoc """
  Creates a party, then spawns additional workers (Hailstorm.Party.JoinPart)
  to repeatedly join and leave the party.
  """

  use WebSockex
  require Logger
  alias Hailstorm.Scenario

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

  # shortcut for a member to request an invite. It's simpler than tracking
  # the party state from the creator point of view
  def invite(pid, user_id), do: WebSockex.cast(pid, {:invite, user_id})

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
      %{"commandId" => cmd_id, "type" => "response", "status" => "success"}
      when cmd_id in ["user/subscribeUpdates", "party/invite"] ->
        {:ok, state}

      %{"commandId" => ev_id, "type" => "event"}
      when ev_id in ["party/updated"] ->
        {:ok, state}

      %{"commandId" => "user/self"} ->
        case parsed["data"]["user"]["party"] do
          nil ->
            send(self(), :create_party)
            {:ok, state}

          party ->
            state = Map.put(state, :party_id, party["id"])
            send(self(), :spawn_members)
            {:ok, state}
        end

      %{"commandId" => "party/create", "type" => "response", "status" => "success"} ->
        state = Map.put(state, :party_id, parsed["data"]["partyId"])
        send(self(), :spawn_members)
        {:ok, state}

      _ ->
        Logger.warning("ignored message: #{inspect(parsed)}")
        {:ok, state}
    end
  end

  def handle_info(:create_party, state) do
    msg = request("party/create") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:spawn_members, state) do
    scenario = %Scenario{
      name: state.scenario.name,
      worker: Hailstorm.Party.JoinPart,
      worker_args: %{founder_pid: self()},
      vus: 4
    }

    Logger.info("spawning #{scenario.vus} members for party #{state.party_id}")
    Scenario.add_workers(scenario)
    {:ok, state}
  end

  def handle_info({:invite, user_id}, state) do
    msg = request("party/invite", %{userId: user_id}) |> Jason.encode!()
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

  def handle_cast({:invite, user_id}, state) do
    msg = request("party/invite", %{userId: to_string(user_id)}) |> Jason.encode!()
    {:reply, {:text, msg}, state}
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

  defp request(cmd_id, data) do
    request(cmd_id)
    |> Map.put(:data, data)
  end
end
