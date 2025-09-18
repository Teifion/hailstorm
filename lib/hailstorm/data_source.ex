defmodule Hailstorm.DataSource do
  @moduledoc """
  a way to get a single reader over the data file, so that different workers can
  all spawn additional workers with fresh data without duplicates
  """

  use GenServer

  alias Hailstorm.TestUser

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get_users(non_neg_integer()) ::
          {:ok, [{TestUser.t(), non_neg_integer()}]} | {:error, :not_enough_data}
  def get_users(n) do
    GenServer.call(__MODULE__, {:get_users, n})
  end

  @doc """
  reset the index on the data
  """
  def reset(), do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(_arg) do
    {:ok, initial_data()}
  end

  @impl true
  def handle_call({:get_users, n}, _from, data) do
    {result, rest} = Enum.split(data, n)

    if Enum.count(result) != n do
      {:reply, {:error, :not_enough_data}, data}
    else
      {:reply, {:ok, result}, rest}
    end
  end

  def handle_call(:reset, _from, _data) do
    {:reply, :ok, initial_data()}
  end

  defp initial_data() do
    TestUser.all() |> Enum.with_index()
  end
end
