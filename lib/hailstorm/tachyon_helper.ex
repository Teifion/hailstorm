defmodule Hailstorm.TachyonHelper do
  require Logger
  alias Hailstorm.TachyonWsServer, as: Ws
  alias Hailstorm.ListenerServer

  @type sslsocket() :: {:sslsocket, any, any}

  @spec get_host() :: binary()
  def get_host(), do: Application.get_env(:hailstorm, Hailstorm)[:host]

  @spec get_websocket_url(String.t()) :: non_neg_integer()
  def get_websocket_url(token_value) do
    query = URI.encode_query(%{
      "token" => token_value,
      "client_hash" => "HailstormHash",
      "client_name" => "Hailstorm"
    })
    Application.get_env(:hailstorm, Hailstorm)[:websocket_url] <> "?#{query}"
  end

  @spec get_password() :: String.t()
  def get_password(), do: Application.get_env(:hailstorm, Hailstorm)[:password]

  defp cleanup_params(params) do
    email = Map.get(params, :email, params.name) <> "@hailstorm_tachyon"
    Map.put(params, :email, email)
  end

  @spec new_connection(map()) :: {:ok, pid(), pid()} | {:error, String.t()}
  def new_connection(params) do
    params = cleanup_params(params)

    with :ok <- create_user(params),
      :ok <- update_user(params.email, Map.merge(%{verified: true}, params[:update] || %{
        friends: [],
        friend_requests: [],
        ignored: [],
        avoided: []
      })),
      {:ok, token} <- get_token(params),
      listener <- ListenerServer.new_listener(),
      {:ok, ws} <- get_socket(token, listener)
      # :ok <- login(ws, params.email)
    do
      {:ok, ws, listener}
    else
      failure -> failure
    end
  end

  @spec get_socket(String.t(), pid()) :: {:ok, sslsocket()} | {:error, any}
  defp get_socket(token, listener) do
    Ws.start_link(get_websocket_url(token), listener)
  end

  @spec create_user(map()) :: :ok | {:error, String.t()}
  defp create_user(params) do
    url = [
      Application.get_env(:hailstorm, Hailstorm)[:host_web_url],
      "teiserver/api/hailstorm/create_user"
    ] |> Enum.join("/")

    data = params
      |> Map.put("password", get_password())
      |> Jason.encode!

    result = case HTTPoison.post(url, data, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 201} = resp} ->
        resp.body |> Jason.decode!
      {_, resp} ->
        %{"result" => "failure", "reason" => "bad request (code: #{resp.status_code})"}
    end

    case result do
      %{"result" => "failure"} ->
        {:error, "Error creating user #{params.email} because #{result["reason"]}"}
      %{"userid" => _userid} ->
        :ok
    end
  end

  @spec get_token(map()) :: {:ok, String.t()} | {:error, String.t()}
  defp get_token(params) do
    url = [
      Application.get_env(:hailstorm, Hailstorm)[:host_web_url],
      "teiserver/api/request_token"
    ] |> Enum.join("/")

    data = params
      |> Map.put("password", get_password())
      |> Jason.encode!

    result = case HTTPoison.post(url, data, [{"Content-Type", "application/json"}]) do
      {:ok, resp} ->
        resp.body |> Jason.decode!
      {:error, _resp} ->
        %{"result" => "failure", "reason" => "bad request"}
    end

    case result do
      %{"result" => "failure", "reason" => reason} ->
        {:error, "Error getting user token for '#{params.email}', because #{reason}"}
      %{"result" => "success", "token_value" => token_value} ->
        {:ok, token_value}
    end
  end

  @spec update_user(String.t(), map()) :: :ok | {:error, String.t()}
  defp update_user(email, params) do
    url = [
      Application.get_env(:hailstorm, Hailstorm)[:host_web_url],
      "teiserver/api/hailstorm/ts_update_user"
    ] |> Enum.join("/")

    data = %{
      email: email,
      attrs: params
    } |> Jason.encode!

    result = case HTTPoison.post(url, data, [{"Content-Type", "application/json"}]) do
      {:ok, resp} ->
        resp.body |> Jason.decode!
      {:error, _resp} ->
        %{"result" => "failure", "reason" => "bad request"}
    end

    case result do
      %{"result" => "failure"} ->
        {:error, "Error updating user #{email} at '#{result["stage"]}' because #{result["reason"]}"}
      %{"result" => "success"} ->
        :ok
    end
  end

  @spec tachyon_send(pid(), map) :: :ok
  @spec tachyon_send(pid(), map, list) :: :ok
  def tachyon_send(ws, data, metadata \\ []) do
    json = Jason.encode!(data)
    WebSockex.send_frame(ws, {:text, json})
  end

  @spec read_messages(pid) :: list
  def read_messages(ls), do: read_messages(ls, 500)

  @spec read_messages(pid, non_neg_integer()) :: list
  def read_messages(ls, timeout) do
    do_read_messages(ls, timeout, System.system_time(:millisecond))
  end

  @spec do_read_messages(pid, non_neg_integer(), non_neg_integer()) :: list
  defp do_read_messages(ls, timeout, start_time) do
    case ListenerServer.read(ls) do
      [] ->
        time_taken = System.system_time(:millisecond) - start_time
        if time_taken > timeout do
          []
        else
          :timer.sleep(50)
          do_read_messages(ls, timeout, start_time)
        end

      result ->
        result
    end
  end

  @spec pop_messages(pid) :: list
  def pop_messages(ls), do: pop_messages(ls, 500)

  @spec pop_messages(pid, non_neg_integer()) :: list
  def pop_messages(ls, timeout) do
    do_pop_messages(ls, timeout, System.system_time(:millisecond))
  end

  @spec do_pop_messages(pid, non_neg_integer(), non_neg_integer()) :: list
  defp do_pop_messages(ls, timeout, start_time) do
    case ListenerServer.pop(ls) do
      [] ->
        time_taken = System.system_time(:millisecond) - start_time
        if time_taken > timeout do
          []
        else
          :timer.sleep(50)
          do_pop_messages(ls, timeout, start_time)
        end

      result ->
        result
    end
  end

  def valid?(%{"command" => command, "data" => data} = o) do
    schema = get_schema(command)

    IO.puts ""
    IO.inspect schema
    IO.inspect o
    IO.inspect ExJsonSchema.Validator.validate(schema, o)
    IO.puts ""

    case ExJsonSchema.Validator.validate(schema, o) do
      :ok ->
        true
      failure ->
        failure
    end
  end

  defp get_schema(command) do
    ConCache.get(:tachyon_schemas, command)
  end

  defmacro __using__(_opts) do
    quote do
      import Hailstorm.TachyonHelper, only: [
        tachyon_send: 2,
        read_messages: 1,
        read_messages: 2,
        pop_messages: 1,
        pop_messages: 2,
        new_connection: 1,
        valid?: 1
      ]
      alias Hailstorm.TachyonHelper
      alias Tachyon
    end
  end
end