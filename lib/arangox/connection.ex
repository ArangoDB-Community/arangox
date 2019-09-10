defmodule Arangox.Connection do
  @moduledoc false

  use DBConnection

  alias Arangox.{
    Client,
    Error,
    Request,
    Response
  }

  @type t :: %__MODULE__{
          socket: any,
          client: module,
          endpoint: binary,
          database: binary,
          auth?: boolean,
          username: binary,
          password: binary,
          headers: list(Arangox.header()),
          read_only?: boolean
        }

  @enforce_keys [:socket, :client, :endpoint]

  defstruct [
    :socket,
    :client,
    :endpoint,
    :database,
    auth?: true,
    username: "root",
    password: "",
    headers: [],
    read_only?: false
  ]

  @spec new(any, module, binary, [Arangox.start_option()]) :: t
  def new(socket, client, endpoint, opts) do
    __MODULE__
    |> struct(opts)
    |> Map.put(:socket, socket)
    |> Map.put(:client, client)
    |> Map.put(:endpoint, endpoint)
  end

  @default_client Client.Gun
  @default_endpoint "http://localhost:8529"
  # @header_endpoint "x-arango-endpoint"
  @header_dirty_read {"x-arango-allow-dirty-read", "true"}
  @request_ping %Request{method: :options, path: "/"}
  @request_availability %Request{method: :get, path: "/_admin/server/availability"}
  @request_mode %Request{method: :get, path: "/_admin/server/mode"}
  @exception_no_trans %Error{message: "ArangoDB is not a transactional database"}

  @impl true
  def connect(opts) do
    client = Keyword.get(opts, :http_client, @default_client)
    endpoints = Keyword.get(opts, :endpoints, [@default_endpoint])

    with(
      {:ok, %__MODULE__{} = state} <- do_connect(client, endpoints, opts),
      {:ok, %__MODULE__{} = state} <- resolve_auth(state),
      {:ok, %__MODULE__{} = state} <- check_availability(state)
    ) do
      {:ok, state}
    else
      {:connect, endpoint} ->
        connect(Keyword.put(opts, :endpoints, [endpoint]))

      {:error, reason} when reason in [:failed, :unavailable] ->
        connect(Keyword.put(opts, :endpoints, tl(endpoints)))

      {:error, %_{} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, %Error{message: reason}}
    end
  end

  defp do_connect(client, [], opts) do
    {:error,
     new(nil, client, nil, opts)
     |> exception("all endpoints are unavailable")
     |> failover_callback(opts)}
  end

  defp do_connect(client, endpoints, opts) when is_list(endpoints) do
    endpoint = hd(endpoints)

    case Client.connect(client, endpoint, opts) do
      {:ok, socket} ->
        {:ok, new(socket, client, endpoint, opts)}

      {:error, reason} ->
        new(nil, client, endpoint, opts)
        |> exception(reason)
        |> failover_callback(opts)

        {:error, :failed}
    end
  end

  defp failover_callback(%_{} = exception, opts) do
    case Keyword.get(opts, :failover_callback) do
      {mod, fun, args} ->
        apply(mod, fun, [exception | args])

        exception

      fun when is_function(fun, 1) ->
        fun.(exception)

        exception

      _invalid_callback ->
        exception
    end
  end

  defp resolve_auth(%__MODULE__{auth?: false} = state),
    do: {:ok, %{state | username: nil, password: nil}}

  defp resolve_auth(%__MODULE__{username: username, password: password} = state) do
    base64_encoded = Base.encode64("#{username}:#{password}")

    {:ok, put_header(state, {"authorization", "Basic #{base64_encoded}"})}
  end

  defp check_availability(%__MODULE__{read_only?: true} = state) do
    state = put_header(state, @header_dirty_read)
    request = put_headers(@request_mode, state.headers)
    result = Client.request(request, state)

    with(
      {:ok, %Response{status: 200} = response, state} <- result,
      response <- DBConnection.Query.decode(@request_mode, response, []),
      %Response{body: %{"mode" => "readonly"}} <- response
    ) do
      {:ok, state}
    else
      {:error, _reason, _state} ->
        {:error, :failed}

      _ ->
        {:error, :unavailable}
    end
  end

  defp check_availability(%__MODULE__{} = state) do
    request = put_headers(@request_availability, state.headers)
    # result = Client.request(request, state)

    # if a server is running inside a container, it's x-arango-endpoint
    # header will need to be mapped to a different value somehow
    with(
      result <- Client.request(request, state),
      {:ok, %Response{status: 503}, _state} <- result
      # {:ok, %Response{status: 503} = response, _state} <- result
      # endpoint when is_binary(endpoint) <- get_header(response, @header_endpoint)
    ) do
      # {:connect, endpoint}
      {:error, :unavailable}
    else
      {:ok, %Response{status: _status}, state} ->
        {:ok, state}

      {:error, reason, _state} ->
        {:error, reason}

        # nil ->
        #   {:error, :unavailable}
    end
  end

  @impl true
  def disconnect(_reason, %__MODULE__{} = state), do: Client.close(state)

  @impl true
  def checkout(%__MODULE__{} = state), do: {:ok, state}

  @impl true
  def checkin(state), do: {:ok, state}

  # These don't do anything, but are required for `DBConnection.transaction/3` to work

  @impl true
  def handle_begin(_opts, %__MODULE__{} = state), do: {:ok, :result, state}

  @impl true
  def handle_commit(_opts, %__MODULE__{} = state), do: {:ok, :result, state}

  # Execution callbacks

  defmacrop exec_case(condition, do: body) do
    {:case, [], [condition, [do: exec_cases_before() ++ body ++ exec_cases_after()]]}
  end

  def exec_cases_before do
    quote do
      {:ok, %Response{status: 505} = response, state} ->
        {:disconnect, exception(state, response), state}

      {:ok, %Response{status: 503} = response, state} ->
        {:disconnect, exception(state, response), state}

      {:ok, %Response{status: 405} = response, state} ->
        {:disconnect, exception(state, response), state}

      {:ok, %Response{status: 403} = response, state} ->
        {:error, exception(state, response), state}

      {:ok, %Response{status: 401} = response, state} ->
        {:disconnect, exception(state, response), state}
    end
  end

  def exec_cases_after do
    quote do
      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, %_{} = reason, state} ->
        {:error, reason, state}

      {:error, reason, state} ->
        {:error, exception(state, reason), state}
    end
  end

  @impl true
  def handle_execute(_q, %Request{} = request, _opts, %__MODULE__{database: nil} = state) do
    request = put_headers(request, state.headers)

    exec_case Client.request(request, state) do
      {:ok, response, state} ->
        {:ok, sanitize_headers(request), response, state}
    end
  end

  @impl true
  def handle_execute(_q, %Request{} = request, _opts, %__MODULE__{} = state) do
    request =
      request
      |> put_headers(state.headers)
      |> maybe_prepend_database(state.database)

    exec_case Client.request(request, state) do
      {:ok, response, state} ->
        {:ok, sanitize_headers(request), response, state}
    end
  end

  @impl true
  def ping(%__MODULE__{} = state) do
    exec_case Client.request(@request_ping, state) do
      {:ok, %Response{}, state} ->
        {:ok, state}
    end
  end

  # Unsupported callbacks

  @impl true
  def handle_prepare(_q, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_close(_q, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_rollback(_opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_status(_opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_declare(_q, _params, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_fetch(_q, _cursor, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  @impl true
  def handle_deallocate(_q, _cursor, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_trans | endpoint: state.endpoint}, state}

  # Utils

  defp put_header(%{headers: headers} = struct, header) when is_tuple(header),
    do: %{struct | headers: [header | headers]}

  defp put_headers(%{headers: headers} = struct, new_headers) when is_list(new_headers),
    do: %{struct | headers: headers ++ new_headers}

  # defp get_header(%{headers: headers}, header) when is_binary(header) do
  #   case Enum.find(headers, fn {k, _v} -> k == header end) do
  #     {_k, v} -> v
  #     nil -> nil
  #   end
  # end

  defp sanitize_headers(struct) when is_map(struct),
    do: Map.update!(struct, :headers, &sanitize_headers/1)

  defp sanitize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn {key, _value} = header ->
      if key == "authorization", do: {key, "..."}, else: header
    end)
  end

  defp maybe_prepend_database(%Request{path: "/_db/" <> _} = request, _),
    do: request

  defp maybe_prepend_database(%Request{path: path} = request, database),
    do: %{request | path: "/_db/" <> database <> path}

  defp exception(state, %Response{status: 405} = response) do
    %Error{
      endpoint: state.endpoint,
      status: response.status,
      message: "method not allowed"
    }
  end

  defp exception(state, %Response{body: nil} = response),
    do: %Error{endpoint: state.endpoint, status: response.status}

  defp exception(state, %Response{} = response) do
    response = DBConnection.Query.decode(struct(Request, []), response, [])

    %Error{
      endpoint: state.endpoint,
      status: response.status,
      message: Map.get(response.body, "errorMessage")
    }
  end

  defp exception(state, reason),
    do: %Error{endpoint: state.endpoint, message: reason}
end
