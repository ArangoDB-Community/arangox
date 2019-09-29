defmodule Arangox.Connection do
  @moduledoc false

  use DBConnection

  alias Arangox.{
    Client,
    Endpoint,
    Error,
    Request,
    Response,
    VelocyClient
  }

  @type t :: %__MODULE__{
          socket: any,
          client: module,
          endpoint: Arangox.endpoint(),
          failover?: boolean,
          database: binary,
          auth?: boolean,
          username: binary,
          password: binary,
          headers: Arangox.headers(),
          read_only?: boolean,
          cursors: map
        }

  @enforce_keys [:socket, :client, :endpoint]

  defstruct [
    :socket,
    :client,
    :endpoint,
    :failover?,
    :database,
    auth?: true,
    username: "root",
    password: "",
    headers: %{},
    read_only?: false,
    cursors: %{}
  ]

  @spec new(any, module, binary, boolean, [Arangox.start_option()]) :: t
  def new(socket, client, endpoint, failover?, opts) do
    __MODULE__
    |> struct(opts)
    |> Map.put(:socket, socket)
    |> Map.put(:client, client)
    |> Map.put(:endpoint, endpoint)
    |> Map.put(:failover?, failover?)
  end

  # @header_arango_endpoint "x-arango-endpoint"
  @path_trx "/_api/transaction/"
  @header_trx_id "x-arango-trx-id"
  @header_dirty_read {"x-arango-allow-dirty-read", "true"}
  @request_ping %Request{method: :get, path: "/_admin/server/availability"}
  @request_availability %Request{method: :get, path: "/_admin/server/availability"}
  @request_mode %Request{method: :get, path: "/_admin/server/mode"}
  @exception_no_prep %Error{message: "ArangoDB doesn't support prepared queries yet"}

  @impl true
  def connect(opts) do
    client = Keyword.get(opts, :client, VelocyClient)
    endpoints = Keyword.get(opts, :endpoints, "http://localhost:8529")

    with(
      {:ok, %__MODULE__{} = state} <- do_connect(client, endpoints, opts),
      {:ok, %__MODULE__{} = state} <- resolve_auth(stringify_kvs(state)),
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

  defp do_connect(client, endpoint, opts) when is_binary(endpoint) do
    case Client.connect(client, Endpoint.new(endpoint), opts) do
      {:ok, socket} ->
        {:ok, new(socket, client, endpoint, false, opts)}

      {:error, reason} ->
        {:error, exception(new(nil, client, endpoint, false, opts), reason)}
    end
  end

  defp do_connect(client, [], opts) do
    {:error,
     new(nil, client, nil, true, opts)
     |> exception("all endpoints are unavailable")
     |> failover_callback(opts)}
  end

  defp do_connect(client, endpoints, opts) when is_list(endpoints) do
    endpoint = hd(endpoints)

    case Client.connect(client, Endpoint.new(endpoint), opts) do
      {:ok, socket} ->
        {:ok, new(socket, client, endpoint, true, opts)}

      {:error, reason} ->
        new(nil, client, endpoint, true, opts)
        |> exception(reason)
        |> failover_callback(opts)

        {:error, :failed}
    end
  end

  defp failover_callback(%_{} = exception, opts) do
    case Keyword.get(opts, :failover_callback) do
      {mod, fun, args} ->
        apply(mod, fun, [exception | args])

      fun when is_function(fun, 1) ->
        fun.(exception)

      _invalid_callback ->
        nil
    end

    exception
  end

  defp resolve_auth(%__MODULE__{auth?: false} = state),
    do: {:ok, %{state | username: nil, password: nil}}

  defp resolve_auth(%__MODULE__{client: VelocyClient} = state) do
    case VelocyClient.authorize(state) do
      :ok ->
        {:ok, state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_auth(%__MODULE__{username: un, password: pw} = state) do
    base64_encoded = Base.encode64("#{un}:#{pw}")

    {:ok, put_header(state, {"authorization", "Basic #{base64_encoded}"})}
  end

  defp check_availability(%__MODULE__{read_only?: true} = state) do
    state = put_header(state, @header_dirty_read)
    request = merge_headers(@request_mode, state.headers)
    result = Client.request(request, state)

    with(
      {:ok, %Response{status: 200} = response, state} <- result,
      %Response{body: %{"mode" => "readonly"}} <- maybe_decode_body(response, state)
    ) do
      {:ok, state}
    else
      {:error, reason, state} ->
        error =
          if state.failover?,
            do: :failed,
            else: exception(state, reason)

        {:error, error}

      _ ->
        error =
          if state.failover?,
            do: :unavailable,
            else: exception(state, "not a readonly server")

        {:error, error}
    end
  end

  defp check_availability(%__MODULE__{failover?: failover?} = state) do
    request = merge_headers(@request_availability, state.headers)
    # result = Client.request(request, state)

    # if a server is running inside a container, it's x-arango-endpoint
    # header will need to be mapped to a different value somehow
    with(
      result <- Client.request(request, state),
      {:ok, %Response{status: 503}, _state} <- result
      # {:ok, %Response{status: 503} = response, _state} <- result
      # endpoint when not is_nil(endpoint) <- response.headers[@header_arango_endpoint]
    ) do
      # {:connect, endpoint}

      error = if failover?, do: :unavailable, else: exception(state, "service unavailable")
      {:error, error}
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

  # Transaction handlers

  @impl true
  def handle_begin(_opts, %__MODULE__{headers: %{@header_trx_id => _id}} = state),
    do: {:transaction, state}

  @impl true
  def handle_begin(opts, %__MODULE__{} = state) do
    collections =
      opts
      |> Keyword.take([:read, :write, :exclusive])
      |> Enum.into(%{})

    body =
      opts
      |> Keyword.get(:properties, [])
      |> Enum.into(%{collections: collections})

    with(
      {:ok, %Response{status: 201} = response, state} <-
        %Request{
          method: :post,
          path: Path.join(@path_trx, "begin"),
          body: body
        }
        |> merge_headers(state.headers)
        |> maybe_prepend_database(state)
        |> maybe_encode_body(state)
        |> Client.request(state),
      %Response{body: %{"result" => %{"id" => id}}} = response <-
        maybe_decode_body(response, state)
    ) do
      {:ok, response, put_header(state, {@header_trx_id, id})}
    else
      {:ok, %Response{}, state} ->
        {:error, state}

      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, _reason, state} ->
        {:error, state}
    end
  end

  @impl true
  def handle_status(_opts, %__MODULE__{} = state) do
    with(
      {id, headers} when is_binary(id) <- Map.pop(state.headers, @header_trx_id),
      {:ok, %Response{status: 200}, state} <-
        %Request{
          method: :get,
          path: Path.join(@path_trx, id)
        }
        |> merge_headers(headers)
        |> maybe_prepend_database(state)
        |> Client.request(state)
    ) do
      {:transaction, state}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, %Response{status: _status}, state} ->
        {:error, state}

      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, _reason, state} ->
        {:error, state}
    end
  end

  @impl true
  def handle_commit(_opts, %__MODULE__{} = state) do
    with(
      {id, headers} when is_binary(id) <- Map.pop(state.headers, @header_trx_id),
      {:ok, %Response{status: 200} = response, state} <-
        %Request{
          method: :put,
          path: Path.join(@path_trx, id)
        }
        |> merge_headers(headers)
        |> maybe_prepend_database(state)
        |> Client.request(state)
    ) do
      {:ok, maybe_decode_body(response, state), %{state | headers: headers}}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, %Response{status: _status}, state} ->
        {:error, state}

      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, _reason, state} ->
        {:error, state}
    end
  end

  @impl true
  def handle_rollback(_opts, %__MODULE__{} = state) do
    with(
      {id, headers} when is_binary(id) <- Map.pop(state.headers, @header_trx_id),
      {:ok, %Response{status: 200} = response, state} <-
        %Request{
          method: :delete,
          path: Path.join(@path_trx, id)
        }
        |> merge_headers(headers)
        |> maybe_prepend_database(state)
        |> Client.request(state)
    ) do
      {:ok, maybe_decode_body(response, state), %{state | headers: headers}}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, %Response{status: _status}, state} ->
        {:error, state}

      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, _reason, state} ->
        {:error, state}
    end
  end

  @impl true
  def handle_declare(query, params, opts, %__MODULE__{} = state) do
    body =
      opts
      |> Keyword.get(:properties, [])
      |> Enum.into(%{query: query, bindVars: params})

    request = %Request{
      method: :post,
      path: "/_api/cursor",
      body: body
    }

    case handle_execute(query, request, opts, state) do
      {:ok, _req, %Response{body: %{"id" => cursor}} = initial, state} ->
        {:ok, query, cursor, %{state | cursors: Map.put(state.cursors, cursor, initial)}}

      {:ok, _req, %Response{} = initial, state} ->
        cursor = rand()
        {:ok, query, cursor, %{state | cursors: Map.put(state.cursors, cursor, initial)}}

      error ->
        error
    end
  end

  defp rand do
    min = String.to_integer("100000", 36)
    max = String.to_integer("ZZZZZZ", 36)

    max
    |> Kernel.-(min)
    |> :rand.uniform()
    |> Kernel.+(min)
    |> Integer.to_string(36)
  end

  @impl true
  def handle_fetch(query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    with(
      {nil, _cursors} <-
        Map.pop(cursors, cursor),
      {:ok, _req, %Response{body: %{"hasMore" => has_more}} = response, state} <-
        handle_execute(
          query,
          %Request{method: :put, path: "/_api/cursor/" <> cursor},
          opts,
          state
        )
    ) do
      {cont_or_halt(has_more), response, state}
    else
      {%Response{body: %{"hasMore" => has_more}} = initial, cursors} ->
        {cont_or_halt(has_more), initial, %{state | cursors: cursors}}

      error ->
        error
    end
  end

  defp cont_or_halt(true), do: :cont
  defp cont_or_halt(false), do: :halt

  @impl true
  def handle_deallocate(query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    state = %{state | cursors: Map.delete(cursors, cursor)}
    request = %Request{method: :delete, path: "/_api/cursor/" <> cursor}

    case handle_execute(query, request, opts, state) do
      {:ok, _req, response, state} ->
        {:ok, response, state}

      error ->
        error
    end
  end

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

      {:ok, %Response{status: 401} = response, state} ->
        {:disconnect, exception(state, response), state}

      {:ok, %Response{status: status} = response, state} when status in 400..599 ->
        {:error, exception(state, response), state}
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
  def handle_execute(_q, %Request{} = request, _opts, %__MODULE__{} = state) do
    request =
      request
      |> merge_headers(state.headers)
      |> maybe_prepend_database(state)
      |> maybe_encode_body(state)

    exec_case Client.request(request, state) do
      {:ok, response, state} ->
        {:ok, sanitize_headers(request), maybe_decode_body(response, state), state}
    end
  end

  @impl true
  def ping(%__MODULE__{} = state) do
    @request_ping
    |> merge_headers(state.headers)
    |> Client.request(state)
    |> exec_case do
      {:ok, %Response{}, state} ->
        {:ok, state}
    end
  end

  # Unsupported callbacks

  @impl true
  def handle_prepare(_q, _opts, %__MODULE__{} = state) do
    {:error, %{@exception_no_prep | endpoint: state.endpoint}, state}
  end

  @impl true
  def handle_close(_q, _opts, %__MODULE__{} = state) do
    {:error, %{@exception_no_prep | endpoint: state.endpoint}, state}
  end

  # Utils

  defp put_header(%__MODULE__{headers: headers} = struct, {key, value}),
    do: %{struct | headers: Map.put(headers, key, value)}

  defp merge_headers(%Request{headers: req_headers} = struct, headers) when is_map(headers),
    do: %{struct | headers: Map.merge(headers, stringify_kvs(req_headers))}

  defp stringify_kvs(%{headers: headers} = struct),
    do: %{struct | headers: stringify_kvs(headers)}

  defp stringify_kvs(headers),
    do: Map.new(headers, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp sanitize_headers(%{headers: %{"authorization" => _auth} = headers} = struct)
       when is_map(struct) do
    %{struct | headers: %{headers | "authorization" => "..."}}
  end

  defp sanitize_headers(%{headers: _headers} = struct) when is_map(struct), do: struct

  # Only prepends when not velocy or nil or path already contains /_db/
  defp maybe_prepend_database(%Request{} = request, %{client: VelocyClient}),
    do: request

  defp maybe_prepend_database(%Request{} = request, %{database: nil}),
    do: request

  defp maybe_prepend_database(%Request{path: "/_db/" <> _} = request, %{database: _db}),
    do: request

  defp maybe_prepend_database(%Request{path: path} = request, %{database: db}),
    do: %{request | path: "/_db/" <> db <> path}

  # Only encodes when not velocy or empty string
  defp maybe_encode_body(%_{} = struct, %__MODULE__{client: VelocyClient}), do: struct

  defp maybe_encode_body(%_{body: ""} = struct, %__MODULE__{}), do: struct

  defp maybe_encode_body(%_{body: body} = struct, %__MODULE__{}) do
    %{struct | body: Arangox.json_library().encode!(body)}
  end

  # Only decodes when not velocy or nil
  defp maybe_decode_body(%_{} = struct, %__MODULE__{client: VelocyClient}), do: struct

  defp maybe_decode_body(%_{body: nil} = struct, %__MODULE__{}), do: struct

  defp maybe_decode_body(%_{body: body} = struct, %__MODULE__{}) do
    %{struct | body: Arangox.json_library().decode!(body)}
  end

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
    message =
      response
      |> maybe_decode_body(state)
      |> Map.get(:body)
      |> Map.get("errorMessage")

    %Error{endpoint: state.endpoint, status: response.status, message: message}
  end

  defp exception(state, reason),
    do: %Error{endpoint: state.endpoint, message: reason}
end
