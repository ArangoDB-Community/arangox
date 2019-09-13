defmodule Arangox do
  @moduledoc File.read!("#{__DIR__}/../README.md")
             |> String.split("\n")
             |> Enum.drop(2)
             |> Enum.join("\n")

  alias __MODULE__.{
    Client.Gun,
    Client.Mint,
    Error,
    Request,
    Response
  }

  @type method ::
          :get
          | :head
          | :delete
          | :post
          | :put
          | :patch
          | :options

  @type path :: binary
  @type body :: binary | map | list | nil
  @type header :: {binary, binary}
  @type endpoint :: binary
  @type conn :: DBConnection.conn()

  @type start_option ::
          {:client, module}
          | {:endpoints, list(endpoint)}
          | {:auth?, boolean}
          | {:database, binary}
          | {:username, binary}
          | {:password, binary}
          | {:headers, list(header)}
          | {:read_only?, boolean}
          | {:connect_timeout, timeout}
          | {:failover_callback, (Error.t() -> any) | {module, atom, [any]}}
          | {:tcp_opts, [:gen_tcp.connect_option()]}
          | {:ssl_opts, [:ssl.tls_client_option()]}
          | {:client_opts, :gun.opts() | keyword()}
          | DBConnection.start_option()

  @doc """
  Returns a supervisor child specification for a DBConnection pool.
  """
  @spec child_spec([start_option()]) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    DBConnection.child_spec(__MODULE__.Connection, opts)
  end

  @doc """
  Starts a connection pool.

  ## Options

  Accepts any of the options accepted by `DBConnection.start_link/2`, as well as any of the
  following:

    * `:endpoints` - A list of _ArangoDB_ endpoints in order of presedence. Each process
    in a pool will individually attempt to establish a connection with and check the
    availablility of each endpoint in the order given until one is found. Defaults to
    `["http://localhost:8529"]`.
    * `:database` - Arangox will prepend `/_db/:value` to the path of every request that
    isn't already prepended. If a value is not given, nothing is prepended (_ArangoDB_ will
    assume the __system_ database).
    * `:headers` - A list of headers to merge with every request.
    * `:auth?` - Configure whether or not to add an _authorization_ header to every request
    with the provided username and password. Defaults to `true`.
    * `:username` - Defaults to `"root"`.
    * `:password` - Defaults to `""`.
    * `:read_only?` - Read-only pools will only connect to _followers_ in an active failover
    setup and add an _x-arango-allow-dirty-read_ header to every request. Defaults to `false`.
    * `:connect_timeout` - Sets the timeout for establishing a connection with a server.
    * `:transport_opts` - Transport options for the socket interface (which is `:gen_tcp` or
    `:ssl` for both gun and mint, depending on whether or not they are connecting via ssl).
    * `:tcp_opts` - Transport options for the tcp socket interface (`:gen_tcp` in the case
    of gun or mint).
    * `:ssl_opts` - Transport options for the ssl socket interface (`:ssl` in the case of
    gun or mint).
    * `:client` - A module that implements the `Arangox.Client` behaviour. Defaults to
    `Arangox.Client.Gun`.
    * `:client_opts` - Options for the client library being used. *WARNING*: If `:transport_opts`
    is set here it will override the options given to `:tcp_opts` _and_ `:ssl_opts`.
    * `:failover_callback` - A function to call every time arangox fails to establish a
    connection. This is called regardless of whether or not it's connecting to an endpoint in
    an _active failover_ setup. Can be either an anonymous function that takes one argument
    (which is an `%Arangox.Error{}` struct), or a three-element tuple containing arguments
    to pass to `apply/3` (in which case an `%Arangox.Error{}` struct is always prepended to
    the arguments).
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    ensure_valid!(opts)

    DBConnection.start_link(__MODULE__.Connection, opts)
  end

  @doc """
  Runs a GET request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec get(conn, path, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def get(conn, path, headers \\ [], opts \\ []) do
    request(conn, :get, path, "", headers, opts)
  end

  @doc """
  Runs a GET request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec get!(conn, path, [header], [DBConnection.option()]) :: Response.t()
  def get!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :get, path, "", headers, opts)
  end

  @doc """
  Runs a HEAD request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec head(conn, path, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def head(conn, path, headers \\ [], opts \\ []) do
    request(conn, :head, path, "", headers, opts)
  end

  @doc """
  Runs a HEAD request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec head!(conn, path, [header], [DBConnection.option()]) :: Response.t()
  def head!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :head, path, "", headers, opts)
  end

  @doc """
  Runs a DELETE request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec delete(conn, path, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def delete(conn, path, headers \\ [], opts \\ []) do
    request(conn, :delete, path, "", headers, opts)
  end

  @doc """
  Runs a DELETE request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec delete!(conn, path, [header], [DBConnection.option()]) :: Response.t()
  def delete!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :delete, path, "", headers, opts)
  end

  @doc """
  Runs a POST request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec post(conn, path, body, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def post(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :post, path, body, headers, opts)
  end

  @doc """
  Runs a POST request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec post!(conn, path, body, [header], [DBConnection.option()]) :: Response.t()
  def post!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :post, path, body, headers, opts)
  end

  @doc """
  Runs a PUT request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec put(conn, path, body, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def put(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :put, path, body, headers, opts)
  end

  @doc """
  Runs a PUT request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec put!(conn, path, body, [header], [DBConnection.option()]) :: Response.t()
  def put!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :put, path, body, headers, opts)
  end

  @doc """
  Runs a PATCH request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec patch(conn, path, body, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def patch(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :patch, path, body, headers, opts)
  end

  @doc """
  Runs a PATCH request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec patch!(conn, path, body, [header], [DBConnection.option()]) :: Response.t()
  def patch!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :patch, path, body, headers, opts)
  end

  @doc """
  Runs a OPTIONS request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec options(conn, [DBConnection.option()]) :: {:ok, Request.t(), Response.t()} | {:error, any}
  def options(conn, opts \\ []) do
    request(conn, :options, "", "", [], opts)
  end

  @doc """
  Runs a OPTIONS request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec options!(conn, [DBConnection.option()]) :: Response.t()
  def options!(conn, opts \\ []) do
    request!(conn, :options, "", "", [], opts)
  end

  @doc """
  Runs a request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec request(conn, method, path, body, [header], [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def request(conn, method, path, body \\ "", headers \\ [], opts \\ []) do
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute(conn, request, nil, opts)
  end

  @doc """
  Runs a request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec request!(conn, method, path, body, [header], [DBConnection.option()]) :: Response.t()
  def request!(conn, method, path, body \\ "", headers \\ [], opts \\ []) do
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute!(conn, request, nil, opts)
  end

  @doc """
  Acquire a connection from a pool and run a series of requests with it.
  If the connection disconnects, all future calls using that connection
  reference will fail.

  Requests can be nested multiple times if the connection reference is used
  to start a nested transaction (i.e. calling another function that calls
  this one). The top level transaction function will represent the actual
  transaction.

  Delegates to `DBConnection.transaction/3`.

  ## Example

      {:ok, result} =
        Arangox.transaction(conn, fn c  ->
          Arangox.request!(c, ...)
        end)
  """
  @spec transaction(conn, (DBConnection.t() -> result), [DBConnection.option()]) ::
          {:ok, result} | {:error, any}
        when result: var
  defdelegate transaction(conn, fun, opts \\ []), to: DBConnection

  @doc """
  Returns the configured JSON library.

  To customize the JSON library, include the following in your `config/config.exs`:

      config :arangox, :json_library, Module

  Defaults to `Jason`.
  """
  @spec json_library() :: module()
  def json_library, do: Application.get_env(:arangox, :json_library, Jason)

  defp ensure_valid!(opts) do
    if endpoints = Keyword.get(opts, :endpoints) do
      unless is_list(endpoints) and endpoints_valid?(endpoints) do
        raise ArgumentError, """
        The :endpoints option expects a non-empty list of binaries, got: \
        #{inspect(endpoints)}
        """
      end
    end

    if client = Keyword.get(opts, :client) do
      ensure_client_valid!(client)
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

  defp ensure_client_valid!(client) do
    cond do
      not is_atom(client) ->
        raise ArgumentError, """
        The :client option expects a module, got: #{inspect(client)}
        """

      client in [Gun, Mint] ->
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
