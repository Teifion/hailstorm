defmodule Hailstorm.Scenario.DataSource do
  @moduledoc """
  a way to get a single reader over the data file, so that different workers can
  all spawn additional workers with fresh data without duplicates
  """

  use GenServer

  alias Hailstorm.Scenario.System

  def start_link(scenario) do
    GenServer.start_link(__MODULE__, scenario, name: System.via_data_source_name(scenario.name))
  end

  @spec get_data(String.t(), non_neg_integer()) ::
          {:ok, [{term(), non_neg_integer()}]} | {:error, :not_enough_data}
  def get_data(scenario_name, n) do
    GenServer.call(System.via_data_source_name(scenario_name), {:get_data, n})
  end

  @impl true
  def init(scenario) do
    data =
      File.stream!(scenario.data_path)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.with_index()
      |> Enum.to_list()

    {:ok, data}
  end

  @impl true
  def handle_call({:get_data, n}, _from, data) do
    {result, rest} = Enum.split(data, n)

    if Enum.count(result) != n do
      {:reply, {:error, :not_enough_data}, data}
    else
      {:reply, {:ok, result}, rest}
    end
  end
end
