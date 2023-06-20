defmodule Arangox do
  @moduledoc File.read!("#{__DIR__}/../README.md")
             |> String.split("\n")
             |> Enum.drop(2)
             |> Enum.join("\n")

  alias __MODULE__.{
    Error,
    GunClient,
    MintClient,
    Request,
    Response,
    VelocyClient
  }

  @type method ::
          :get
          | :head
          | :delete
          | :post
          | :put
          | :patch
          | :options

  @type conn :: DBConnection.conn()
  @type client :: module
  @type endpoint :: binary
  @type path :: binary
  @type body :: binary | map | list | nil
  @type headers :: map | [{binary, binary}]
  @type query :: binary
  @type bindvars :: keyword | map

  @type start_option ::
          {:client, module}
          | {:endpoints, list(endpoint)}
          | {:auth?, boolean}
          | {:database, binary}
          | {:username, binary}
          | {:password, binary}
          | {:headers, headers}
          | {:read_only?, boolean}
          | {:connect_timeout, timeout}
          | {:failover_callback, (Error.t() -> any) | {module, atom, [any]}}
          | {:tcp_opts, [:gen_tcp.connect_option()]}
          | {:ssl_opts, [:ssl.tls_client_option()]}
          | {:client_opts, :gun.opts() | keyword()}
          | DBConnection.start_option()

  @type transaction_option ::
          {:read, binary() | [binary()]}
          | {:write, binary() | [binary()]}
          | {:exclusive, binary() | [binary()]}
          | {:properties, list() | map()}
          | DBConnection.option()

  @doc """
  Returns a supervisor child specification for a DBConnection pool.
  """
  @spec child_spec([start_option()]) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    ensure_opts_valid!(opts)

    DBConnection.child_spec(__MODULE__.Connection, opts)
  end

  @doc """
  Starts a connection pool.

  ## Options

  Accepts any of the options accepted by `DBConnection.start_link/2`, as well as any of the
  following:

    * `:endpoints` - Either a single _ArangoDB_ endpoint binary, or a list of endpoints in
    order of presedence. Each process in a pool will individually attempt to establish a connection
    with and check the availablility of each endpoint in the order given until an available endpoint
    is found. Defaults to `"http://localhost:8529"`.
    * `:database` - Arangox will prepend `/_db/:value` to the path of every request that
    isn't already prepended. If a value is not given, nothing is prepended (_ArangoDB_ will
    assume the __system_ database).
    * `:headers` - A map of headers to merge with every request.
    * `:disconnect_on_error_codes` - A list of status codes that will trigger a forced disconnect.
    Only integers within the range `400..599` are affected. Defaults to
    `[401, 405, 503, 505]`.
    * `:auth?` - Configure whether or not to resolve authorization (with the `:username` and
    `:password` options). Defaults to `true`.
    * `:username` - Defaults to `"root"`.
    * `:password` - Defaults to `""`.
    * `:read_only?` - Read-only pools will only connect to _followers_ in an active failover
    setup and add an _x-arango-allow-dirty-read_ header to every request. Defaults to `false`.
    * `:connect_timeout` - Sets the timeout for establishing connections with a database.
    * `:tcp_opts` - Transport options for the tcp socket interface (`:gen_tcp` in the case
    of gun or mint).
    * `:ssl_opts` - Transport options for the ssl socket interface (`:ssl` in the case of
    gun or mint).
    * `:client` - A module that implements the `Arangox.Client` behaviour. Defaults to
    `Arangox.VelocyClient`.
    * `:client_opts` - Options for the client library being used. *WARNING*: If `:transport_opts`
    is set here it will override the options given to `:tcp_opts` _and_ `:ssl_opts`.
    * `:failover_callback` - A function to call every time arangox fails to establish a
    connection. This is only called if a list of endpoints is given, regardless of whether or not
    it's connecting to an endpoint in an _active failover_ setup. Can be either an anonymous function
    that takes one argument (which is an `%Arangox.Error{}` struct), or a three-element tuple
    containing arguments to pass to `apply/3` (in which case an `%Arangox.Error{}` struct is always
    prepended to the arguments).
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    ensure_opts_valid!(opts)

    DBConnection.start_link(__MODULE__.Connection, opts)
  end

  @doc """
  Runs a GET request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec get(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def get(conn, path, headers \\ %{}, opts \\ []) do
    request(conn, :get, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a GET request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec get!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def get!(conn, path, headers \\ %{}, opts \\ []) do
    request!(conn, :get, path, "", headers, opts)
  end

  @doc """
  Runs a HEAD request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec head(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def head(conn, path, headers \\ %{}, opts \\ []) do
    request(conn, :head, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a HEAD request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec head!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def head!(conn, path, headers \\ %{}, opts \\ []) do
    request!(conn, :head, path, "", headers, opts)
  end

  @doc """
  Runs a DELETE request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec delete(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def delete(conn, path, headers \\ %{}, opts \\ []) do
    request(conn, :delete, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a DELETE request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec delete!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def delete!(conn, path, headers \\ %{}, opts \\ []) do
    request!(conn, :delete, path, "", headers, opts)
  end

  @doc """
  Runs a POST request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec post(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def post(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request(conn, :post, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a POST request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec post!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def post!(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request!(conn, :post, path, body, headers, opts)
  end

  @doc """
  Runs a PUT request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec put(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def put(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request(conn, :put, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a PUT request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec put!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def put!(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request!(conn, :put, path, body, headers, opts)
  end

  @doc """
  Runs a PATCH request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec patch(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def patch(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request(conn, :patch, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a PATCH request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec patch!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def patch!(conn, path, body \\ "", headers \\ %{}, opts \\ []) do
    request!(conn, :patch, path, body, headers, opts)
  end

  @doc """
  Runs a OPTIONS request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec options(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def options(conn, path, headers \\ %{}, opts \\ []) do
    request(conn, :options, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a OPTIONS request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec options!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def options!(conn, path, headers \\ %{}, opts \\ []) do
    request!(conn, :options, path, "", headers, opts)
  end

  @doc """
  Runs a request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec request(conn, method, path, body, headers, [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def request(conn, method, path, body \\ "", headers \\ %{}, opts \\ []) do
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute(conn, request, nil, opts)
  end

  @doc """
  Runs a request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec request!(conn, method, path, body, headers, [DBConnection.option()]) ::
          Response.t()
  def request!(conn, method, path, body \\ "", headers \\ %{}, opts \\ []) do
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute!(conn, request, nil, opts)
  end

  defp do_result({:ok, _request, response}), do: {:ok, response}
  defp do_result({:error, exception}), do: {:error, exception}

  @doc """
  Acquires a connection from a pool and runs a series of requests or cursors with it.
  If the connection disconnects, all future calls using that connection reference will
  fail.

  Runs can be nested multiple times if the connection reference is used to start a
  nested run (i.e. calling another function that calls this one). The top level run
  function will represent the actual run.

  Delegates to `DBConnection.run/3`.

  ## Example

      result =
        Arangox.run(conn, fn c  ->
          Arangox.request!(c, ...)
        end)
  """
  @spec run(conn, (DBConnection.t() -> result), [DBConnection.option()]) :: result
        when result: var
  defdelegate run(conn, fun, opts \\ []), to: DBConnection

  @doc """
  Acquires a connection from a pool, begins a transaction in the database and runs a
  series of requests or cursors with it. If the connection disconnects, all future calls
  using that connection reference will fail.

  Transactions can be nested multiple times if the connection reference is used to start a
  nested transactions (i.e. calling another function that calls this one). The top level
  transaction function will represent the actual transaction and nested transactions will
  be interpreted as a `run/3`, erego, any collections declared in nested transactions will
  have no effect.

  Accepts any of the options accepted by `DBConnection.transaction/3`, as well as any of the
  following:

    * `:read` - An array of collection names or a single collection name as a binary.
    * `:write` - An array of collection names or a single collection name as a binary.
    * `:exclusive` - An array of collection names or a single collection name as a binary.
    * `:database` - Sets what database to run the transaction on
    * `:properties` - A list or map of additional body attributes to append to the request
    body when beginning a transaction.

  Delegates to `DBConnection.transaction/3`.

  ## Example

      Arangox.transaction(conn, fn c ->
        Arangox.status(c) #=> :transaction

        # do stuff
      end, [
        write: "something",
        properties: [waitForSync: true]
      ])
  """
  @spec transaction(conn, (DBConnection.t() -> result), [transaction_option()]) ::
          {:ok, result} | {:error, any}
        when result: var
  defdelegate transaction(conn, fun, opts \\ []), to: DBConnection

  @doc """
  Fetches the current status of a transaction from the database and returns its
  corresponding `DBconnection` status.

  Delegates to `DBConnection.status/1`.
  """
  @spec status(conn) :: DBConnection.status()
  defdelegate status(conn), to: DBConnection

  @doc """
  Aborts a transaction for the given reason.

  Delegates to `DBConnection.rollback/2`.

  ## Example

      iex> {:ok, conn} = Arangox.start_link()
      iex> Arangox.transaction(conn, fn c ->
      iex>   Arangox.abort(c, :reason)
      iex> end)
      {:error, :reason}
  """
  @spec abort(conn, reason :: any) :: no_return()
  defdelegate abort(conn, reason), to: DBConnection, as: :rollback

  @doc """
  Creates a cursor and returns a `DBConnection.Stream` struct. Results are fetched
  upon enumeration.

  The cursor is created, results fetched, then deleted from the database upon each
  enumeration (not to be confused with iteration). When a cursor is created, an initial
  result set is fetched from the database. The initial result is returned with the first
  iteration, subsequent iterations are fetched lazily.

  Can only be used within a `transaction/3` or `run/3` call.

  Accepts any of the options accepted by `DBConnection.stream/4`, as well as any of the
  following:

    * `:database` - Sets what database to run the cursor query on
    * `:properties` - A list or map of additional body attributes to append to the
    request body when creating the cursor.

  Delegates to `DBConnection.stream/4`.

  ## Example

      iex> {:ok, conn} = Arangox.start_link()
      iex> Arangox.transaction(conn, fn c ->
      iex>   stream =
      iex>     Arangox.cursor(
      iex>       c,
      iex>       "FOR i IN [1, 2, 3] FILTER i == 1 || i == @num RETURN i",
      iex>       %{num: 2},
      iex>       properties: [batchSize: 1]
      iex>     )
      iex>
      iex>   first_batch = Enum.at(stream, 0).body["result"]
      iex>
      iex>   exhaust_cursor =
      iex>     Enum.reduce(stream, [], fn resp, acc ->
      iex>       acc ++ resp.body["result"]
      iex>     end)
      iex>
      iex>   {first_batch, exhaust_cursor}
      iex> end)
      {:ok, {[1], [1, 2]}}
  """
  @spec cursor(conn(), query, bindvars, [DBConnection.option()]) :: DBConnection.Stream.t()
  defdelegate cursor(conn, query, bindvars \\ [], opts \\ []), to: DBConnection, as: :stream

  @doc """
  Returns the configured JSON library.

  To change the library, include the following in your `config/config.exs`:

      config :arangox, :json_library, Module

  Defaults to `Jason`.
  """
  @spec json_library() :: module()
  def json_library, do: Application.get_env(:arangox, :json_library, Jason)

  defp ensure_opts_valid!(opts) do
    if endpoints = Keyword.get(opts, :endpoints) do
      unless is_binary(endpoints) or (is_list(endpoints) and endpoints_valid?(endpoints)) do
        raise ArgumentError, """
        The :endpoints option expects a binary or a non-empty list of binaries,\
        got: #{inspect(endpoints)}
        """
      end
    end

    if client = Keyword.get(opts, :client) do
      ensure_client_loaded!(client)
    end

    if database = Keyword.get(opts, :database) do
      unless is_binary(database) do
        raise ArgumentError, """
        The :database option expects a binary, got: #{inspect(endpoints)}
        """
      end
    end
  end

  defp endpoints_valid?(endpoints) when is_list(endpoints) do
    length(endpoints) > 0 and
      Enum.count(endpoints, &is_binary/1) == length(endpoints)
  end

  defp ensure_client_loaded!(client) do
    cond do
      not is_atom(client) ->
        raise ArgumentError, """
        The :client option expects a module, got: #{inspect(client)}
        """

      client in [VelocyClient, GunClient, MintClient] ->
        unless Code.ensure_loaded?(client) do
          library =
            client
            |> Module.split()
            |> List.last()
            |> String.downcase()

          raise """
          Missing client dependency. Please add #{library} to your mix deps:

              # mix.exs
              defp deps do
                ...
                {:#{library}, "~> ..."}
              end
          """
        end

      client ->
        unless Code.ensure_loaded?(client),
          do: raise("Module #{client} does not exist")
    end
  end
end
