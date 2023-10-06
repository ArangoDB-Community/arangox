defimpl DBConnection.Query, for: BitString do
  def parse(query, _opts), do: query

  def describe(query, _opts), do: query

  def encode(_query, params, _opts), do: Enum.into(params, %{})

  def decode(_query, params, _opts), do: params
end

defmodule Arangox.Connection do
  @moduledoc """
  `DBConnection` implementation for `Arangox`.
  """

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
          disconnect_on_error_codes: [integer],
          read_only?: boolean,
          cursors: map
        }

  @type failover? :: boolean

  @enforce_keys [:socket, :client, :endpoint]

  defstruct [
    :socket,
    :client,
    :endpoint,
    :failover?,
    :database,
    :cursors,
    auth?: true,
    username: "root",
    password: "",
    headers: %{},
    disconnect_on_error_codes: [401, 405, 503, 505],
    read_only?: false
  ]

  @spec new(
          Client.socket(),
          Arangox.client(),
          Arangox.endpoint(),
          failover?,
          [Arangox.start_option()]
        ) :: t
  def new(socket, client, endpoint, failover?, opts) do
    __MODULE__
    |> struct(opts)
    |> Map.put(:socket, socket)
    |> Map.put(:client, client)
    |> Map.put(:endpoint, endpoint)
    |> Map.put(:failover?, failover?)
    |> Map.put(:cursors, %{})
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
    case apply(VelocyClient, :authorize, [state]) do
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

    request = %Request{
      method: :post,
      path: Path.join(@path_trx, "begin"),
      body: body
    }

    case handle_execute(nil, request, opts, state) do
      {:ok, _request, %Response{status: 201, body: %{"result" => %{"id" => id}}} = response,
       state} ->
        {:ok, response, put_header(state, {@header_trx_id, id})}

      {:ok, _request, %Response{}, state} ->
        {:error, state}

      {:error, _exception, state} ->
        {:error, state}

      {:disconnect, _exception, state} ->
        {:error, state}
    end
  end

  @impl true
  def handle_status(opts, %__MODULE__{} = state) do
    with(
      {id, _headers} when is_binary(id) <-
        Map.pop(state.headers, @header_trx_id),
      {:ok, _request, %Response{status: 200}, state} <-
        handle_execute(
          nil,
          %Request{method: :get, path: Path.join(@path_trx, id)},
          opts,
          state
        )
    ) do
      {:transaction, state}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, _request, %Response{}, state} ->
        {:error, state}

      {:error, _exception, state} ->
        {:error, state}

      {:disconnect, exception, state} ->
        {:disconnect, exception, state}
    end
  end

  @impl true
  def handle_commit(opts, %__MODULE__{} = state) do
    with(
      {id, headers} when is_binary(id) <-
        Map.pop(state.headers, @header_trx_id),
      {:ok, _request, %Response{status: 200} = response, state} <-
        handle_execute(
          nil,
          %Request{method: :put, path: Path.join(@path_trx, id)},
          opts,
          %{state | headers: headers}
        )
    ) do
      {:ok, response, state}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, _request, %Response{}, state} ->
        {:error, state}

      {:error, _exception, state} ->
        {:error, state}

      {:disconnect, exception, state} ->
        {:disconnect, exception, state}
    end
  end

  @impl true
  def handle_rollback(opts, %__MODULE__{} = state) do
    with(
      {id, headers} when is_binary(id) <- Map.pop(state.headers, @header_trx_id),
      {:ok, _request, %Response{status: 200} = response, state} <-
        handle_execute(
          nil,
          %Request{method: :delete, path: Path.join(@path_trx, id)},
          opts,
          %{state | headers: headers}
        )
    ) do
      {:ok, response, state}
    else
      {nil, _headers} ->
        {:idle, state}

      {:ok, _request, %Response{}, state} ->
        {:error, state}

      {:error, _exception, state} ->
        {:error, state}

      {:disconnect, exception, state} ->
        {:disconnect, exception, state}
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

  @rand_min String.to_integer("10000000", 36)
  @rand_max String.to_integer("ZZZZZZZZ", 36)

  defp rand do
    @rand_max
    |> Kernel.-(@rand_min)
    |> :rand.uniform()
    |> Kernel.+(@rand_min)
  end

  @impl true
  def handle_fetch(query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    with(
      {nil, _cursors} <-
        Map.pop(cursors, cursor),
      {:ok, _req, %Response{body: %{"hasMore" => true}} = response, state} <-
        handle_execute(
          query,
          %Request{method: :put, path: "/_api/cursor/" <> cursor},
          opts,
          state
        )
    ) do
      {:cont, response, state}
    else
      {%Response{body: %{"hasMore" => false}} = initial, cursors} ->
        {:halt, initial, %{state | cursors: Map.put(cursors, cursor, :noop)}}

      {%Response{body: %{"hasMore" => true}} = initial, cursors} ->
        {:cont, initial, %{state | cursors: cursors}}

      {:ok, _req, %Response{body: %{"hasMore" => false}} = response, state} ->
        {:halt, response, %{state | cursors: Map.put(cursors, cursor, :noop)}}

      error ->
        error
    end
  end

  @impl true
  def handle_deallocate(query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    state = %{state | cursors: Map.delete(cursors, cursor)}

    case cursors do
      %{^cursor => :noop} ->
        {:ok, :noop, state}

      _ ->
        request = %Request{method: :delete, path: "/_api/cursor/" <> cursor}

        case handle_execute(query, request, opts, state) do
          {:ok, _req, response, state} ->
            {:ok, response, state}

          error ->
            error
        end
    end
  end

  @impl true
  def ping(%__MODULE__{} = state) do
    case handle_execute(nil, @request_ping, [], state) do
      {:ok, _request, %Response{}, state} ->
        {:ok, state}

      {call, exception, state} when call in [:error, :disconnect] ->
        {:disconnect, exception, state}
    end
  end

  @impl true
  def handle_execute(_q, %Request{} = request, opts, %__MODULE__{} = state) do
    request =
      request
      |> merge_headers(state.headers)
      |> maybe_prepend_database(state, opts)
      |> maybe_encode_body(state)

    case Client.request(request, state) do
      {:ok, %Response{status: status} = response, state} when status in 400..599 ->
        {
          err_or_disc(status, state.disconnect_on_error_codes),
          exception(state, response),
          state
        }

      {:ok, response, state} ->
        {:ok, sanitize_headers(request), maybe_decode_body(response, state), state}

      {:error, :noproc, state} ->
        {:disconnect, exception(state, "connection lost"), state}

      {:error, %_{} = reason, state} ->
        {:error, reason, state}

      {:error, reason, state} ->
        {:error, exception(state, reason), state}
    end
  end

  defp err_or_disc(status, codes) do
    if status in codes, do: :disconnect, else: :error
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

  defp maybe_prepend_database(%Request{path: path} = request, state, opts) do
    case Keyword.get(opts, :database) do
      nil ->
        do_db_prepend(request, state)

      db ->
        %{request | path: "/_db/" <> db <> path}
    end
  end

  # Only prepends when not velocy or nil or path already contains /_db/
  defp do_db_prepend(%Request{} = request, %{client: VelocyClient}),
    do: request

  defp do_db_prepend(%Request{} = request, %{database: nil}),
    do: request

  defp do_db_prepend(%Request{path: "/_db/" <> _} = request, %{database: _db}),
    do: request

  defp do_db_prepend(%Request{path: path} = request, %{database: db}),
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

  defp maybe_decode_body(
         %_{body: body, headers: %{"content-type" => "application/x-arango-dump"}} = struct,
         %__MODULE__{}
       ) do
    content =
      body
      |> String.split("\n")
      |> Enum.filter(fn line -> String.length(line) > 0 end)
      |> Enum.map(fn line -> Arangox.json_library().decode!(line) end)

    %{struct | body: content}
  end

  defp maybe_decode_body(%_{body: body} = struct, %__MODULE__{}) do
    %{struct | body: Arangox.json_library().decode!(body)}
  end

  defp exception(state, %Response{body: nil} = response),
    do: %Error{endpoint: state.endpoint, status: response.status}

  defp exception(state, %Response{} = response) do
    response = maybe_decode_body(response, state)
    message = response.body["errorMessage"]
    error_num = response.body["errorNum"]

    %Error{
      endpoint: state.endpoint,
      status: response.status,
      error_num: error_num,
      message: message
    }
  end

  defp exception(state, reason),
    do: %Error{endpoint: state.endpoint, message: reason}
end
