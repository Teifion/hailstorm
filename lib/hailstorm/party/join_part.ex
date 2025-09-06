defmodule Hailstorm.Party.JoinPart do
  @moduledoc """
  Given a party ID, repeatedly joins then leave the party
  """

  use Hailstorm.TachyonWorker
  require Logger
  alias Hailstorm.TachyonWorker

  def init_state(arg), do: %{founder_pid: arg.founder_pid}

  def handle_frame({:text, msg}, state) do
    parsed = Jason.decode!(msg)

    case parsed do
      %{"commandId" => cmd_id, "type" => "response", "status" => "success"}
      when cmd_id in ["party/invited"] ->
        {:ok, state}

      %{"commandId" => ev_id, "type" => "event"}
      when ev_id in ["party/updated"] ->
        {:ok, state}

      %{"commandId" => "user/self"} ->
        Hailstorm.Party.Creator.invite(state.founder_pid, state.data["id"])
        {:ok, state}

      %{"commandId" => "party/invited"} ->
        resp =
          TachyonWorker.request("party/acceptInvite", %{partyId: parsed["data"]["party"]["id"]})
          |> Jason.encode!()

        {:reply, {:text, resp}, state}

      %{"commandId" => "party/acceptInvite", "status" => "success"} ->
        jitter = :rand.uniform(100)
        :timer.send_after(10_000 + jitter, :leave_party)
        {:ok, state}

      %{"commandId" => "party/leave", "status" => "success"} ->
        Hailstorm.Party.Creator.invite(state.founder_pid, state.data["id"])
        {:ok, state}

      _ ->
        Logger.warning("ignored message: #{inspect(parsed)}")
        {:ok, state}
    end
  end

  def handle_info(:leave_party, state) do
    msg = TachyonWorker.request("party/leave") |> Jason.encode!()
    {:reply, {:text, msg}, state}
  end
end
