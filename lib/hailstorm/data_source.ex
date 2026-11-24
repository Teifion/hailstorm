defmodule Hailstorm.DataSource do
  @moduledoc """
  a way to get a single reader over the data file, so that different workers can
  all spawn additional workers with fresh data without duplicates
  """
  alias Hailstorm.TestUser

  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec acquire_user(pid() | nil) :: {:ok, TestUser.t()} | {:error, reason :: term()}
  def acquire_user(pid \\ self()) do
    GenServer.call(__MODULE__, {:acquire_user, pid})
  end

  def release_user(user_id, pid \\ self()) do
    GenServer.call(__MODULE__, {:release_user, user_id, pid})
  end

  def refresh_user(user) do
    cfg = Application.get_env(:hailstorm, :tachyon)
    scheme = if cfg[:use_tls?], do: "https://", else: "http://"
    url = "#{scheme}#{cfg[:host]}:#{cfg[:port]}/oauth/token"

    Logger.debug("refreshing access token")

    params = [
      grant_type: "refresh_token",
      client_id: "generic_lobby",
      refresh_token: user.refresh_token
    ]

    headers = [{"content-type", "application/x-www-form-urlencoded"}]

    resp = Req.post!(url, params: params, headers: headers)

    if resp.status != 200 do
      Logger.error("failed to refresh user #{user.id}: #{resp.status} - #{inspect(resp.body)}")
      raise "Error refreshing token for user #{user.id}: #{resp.body}"
    end

    new_data = resp.body

    {:ok, new_user} =
      TestUser.update_token(
        user,
        new_data["access_token"],
        new_data["refresh_token"]
      )

    new_user
  end

  @impl GenServer
  def init(_arg) do
    Logger.metadata(actor_id: :data_source)
    user_ids = TestUser.all() |> Enum.map(& &1.id)
    {:ok, %{user_ids: user_ids, pool: %{}}}
  end

  @impl GenServer
  def handle_call({:acquire_user, caller_pid}, _from, state) do
    case state.user_ids do
      [] ->
        {:reply, {:error, :no_user}, state}

      [uid | rest] ->
        user = TestUser.get(uid)
        ref = Process.monitor(caller_pid)

        pool =
          Map.update(state.pool, caller_pid, %{ref => uid}, fn refs ->
            Map.put(refs, ref, uid)
          end)

        new_state = %{state | user_ids: rest, pool: pool}
        {:reply, {:ok, user}, new_state}
    end
  end

  def handle_call({:release_user, user_id, owner_pid}, _from, state) do
    case state.pool[owner_pid] do
      nil ->
        {:reply, {:error, :not_owned}, state}

      refs ->
        case Enum.find(refs, fn {_ref, uid} -> uid == user_id end) do
          nil ->
            {:reply, {:error, :not_owned}, state}

          {ref, _} ->
            Process.demonitor(ref, [:flush])

            state =
              state
              |> update_in([:pool, owner_pid], &Map.delete(&1, ref))
              |> Map.put(:user_ids, [user_id | state.user_ids])

            {:reply, :ok, state}
        end
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    uid = get_in(state.pool[pid][ref])
    if uid == nil, do: raise("uid is nil for pid #{inspect(pid)}")
    pool = Map.update!(state.pool, pid, &Map.delete(&1, ref))
    new_state = %{state | user_ids: [uid | state.user_ids], pool: pool}
    {:noreply, new_state}
  end
end
