defmodule Hailstorm.Lobby.Listing do
  @moduledoc """
  Repeatedly subscribe then unsubscribe after a bit to the list of lobbies
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
        {:ok, state}

      %{"commandId" => "lobby/subscribeList", "type" => "response", "status" => "success"} ->
        time = 500 + :rand.uniform(1_000)
        :timer.send_after(time, :unsubscribe_list)
        {:ok, state}

      %{"commandId" => "lobby/unsubscribeList", "type" => "response", "status" => "success"} ->
        time = 500 + :rand.uniform(1_000)
        :timer.send_after(time, :subscribe_list)
        {:ok, state}
    end
  end

  def handle_info(:subscribe_list, state) do
    msg = TachyonWorker.request("lobby/subscribeList") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end

  def handle_info(:unsubscribe_list, state) do
    msg = TachyonWorker.request("lobby/unsubscribeList") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end
end
