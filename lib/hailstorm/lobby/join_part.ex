defmodule Hailstorm.Lobby.JoinPart do
  @moduledoc """
  Given a lobby id, join the lobby, then join the first ally team, then leave
  the lobby and repeat in a loop
  """
  require Logger

  use Hailstorm.TachyonWorker
  alias Hailstorm.TachyonWorker

  def init_state(arg) do
    %{lobby_id: arg.lobby_id, lobby_state: :no_lobby}
  end

  def handle_frame({:text, msg}, state) do
    parsed = Jason.decode!(msg)

    case parsed do
      %{"commandId" => "lobby/join", "type" => "response", "status" => "success", "data" => data} ->
        cond do
          get_in(data, ["spectators", to_string(state.data.id)]) != nil ->
            msg = TachyonWorker.request("lobby/joinQueue") |> Jason.encode!()
            {:reply, {:text, msg}, Map.replace!(state, :lobby_state, :spectating)}
        end

      %{"commandId" => "lobby/updated", "type" => "event", "data" => data} ->
        p_id = to_string(state.data.id)

        cond do
          get_in(data, ["players", p_id]) != nil ->
            send_after_jitter(:spectate)
            {:ok, Map.replace!(state, :lobby_state, :playing)}

          get_in(data, ["spectators", p_id]) != nil ->
            send_after_jitter(:join_queue)
            {:ok, Map.replace!(state, :lobby_state, :spectating)}

          true ->
            {:ok, state}
        end

      %{"commandId" => "user/self"} ->
        send(self(), :subscribe_list)

        case parsed["data"]["user"]["currentLobby"] do
          nil ->
            send(self(), :join_lobby)
            {:ok, state}

          _lobby_id ->
            send(self(), :leave_lobby)
            {:ok, state}
        end

      %{"commandId" => cmd_id, "type" => "event"}
      when cmd_id in ["lobby/listUpdated", "lobby/listReset"] ->
        {:ok, state}

      %{"commandId" => _cmd_id, "type" => "response", "status" => "success"} ->
        {:ok, state}

      _ ->
        Logger.warning("ignored message: #{inspect(parsed)}")
        {:ok, state}
    end
  end

  def handle_info(:join_lobby, state) do
    msg = TachyonWorker.request("lobby/join", %{id: state.lobby_id}) |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:subscribe_list, state) do
    msg = TachyonWorker.request("lobby/subscribeList") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:spectate, state) do
    msg = TachyonWorker.request("lobby/spectate") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:join_queue, state) do
    msg = TachyonWorker.request("lobby/joinQueue") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:leave_lobby, state) do
    msg = TachyonWorker.request("lobby/leave") |> Jason.encode!()
    send_after_jitter(:join_lobby)
    {:reply, {:text, msg}, state}
  end

  defp send_after_jitter(msg) do
    :timer.send_after(5000 + :rand.uniform(15_000), msg)
  end
end
