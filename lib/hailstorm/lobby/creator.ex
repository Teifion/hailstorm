defmodule Hailstorm.Lobby.Creator do
  @moduledoc """
  Create a lobby for 16 players, then spawn 15 additional workers that will
  join and leave the lobby.
  All these processes also subscribe to the lobby list
  """

  use Hailstorm.TachyonWorker
  alias Hailstorm.TachyonWorker
  alias Hailstorm.Scenario
  require Logger

  def handle_frame({:text, msg}, state) do
    parsed = Jason.decode!(msg)

    case parsed do
      %{"commandId" => ev_id, "type" => "event"}
      when ev_id in ["lobby/updated", "lobby/listReset", "lobby/listUpdated"] ->
        {:ok, state}

      %{"commandId" => "user/self"} ->
        send(self(), :subscribe_list)

        case parsed["data"]["user"]["currentLobby"] do
          nil ->
            send(self(), :create_lobby)
            {:ok, state}

          lobby_id ->
            state = Map.put(state, :lobby_id, lobby_id)
            send(self(), :spawn_members)
            {:ok, state}
        end

      %{"commandId" => "lobby/create", "type" => "response", "status" => "success"} ->
        state = Map.put(state, :lobby_id, parsed["data"]["id"])
        send(self(), :spawn_members)
        {:ok, state}

      %{"commandId" => _cmd_id, "type" => "response", "status" => "success"} ->
        {:ok, state}

      _ ->
        Logger.warning("ignored message #{inspect(parsed)}")
        {:ok, state}
    end
  end

  def handle_info(:create_lobby, state) do
    teams = Enum.map(1..16, fn _ -> %{maxPlayers: 1} end)

    data = %{
      name: "test lobby #{state.user.id}",
      mapName: "Avalanche 3.4",
      allyTeamConfig: [
        %{maxTeams: 16, startBox: %{top: 0, bottom: 0, left: 1, right: 1}, teams: teams},
        %{
          maxTeams: 1,
          startBox: %{top: 0, bottom: 0, left: 1, right: 1},
          teams: [%{maxPlayers: 1}]
        }
      ]
    }

    msg = TachyonWorker.request("lobby/create", data) |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:spawn_members, state) do
    lobby_size = if :rand.uniform() <= 0.1, do: 15, else: 3
    scenario = %Scenario{
      name: state.scenario.name,
      worker: Hailstorm.Lobby.JoinPart,
      worker_args: %{lobby_id: state.lobby_id},
      vus: lobby_size,
      rampup_duration: 15_000
    }

    Logger.info("spawning #{scenario.vus} members for lobby #{state.lobby_id}")
    Scenario.add_workers(scenario)
    {:ok, state}
  end

  def handle_info(:subscribe_list, state) do
    msg = TachyonWorker.request("lobby/subscribeList") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end
end
