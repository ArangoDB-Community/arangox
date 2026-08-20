defmodule Arangox do
  @readme Path.expand("../README.md", __DIR__)

  # Recompile this module when the README changes, since it is the moduledoc.
  @external_resource @readme

  @moduledoc @readme
             |> File.read!()
             |> String.split("\n")
             |> Enum.drop(2)
             |> Enum.join("\n")

  require Logger

  alias __MODULE__.{
    Auth,
    Client,
    Connection,
    Endpoint,
    Error,
    GunClient,
    MintClient,
    Query,
    Request,
    Response,
    Transaction,
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
  @type headers :: [{binary, binary}]
  @type query :: binary | Query.t()
  @type bindvars :: keyword | map

  @typedoc """
  Remaps a server-advertised redirect endpoint to one this client can reach.

  A map is looked up by the advertised endpoint; a missing entry refuses the
  redirect. A function (or `{module, function, args}`, which is applied with the
  advertised endpoint prepended to `args`) returns the endpoint to use, and
  anything other than an endpoint binary refuses the redirect.
  """
  @type endpoint_mapper ::
          %{optional(endpoint) => endpoint}
          | (endpoint -> endpoint | nil)
          | {module, atom, [any]}

  @type start_option ::
          {:client, module}
          | {:endpoints, list(endpoint)}
          | {:endpoint_mapper, endpoint_mapper}
          | {:auth, Arangox.Auth.t()}
          | {:database, binary}
          | {:headers, headers}
          | {:read_only?, boolean}
          | {:connect_timeout, timeout}
          | {:request_timeout, pos_integer}
          | {:failover_callback, (Error.t() -> any) | {module, atom, [any]}}
          | {:tcp_opts, [:gen_tcp.connect_option()]}
          | {:ssl_opts, [:ssl.tls_client_option()]}
          | {:client_opts, keyword() | map()}
          | {:json_library, module}
          | {:content_type, :json | :velocypack}
          | {:max_body_size, pos_integer}
          | {:vst_maxsize, pos_integer}
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
    warn_deprecated_app_config(opts)

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
    * `:headers` - A list of `{name, value}` header tuples sent with every request,
    in the order given, before the request's own headers. Nothing is merged,
    deduplicated, renamed or re-cased; see the "Headers" section of the README
    for the exact wire behavior per client.
    * `:disconnect_on_error_codes` - A list of status codes that will trigger a forced disconnect.
    Only integers within the range `400..599` are affected. Defaults to
    `[401, 405, 503, 505]`.
    * `:allow_cleartext_auth` - Permit `:auth` credentials to be sent to a cleartext
    (`http://`) endpoint that is not on this machine. Defaults to `false`, and a pool
    configured that way refuses to start: the credentials would be readable by anything
    on the network path. Loopback endpoints are exempt and need no opt-in.
    * `:auth` - Configure whether to resolve authorization.
    Options are: `{:basic, username, password}`, `{:bearer, token}`.
    * `:endpoint_mapper` - Remaps the endpoint a server advertises in the _x-arango-endpoint_
    header of a `503` to an address this client can reach. Either a map of
    `advertised endpoint => target endpoint`, a one-argument function returning the target
    endpoint, or an `{module, function, args}` tuple (the advertised endpoint is prepended to
    `args`). A map with no entry for the advertised endpoint, or a function returning anything
    that is not an endpoint binary, refuses the redirect. Defaults to no mapper.
    __This is a trust boundary__: see _Leader redirects_ below before setting it.
    * `:read_only?` - Read-only pools will only connect to _followers_ in an active failover
    setup and add an _x-arango-allow-dirty-read_ header to every request. Defaults to `false`.
    Read-only pools never follow a leader redirect — not landing on the leader is what the
    option is for.
    * `:connect_timeout` - Sets the timeout for establishing connections with a database.
    It also bounds the probes the connect pipeline makes on the open socket (the
    authentication, availability and version stages) — all of them together, not one budget
    each — so a server that completes the handshake and then goes quiet cannot wedge a
    connection attempt, and adding a stage cannot extend the worst case. The budget is per
    endpoint attempt: each endpoint the failover walk reaches gets its own.
    * `:request_timeout` - The longest arangox will wait on the socket for one request's
    response, in milliseconds. Must be a positive integer; `0`, negatives and `:infinity`
    are rejected here and per request. Defaults to `15_000`, the same as `DBConnection`'s
    `:timeout`. It is a **ceiling**, not the whole story — see _Request timeouts_ below.
    Can be overridden per request.
    * `:tcp_opts` - Transport options for the tcp socket interface (`:gen_tcp` in the case
    of mint).
    * `:ssl_opts` - Transport options for the ssl socket interface (`:ssl` in the case of
    mint).
    * `:client` - A module that implements the `Arangox.Client` behaviour. Defaults to
    `Arangox.MintClient`. `Arangox.VelocyClient` speaks VelocyStream, which ArangoDB
    removed in server 3.12 — it remains supported as an explicit opt-in for 3.11
    deployments.
    * `:client_opts` - Options for the client library being used. *WARNING*: If `:transport_opts`
    is set here it will override the options given to `:tcp_opts` _and_ `:ssl_opts`.
    * `:failover_callback` - A function to call every time arangox fails to establish a
    connection. This is only called if a list of endpoints is given, regardless of whether or not
    it's connecting to an endpoint in an _active failover_ setup. Can be either an anonymous function
    that takes one argument (which is an `%Arangox.Error{}` struct), or a three-element tuple
    containing arguments to pass to `apply/3` (in which case an `%Arangox.Error{}` struct is always
    prepended to the arguments).
    * `:json_library` - The module used to encode and decode JSON request and response
    bodies. Only the HTTP clients use it; `Arangox.VelocyClient` speaks _VelocyPack_.
    Must export `encode!/1`, `decode/1` and `decode!/1`. Defaults to `Jason`.
    * `:vst_maxsize` - The maximum size, in bytes, of a single _VelocyStream_ chunk
    written by `Arangox.VelocyClient`. Must be an integer greater than 24, the size of a
    chunk header. Defaults to `30_720`.
    * `:content_type` - `:json` (the default) or `:velocypack`, selecting how an
    HTTP client encodes request bodies. `:velocypack` requires the `:velocy`
    library, sends `content-type: application/x-velocypack`, and asks for the
    same in return with an `accept` header. Responses are decoded by *their own*
    content type, so a server that declines _VelocyPack_ and answers in JSON is
    still read correctly. A `content-type` or `accept` header set among a
    request's *own* headers wins over the pool's setting — the codec is chosen
    from the first `content-type` entry there, any casing, and never from the
    pool's `:headers` list — and one naming neither codec — `text/plain` for
    `/_api/import`, `application/octet-stream` — sends the request body raw:
    it must already be a binary in its wire form. Ignored by
    `Arangox.VelocyClient`, which carries its own body encoding.
    * `:max_body_size` - The largest response body, in bytes, handed to a codec.
    A larger body is answered with a structured error (`reason: :body_too_large`)
    before any decoding runs, bounding what a hostile or broken server can make
    the pool parse. Defaults to `134_217_728` (128 MiB). Ignored by
    `Arangox.VelocyClient`.

  ## Leader redirects

  In an _active failover_ setup a follower answers `503` and names the current leader in an
  _x-arango-endpoint_ response header. Arangox follows that header during connect, but only
  when the target passes an admission policy. The pool holds your credentials and would send
  them to whatever host the server named, so:

    1. The advertised value must parse as an endpoint. One that does not is refused, not
    raised.
    2. Its normalized origin — encryption class, host **and port** — must already appear in
    `:endpoints`, or `:endpoint_mapper` must admit it. Normalized means `tcp://` compares
    equal to `http://` and `ssl://`/`tls://` to `https://`, because the server advertises in
    its own scheme vocabulary rather than yours. The comparison uses the full origin and not
    just the host: a configured `http://db.internal:8529` does not authorize a redirect to
    `http://db.internal:9999`, which is a different service on the same machine.
    3. An encrypted connection is never redirected to a cleartext one, even to an endpoint
    that is configured.
    4. At most three redirects are followed per connect attempt, counted across the whole
    endpoint walk, so a pair of servers redirecting to each other terminates.

  A refused redirect is treated as what it is — an endpoint that answered and is unusable. The
  walk moves on to the next endpoint, `:failover_callback` fires, and the error says which
  redirect was refused and why. A redirect that *is* followed is normal operation rather than a
  failure and does not fire `:failover_callback`.

  ### `:endpoint_mapper` is a trust boundary

  `:endpoint_mapper` is the only way to follow a redirect to an address that is not in
  `:endpoints`. Its output is validated the same way — it must parse, and it may not downgrade
  encryption — but it is **not** re-checked against `:endpoints`, because remapping to an
  address you never configured is the whole point. A mapper that returns its input unchanged
  therefore switches the policy off entirely and lets any server that can answer a connect
  probe send your credentials anywhere. Map the advertised endpoints you recognise and refuse
  everything else; the map form does exactly that.

  It exists for the containerized case. Running `docker-compose.yml`'s `resilient_single`
  service, the followers on host ports 8003 and 8005 advertise the leader as
  `http://localhost:8539` — 8539 is the leader's port *inside* the container, and from the host
  the leader is on 8004. No host-side `:endpoints` list can contain `localhost:8539`, so the
  default policy refuses that redirect even though it is legitimate. The mapper is how you say
  where the leader really is:

      Arangox.start_link(
        endpoints: ["http://localhost:8003"],
        endpoint_mapper: %{"http://localhost:8539" => "http://localhost:8004"}
      )

  Map keys are matched on their normalized origin too, so the key above also answers an
  advertised `tcp://localhost:8539`.

  A topology whose members sit on their real published addresses — the usual bare-metal
  active-failover deployment, where `:endpoints` lists the same addresses the servers
  advertise — needs no mapper at all.

  ## Request timeouts

  Every request is bounded. Two numbers decide by how much, and they are not the same
  kind of number:

    * your `:timeout` (`DBConnection`'s, per call, 15 seconds by default) is a **budget**
      that starts counting the moment you ask for a connection — including the time you
      spend queueing for one;
    * `:request_timeout` is a **ceiling** on how long any single request may sit on the
      socket.

  Arangox waits for `min(what is left of your budget, :request_timeout)`, less a small
  margin. So a caller that waited 14 seconds for a free connection gets the last second,
  not a fresh 15 — and `Arangox.get(conn, path, [], timeout: 500)` really does come back
  within 500ms, with an `Arangox.Error` whose `:reason` is `:timeout`, rather than with
  `DBConnection`'s "queued and checked out for longer than" error some time later.

  Raise the ceiling for one slow request without loosening the pool:

      Arangox.post(conn, "/_api/cursor", body, [], request_timeout: 60_000, timeout: 65_000)

  Both numbers matter there: `:request_timeout` alone cannot buy more time than the
  caller's budget allows.

  If the budget is already gone by the time a connection frees up, the request is not
  sent at all and the error's `:reason` is `:deadline_exceeded`. That connection is
  healthy and stays in the pool.

  `timeout: :infinity` waives the budget, not the ceiling: such a request still gets
  `:request_timeout` on the socket. There is no way to configure an unbounded wait.

  **A request that times out on the socket takes its connection down with it.** Arangox
  cannot tell where an abandoned response ended, so reusing the connection would serve
  the leftover bytes to whoever draws it next. The pool reconnects; the request is *not*
  retried, because it may well have been executed.

  Inside `run/3` and `transaction/3` the block's own `:timeout` bounds every request made
  **on the block's connection**, since that is the deadline `DBConnection` armed when the
  block checked it out. Such a request never gets a budget longer than what is left of the
  block's — including a cursor's per-batch fetches.

  A request made from inside a block to a *different* pool is a different checkout with a
  deadline of its own, and keeps the budget it asked for:

      Arangox.transaction(primary, fn conn ->
        Arangox.get(conn, path)               # bounded by the block
        Arangox.get(read_replica, other_path) # bounded by its own :timeout
      end)

  ## Deprecated application config

  `:json_library` and `:vst_maxsize` used to be global application config:

      config :arangox, :json_library, Poison
      config :arangox, :vst_maxsize, 12_345

  Both reads still work in v0.8 and will be removed in the next release. A pool that
  does not pass the start option falls back to the application config, and the fallback
  logs a deprecation warning. A value read from the fallback is validated exactly like the start option and
  raises here on the same inputs — `:vst_maxsize` used to be checked by
  `Application.compile_env/3` at compile time, and losing that check would only move the
  failure to a `MatchError` in the middle of a request.

  That warning is emitted **once per pool**: precisely, once per `start_link/1` or
  `child_spec/1` call, in the calling process, and nowhere else. It is deliberately not
  emitted from the `DBConnection` connect callback, which is not a once-per-pool function —
  `DBConnection` re-enters it in the same process on every backoff cycle for as long as
  the pool lives, in each of the pool's `:pool_size` processes. Warning there would log
  several times a second, forever, against an unreachable server. Starting a pool through
  `DBConnection.start_link/2` directly bypasses this module and therefore warns not at
  all, while still honouring the fallback.
  """
  @spec start_link([start_option]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    ensure_opts_valid!(opts)
    warn_deprecated_app_config(opts)

    DBConnection.start_link(__MODULE__.Connection, with_pool_size(opts))
  end

  # `DBConnection` defaults to a single connection, which for an HTTP driver
  # means one request at a time for the whole application: HTTP/1.1 carries one
  # request per connection, so concurrency here is the pool size and nothing
  # else. Ten is a working default for a web application; a caller who sets
  # `:pool_size` still decides.
  @default_pool_size 10

  defp with_pool_size(opts), do: Keyword.put_new(opts, :pool_size, @default_pool_size)

  @doc """
  Runs a GET request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec get(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def get(conn, path, headers \\ [], opts \\ []) do
    request(conn, :get, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a GET request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec get!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def get!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :get, path, "", headers, opts)
  end

  @doc """
  Runs a HEAD request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec head(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def head(conn, path, headers \\ [], opts \\ []) do
    request(conn, :head, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a HEAD request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec head!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def head!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :head, path, "", headers, opts)
  end

  @doc """
  Runs a DELETE request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec delete(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def delete(conn, path, headers \\ [], opts \\ []) do
    request(conn, :delete, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a DELETE request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec delete!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def delete!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :delete, path, "", headers, opts)
  end

  @doc """
  Runs a POST request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec post(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def post(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :post, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a POST request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec post!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def post!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :post, path, body, headers, opts)
  end

  @doc """
  Runs a PUT request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec put(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def put(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :put, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a PUT request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec put!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def put!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :put, path, body, headers, opts)
  end

  @doc """
  Runs a PATCH request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec patch(conn, path, body, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def patch(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request(conn, :patch, path, body, headers, opts) |> do_result()
  end

  @doc """
  Runs a PATCH request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec patch!(conn, path, body, headers, [DBConnection.option()]) :: Response.t()
  def patch!(conn, path, body \\ "", headers \\ [], opts \\ []) do
    request!(conn, :patch, path, body, headers, opts)
  end

  @doc """
  Runs a OPTIONS request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`.
  """
  @spec options(conn, path, headers, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def options(conn, path, headers \\ [], opts \\ []) do
    request(conn, :options, path, "", headers, opts) |> do_result()
  end

  @doc """
  Runs a OPTIONS request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec options!(conn, path, headers, [DBConnection.option()]) :: Response.t()
  def options!(conn, path, headers \\ [], opts \\ []) do
    request!(conn, :options, path, "", headers, opts)
  end

  @doc """
  Runs a request against a connection pool.

  Accepts any of the options accepted by `DBConnection.execute/4`, as well as:

    * `:transaction` - An `t:Arangox.Transaction.t/0` handle from
    `begin_transaction/2`. The request joins that stream transaction: its
    identifier is sent in the _x-arango-trx-id_ header **for this request
    only** — connection state is never written, so the handle applies on
    whichever pooled connection serves the request. Accepts only the handle
    struct, never a bare identifier binary. Every request-running function in
    this module accepts this option.

  `headers` is a list of `{name, value}` string tuples, appended after the
  pool's `:headers` and sent as given — order kept, duplicates kept, nothing
  renamed or re-cased. See the README's "Headers" section for the exact wire
  behavior per client. Maps are no longer accepted (0.8).

  The request struct echoed back on success carries `[redacted]` in place of
  the _authorization_ and _x-arango-trx-id_ header values; what went on the
  wire is the real thing.
  """
  @spec request(conn, method, path, body, headers, [DBConnection.option()]) ::
          {:ok, Request.t(), Response.t()} | {:error, any}
  def request(conn, method, path, body \\ "", headers \\ [], opts \\ []) do
    check_headers_argument!(headers)
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute(conn, request, nil, with_deadline(conn, opts))
  end

  @doc """
  Runs a request against a connection pool. Raises in the case of an error.

  Accepts any of the options accepted by `DBConnection.execute!/4`.
  """
  @spec request!(conn, method, path, body, headers, [DBConnection.option()]) ::
          Response.t()
  def request!(conn, method, path, body \\ "", headers \\ [], opts \\ []) do
    check_headers_argument!(headers)
    request = %Request{method: method, path: path, body: body, headers: headers}

    DBConnection.execute!(conn, request, nil, with_deadline(conn, opts))
  end

  # The message never renders an element: a header value may be a credential
  # or a transaction identifier.
  defp check_headers_argument!(headers) when is_list(headers) do
    if Enum.all?(headers, fn
         {name, value} -> is_binary(name) and is_binary(value)
         _other -> false
       end) do
      :ok
    else
      bad_headers_argument!()
    end
  end

  defp check_headers_argument!(_headers), do: bad_headers_argument!()

  defp bad_headers_argument! do
    raise ArgumentError,
          "request headers are a list of {name, value} tuples since 0.8, sent in order " <>
            "after the pool's :headers; maps are no longer accepted"
  end

  defp do_result({:ok, _request, response}) do
    {:ok, response}
  end

  defp do_result({:error, exception}), do: {:error, exception}

  ## The timeout budget

  # `DBConnection`'s default `:timeout` (`db_connection/holder.ex`, `@timeout`).
  # Not exported by `DBConnection`, so it is mirrored here; the same number is
  # `Arangox.Client.default_request_timeout/0`.
  @dbconnection_default_timeout 15_000

  # Converts the caller's budget into an absolute instant, **here**, before
  # `DBConnection` can spend any of it queueing for a connection.
  #
  # `:timeout` is a duration whose clock starts when
  # the caller asks for a connection; `opts` is then threaded unchanged all the
  # way to `Arangox.Connection.handle_execute/4`, still carrying the original
  # duration, long after part of it has been spent. A socket wait derived from
  # that duration restarts a clock that has already been running, and the
  # caller outlives the very deadline it asked for — with `DBConnection`'s own
  # deadline firing on the *pool* process, tearing the connection down without
  # unblocking the caller stuck in `recv`. See
  # `docs/solutions/architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md`.
  #
  # `:deadline` is `DBConnection`'s own option for exactly this quantity — an
  # absolute monotonic instant in milliseconds — so stamping it introduces no
  # competing key and tightens `DBConnection`'s checkout deadline onto the same
  # instant instead of a slightly later one.
  #
  # The lowest of the three candidates wins: a `:deadline` the caller set
  # explicitly, the one derived from `:timeout`, and the enclosing `run/3` or
  # `transaction/3` block's — when this request belongs to that block, see
  # `block_deadline/1`. `timeout: :infinity` contributes nothing, and if
  # nothing else does either the stamped value is `nil` — the pool's
  # `:request_timeout` still bounds the request, but no deadline is invented
  # for a caller who asked for none.
  #
  # The key is stamped either way, `nil` included. `DBConnection` treats
  # `deadline: nil` and an absent `:deadline` identically — its own option type
  # is `{:deadline, integer | nil}` (`db_connection.ex`) and `abs_timeout/2`
  # reads it with `Keyword.get/2`, which answers `nil` for both — so the `nil`
  # costs nothing there, and it is what tells
  # `Arangox.Connection.with_deadline/2` that the question of whether an
  # enclosing block applies has already been asked and answered.
  defp with_deadline(conn, opts) do
    Keyword.put(opts, :deadline, deadline_from(conn, opts))
  end

  defp deadline_from(conn, opts) do
    budget = Keyword.get(opts, :timeout, @dbconnection_default_timeout)

    [
      if(is_integer(budget), do: Client.monotonic_ms() + budget),
      Keyword.get(opts, :deadline),
      block_deadline(conn)
    ]
    |> Enum.filter(&is_integer/1)
    |> case do
      [] -> nil
      deadlines -> Enum.min(deadlines)
    end
  end

  # The enclosing block's deadline applies to the block's **own** connection and
  # to nothing else.
  #
  # The carrier is per process, so without this a request to an unrelated pool
  # issued from inside a block — a read replica, a second tenant, an audit write
  # — would silently be given what was left of that block's budget instead of
  # the one it asked for. Discriminating costs nothing and reaches into nothing
  # private: `DBConnection`'s `@type conn :: GenServer.server() | t` is public,
  # so the block's connection is exactly the `%DBConnection{}` case and a pool
  # name or pid is exactly the other one. (Note what is *not* being read here:
  # nothing asks which pool a `%DBConnection{}` belongs to, which would mean
  # opening its private `pool_ref` record.)
  #
  # A block on a second pool nested inside a block on the first is already
  # right: it publishes its own deadline for its duration, and `in_block/2`
  # restores the outer one after.
  defp block_deadline(%DBConnection{}), do: Connection.caller_deadline()
  defp block_deadline(_other_pool), do: nil

  # `run/3` and `transaction/3` hold a connection across many requests, and
  # `DBConnection` arms exactly one deadline for the whole block — at the
  # block's checkout, from the block's `:timeout`. Requests inside the block
  # therefore have to be bounded by what is left of *that*, not by a fresh
  # budget each. The block's deadline is published for the duration of the
  # block so they can be, including the ones arangox never sees the options of
  # (a cursor's per-batch fetches, and the transaction callbacks
  # `DBConnection` invokes with its own option list).
  defp in_block(opts, fun) do
    previous = Connection.put_caller_deadline(Keyword.get(opts, :deadline))

    try do
      fun.()
    after
      Connection.restore_caller_deadline(previous)
    end
  end

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
  def run(conn, fun, opts \\ []) do
    opts = with_deadline(conn, opts)

    in_block(opts, fn -> DBConnection.run(conn, fun, opts) end)
  end

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
  def transaction(conn, fun, opts \\ []) do
    opts = with_deadline(conn, opts)

    in_block(opts, fn -> DBConnection.transaction(conn, fun, opts) end)
  end

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

  ## Stream transaction handles
  #
  # The handle form never goes through DBConnection's transaction machinery:
  # begin, commit, abort and status are plain requests, with the transaction's
  # identity carried in the handle rather than in any connection's state. That
  # is what lets any pooled connection serve them. The four functions carry
  # explicit `_transaction` names because the closure form already owns
  # `transaction/3`, `status/1` and `abort/2` — and `abort/2` in particular has
  # incompatible semantics (it raises to roll back); dispatching both meanings
  # off one name on the argument's type would make a mixed-up call site run
  # instead of fail.

  @doc """
  Begins a stream transaction and returns a handle to it.

  This is the handle form of transactions. Where `transaction/3` binds the
  transaction to one checked-out connection for the span of a closure, the
  `t:Arangox.Transaction.t/0` returned here carries the transaction's identity
  as a value: pass it to any request through the `:transaction` option and
  that request joins the transaction, whichever pooled connection serves it —
  then finish with `commit_transaction/3` or `abort_transaction/3`, again on
  any connection reaching the same deployment. Verified against an ArangoDB
  3.12 cluster, this includes connections to *different coordinators* of that
  deployment; see `Arangox.Transaction` for the measured scope.

  The handle is a bearer capability — treat it like authentication material
  and do not pass it across a trust boundary. See `Arangox.Transaction`.

  Accepts the same options as `transaction/3`: `:read`, `:write`,
  `:exclusive`, `:properties`, `:database`, and any of the options accepted by
  `DBConnection.execute/4`. A transaction lives in the database it was begun
  in, so pass the same `:database` option to the requests and to
  commit/abort/status that you pass here.

  ## Example

      {:ok, trx} = Arangox.begin_transaction(conn, write: "coll")
      Arangox.post!(conn, "/_api/document/coll", %{a: 1}, [], transaction: trx)
      {:ok, :running} = Arangox.transaction_status(conn, trx)
      {:ok, %Arangox.Response{}} = Arangox.commit_transaction(conn, trx)
  """
  @spec begin_transaction(conn, [transaction_option()]) ::
          {:ok, Transaction.t()} | {:error, any}
  def begin_transaction(conn, opts \\ []) do
    reject_transaction_opt!(opts, "begin_transaction/2")
    request = opts |> Transaction.begin_body() |> Transaction.begin()

    case DBConnection.execute(conn, request, nil, with_deadline(conn, opts)) do
      {:ok, _request, %Response{status: 201, body: %{"result" => %{"id" => id}}}} ->
        Transaction.from_id(id)

      {:ok, _request, %Response{status: status}} ->
        {:error,
         %Error{
           status: status,
           message: "the server's answer to the begin request named no transaction"
         }}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  Begins a stream transaction and returns a handle to it. Raises in the case
  of an error.

  See `begin_transaction/2`.
  """
  @spec begin_transaction!(conn, [transaction_option()]) :: Transaction.t()
  def begin_transaction!(conn, opts \\ []) do
    case begin_transaction(conn, opts) do
      {:ok, %Transaction{} = trx} -> trx
      {:error, exception} when is_exception(exception) -> raise exception
    end
  end

  @doc """
  Commits the stream transaction the handle names.

  Runs against any pooled connection to the deployment the transaction was
  begun on — the handle, not the connection, names the transaction. Accepts
  only a `t:Arangox.Transaction.t/0`, never a bare identifier.

  A failed commit leaves the handle usable: the transaction is still addressed
  by the identifier, so a follow-up `abort_transaction/3` reaches it.
  Committing an already-committed transaction is answered 200 by the server
  (idempotent); aborting or using a committed one is the server's error.

  Accepts any of the options accepted by `DBConnection.execute/4`, plus
  `:database` (pass the one the transaction was begun in).
  """
  @spec commit_transaction(conn, Transaction.t(), [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def commit_transaction(conn, trx, opts \\ [])

  def commit_transaction(conn, %Transaction{} = trx, opts) do
    reject_transaction_opt!(opts, "commit_transaction/3")

    with {:ok, id} <- Transaction.fetch_id(trx) do
      conn
      |> DBConnection.execute(Transaction.commit(id), nil, with_deadline(conn, opts))
      |> do_result()
    end
  end

  def commit_transaction(_conn, other, _opts) do
    raise ArgumentError, not_a_handle("commit_transaction/3", other)
  end

  @doc """
  Commits the stream transaction the handle names. Raises in the case of an
  error.

  See `commit_transaction/3`.
  """
  @spec commit_transaction!(conn, Transaction.t(), [DBConnection.option()]) :: Response.t()
  def commit_transaction!(conn, trx, opts \\ []) do
    case commit_transaction(conn, trx, opts) do
      {:ok, %Response{} = response} -> response
      {:error, exception} when is_exception(exception) -> raise exception
    end
  end

  @doc """
  Aborts the stream transaction the handle names, discarding its writes.

  This is the handle form's counterpart to the closure form's `abort/2`, and
  deliberately not the same function: `abort/2` raises to roll the *current
  closure* back through `DBConnection.rollback/2`, while this sends an abort
  request for the named transaction and returns. It runs against any pooled
  connection to the deployment; accepts only a `t:Arangox.Transaction.t/0`.

  Accepts any of the options accepted by `DBConnection.execute/4`, plus
  `:database` (pass the one the transaction was begun in).
  """
  @spec abort_transaction(conn, Transaction.t(), [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def abort_transaction(conn, trx, opts \\ [])

  def abort_transaction(conn, %Transaction{} = trx, opts) do
    reject_transaction_opt!(opts, "abort_transaction/3")

    with {:ok, id} <- Transaction.fetch_id(trx) do
      conn
      |> DBConnection.execute(Transaction.abort(id), nil, with_deadline(conn, opts))
      |> do_result()
    end
  end

  def abort_transaction(_conn, other, _opts) do
    raise ArgumentError, not_a_handle("abort_transaction/3", other)
  end

  @doc """
  Aborts the stream transaction the handle names. Raises in the case of an
  error.

  See `abort_transaction/3`.
  """
  @spec abort_transaction!(conn, Transaction.t(), [DBConnection.option()]) :: Response.t()
  def abort_transaction!(conn, trx, opts \\ []) do
    case abort_transaction(conn, trx, opts) do
      {:ok, %Response{} = response} -> response
      {:error, exception} when is_exception(exception) -> raise exception
    end
  end

  @doc """
  Fetches the status of the stream transaction the handle names from the
  database.

  Answers from the body of the server's reply, not from the HTTP status: the
  server keeps answering 200 for a finished transaction within a retention
  window, with the actual state in the body. Returns `{:ok, :running}`,
  `{:ok, :committed}` or `{:ok, :aborted}`; a status this driver does not
  recognize is returned as its raw binary rather than turned into an atom.

  This is the handle form's counterpart to `status/1`, which answers for the
  closure transaction bound to a connection. It runs against any pooled
  connection to the deployment; accepts only a `t:Arangox.Transaction.t/0`.

  Accepts any of the options accepted by `DBConnection.execute/4`, plus
  `:database` (pass the one the transaction was begun in).
  """
  @spec transaction_status(conn, Transaction.t(), [DBConnection.option()]) ::
          {:ok, :running | :committed | :aborted | binary} | {:error, any}
  def transaction_status(conn, trx, opts \\ [])

  def transaction_status(conn, %Transaction{} = trx, opts) do
    reject_transaction_opt!(opts, "transaction_status/3")

    with {:ok, id} <- Transaction.fetch_id(trx),
         {:ok, %Response{} = response} <-
           conn
           |> DBConnection.execute(Transaction.status(id), nil, with_deadline(conn, opts))
           |> do_result() do
      trx_status_from_body(response)
    end
  end

  def transaction_status(_conn, other, _opts) do
    raise ArgumentError, not_a_handle("transaction_status/3", other)
  end

  @doc """
  Fetches the status of the stream transaction the handle names from the
  database. Raises in the case of an error.

  See `transaction_status/3`.
  """
  @spec transaction_status!(conn, Transaction.t(), [DBConnection.option()]) ::
          :running | :committed | :aborted | binary
  def transaction_status!(conn, trx, opts \\ []) do
    case transaction_status(conn, trx, opts) do
      {:ok, status} -> status
      {:error, exception} when is_exception(exception) -> raise exception
    end
  end

  defp trx_status_from_body(%Response{body: %{"result" => %{"status" => status}}}) do
    case status do
      "running" -> {:ok, :running}
      "committed" -> {:ok, :committed}
      "aborted" -> {:ok, :aborted}
      other when is_binary(other) -> {:ok, other}
    end
  end

  defp trx_status_from_body(%Response{status: status}) do
    {:error, %Error{status: status, message: "the server's answer named no transaction status"}}
  end

  # The four handle functions already name their transaction — in the handle
  # argument, or in begin's case by beginning a new one — so a `:transaction`
  # option here is a second, contradictory identity. Rejected loudly rather
  # than silently attaching a foreign transaction's header to a management
  # request. The value is not echoed; it may hold a live identifier.
  defp reject_transaction_opt!(opts, fun) do
    if Keyword.has_key?(opts, :transaction) do
      raise ArgumentError, """
      Arangox.#{fun} does not accept the :transaction option; the transaction \
      it operates on is already named. Pass :transaction to data requests \
      instead:

          Arangox.get(conn, path, [], transaction: trx)
      """
    end

    :ok
  end

  # The wrong value is described by type, never echoed: a bare binary handed
  # where a handle belongs is most likely a live transaction identifier, which
  # must not end up in an error message or a log.
  defp not_a_handle(fun, other) do
    """
    Arangox.#{fun} accepts only an %Arangox.Transaction{} handle, from \
    Arangox.begin_transaction/2 or Arangox.Transaction.new/1 — never a bare \
    identifier. Got: #{describe_type(other)} (the value is not echoed, in \
    case it is a live transaction identifier).
    """
  end

  defp describe_type(%module{}), do: "a #{inspect(module)} struct"
  defp describe_type(value) when is_binary(value), do: "a binary"
  defp describe_type(value) when is_atom(value), do: "an atom"
  defp describe_type(value) when is_integer(value), do: "an integer"
  defp describe_type(value) when is_list(value), do: "a list"
  defp describe_type(value) when is_map(value), do: "a map"
  defp describe_type(_value), do: "an unsupported value"

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
    * `:transaction` - An `t:Arangox.Transaction.t/0` handle from
    `begin_transaction/2`; the cursor's requests join that stream transaction.

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
  def cursor(conn, query, bindvars \\ [], opts \\ [])

  def cursor(conn, %Query{} = query, bindvars, opts),
    do: DBConnection.stream(conn, query, bindvars, warn_unknown_query_opts(opts))

  # A binary query is wrapped here rather than passed through. Letting a
  # binary reach `DBConnection` as the query itself would require a
  # `DBConnection.Query` implementation for `BitString` — a protocol
  # implementation for a built-in type, shipped by a library, which makes any
  # application that installs a second driver doing the same
  # un-consolidatable. Wrapping converges both forms on one struct and costs
  # the caller nothing.
  def cursor(conn, query, bindvars, opts) when is_binary(query),
    do: cursor(conn, %Query{query: query}, bindvars, opts)

  @doc """
  Runs an AQL query and answers with every row it returned.

  _ArangoDB_ executes AQL through a server-side cursor whichever of these two
  functions you use — they send the same request. The difference is who drives
  the cursor afterwards: this one drains it and hands back a single response
  holding the complete result, while `cursor/4` hands you the cursor to read a
  batch at a time inside a `run/3` or `transaction/3` block.

  A result that fits one batch costs exactly one request either way, because the
  server keeps no cursor when it has nothing more to send. The extra requests
  happen only when there is more, and then only here — a caller who stops
  reading a `cursor/4` stream never asks for the rest.

  Takes an AQL binary or an `t:Arangox.Query.t/0`. AQL options may be given
  here or carried by the query; see `Arangox.Query` for the names.

  Does **not** ask the server to reuse a cached query plan unless told to. Pass
  `use_plan_cache: true` when the same statement runs repeatedly; it is opt-in
  because it has a server-version floor and the server refuses to cache some
  statements outright. There is no prepare step to do it for you — see
  `Arangox.Query`.

  ## Example

      iex> {:ok, conn} = Arangox.start_link()
      iex> {:ok, response} =
      iex>   Arangox.query(conn, "FOR i IN [1, 2, 3] FILTER i != @skip RETURN i", %{skip: 2})
      iex> response.body["result"]
      [1, 3]
  """
  @spec query(conn(), query, bindvars, [DBConnection.option()]) ::
          {:ok, Response.t()} | {:error, any}
  def query(conn, query, bindvars \\ [], opts \\ [])

  def query(conn, %Query{} = query, bindvars, opts) do
    conn
    |> DBConnection.execute(query, bindvars, with_deadline(conn, warn_unknown_query_opts(opts)))
    |> do_result()
  end

  def query(conn, statement, bindvars, opts) when is_binary(statement),
    do: query(conn, %Query{query: statement}, bindvars, opts)

  @doc """
  Runs an AQL query and answers with every row it returned. Raises on error.

  See `query/4`.
  """
  @spec query!(conn(), query, bindvars, [DBConnection.option()]) :: Response.t()
  def query!(conn, query, bindvars \\ [], opts \\ [])

  def query!(conn, %Query{} = query, bindvars, opts),
    do:
      DBConnection.execute!(
        conn,
        query,
        bindvars,
        with_deadline(conn, warn_unknown_query_opts(opts))
      )

  def query!(conn, statement, bindvars, opts) when is_binary(statement),
    do: query!(conn, %Query{query: statement}, bindvars, opts)

  @plan_cache_path "/_api/query-plan-cache"

  @doc """
  Lists the current database's cached query plans.

  A **database-wide administrative operation**. The plan cache is shared by
  every caller of the database, so this exposes the query text of statements
  other callers ran, and `clear_plan_cache/2` discards plans they are relying
  on. Requires read privileges on the database.

  Each entry is the server's own map, including `"query"`, `"hash"` — the same
  value `Arangox.Response.plan_cache_key/1` answers — `"hits"`, `"memoryUsage"`
  and `"created"`.

  > #### An empty list is ambiguous {: .warning}
  >
  > The server returns only the plans whose collections the caller may read, and
  > it filters rather than refuses. A caller permitted on no collections is
  > answered `[]`, which is indistinguishable from an empty cache. A caller with
  > no privileges on the *database* is refused outright, which does surface as
  > an error — note that the refusal is a `401`, and `401` is in the default
  > `:disconnect_on_error_codes`, so it also retires the connection. ArangoDB
  > uses the same status and error number for bad credentials and for
  > insufficient rights, so the driver has nothing to tell them apart by.

  Accepts `:database` and any of the options accepted by
  `DBConnection.execute/4`.
  """
  @spec plan_cache(conn(), [DBConnection.option()]) :: {:ok, [map]} | {:error, any}
  def plan_cache(conn, opts \\ []) do
    with {:ok, %Response{body: entries}} <- get(conn, @plan_cache_path, [], opts) do
      {:ok, List.wrap(entries)}
    end
  end

  @doc """
  Lists the current database's cached query plans. Raises in the case of an error.

  See `plan_cache/2`, including its warning about empty results.
  """
  @spec plan_cache!(conn(), [DBConnection.option()]) :: [map]
  def plan_cache!(conn, opts \\ []),
    do: conn |> get!(@plan_cache_path, [], opts) |> Map.fetch!(:body) |> List.wrap()

  @doc """
  Discards every cached query plan in the current database.

  A **database-wide administrative operation**, and the blunt kind: the server
  has no per-entry release, so this affects every caller of the database, whose
  next execution of an affected statement is planned afresh. Requires write
  privileges on the database; read alone is refused with a `403`.

  Clearing is the escape hatch for a plan that has gone stale — a plan is
  optimised against the indexes and statistics that existed when it was built,
  and nothing invalidates it when those change.

  Accepts `:database` and any of the options accepted by
  `DBConnection.execute/4`.
  """
  @spec clear_plan_cache(conn(), [DBConnection.option()]) :: :ok | {:error, any}
  def clear_plan_cache(conn, opts \\ []) do
    with {:ok, %Response{}} <- delete(conn, @plan_cache_path, [], opts), do: :ok
  end

  @doc """
  Discards every cached query plan in the current database. Raises in the case of
  an error.

  See `clear_plan_cache/2`.
  """
  @spec clear_plan_cache!(conn(), [DBConnection.option()]) :: :ok
  def clear_plan_cache!(conn, opts \\ []) do
    _response = delete!(conn, @plan_cache_path, [], opts)
    :ok
  end

  @doc """
  Returns the JSON library from the deprecated application config, or `Jason`.

  Deprecated in v0.8 and to be removed in the next release, along with the
  application-config read it reports on. It answers the *fallback*, not what any particular pool uses:
  since v0.8 the JSON library is a per-pool start option, so two pools can disagree
  and neither has to agree with this. Pass `:json_library` to `start_link/1` instead.

  Emits a deprecation warning on every call, because there is no correct number of
  times to call it.
  """
  @deprecated "Pass :json_library to Arangox.start_link/1 instead"
  @spec json_library() :: module()
  def json_library do
    Logger.warning("""
    Arangox.json_library/0 is deprecated and will be removed in the next release. \
    The JSON library is a per-pool start option now, and this function cannot \
    see it:

        Arangox.start_link(json_library: Poison)
    """)

    __MODULE__.Connection.fallback_json_library()
  end

  # DECISION (scope of "once per pool"): the application-config deprecation
  # warning is emitted here, from `start_link/1` and `child_spec/1`, and nowhere
  # else. Both run exactly once per pool, in the caller's process, before any
  # connection process exists.
  #
  # The tempting home is `Arangox.Connection.resolve_options/1`, next to the
  # resolution itself, and it is wrong. `connect/1` is not a once-per-pool
  # function: `DBConnection` re-enters it in the same process on every backoff
  # cycle for as long as the pool lives, in each of `:pool_size` processes. A
  # warning there fires once per process per reconnect — against an unreachable
  # server with the default backoff that is a permanent log flood, not a
  # deprecation notice. Resolution stays in the connect pipeline; the warning
  # does not follow it there.
  defp warn_deprecated_app_config(opts) do
    warn_app_config_key(opts, :json_library, "Arangox.start_link(json_library: Poison)")
    warn_app_config_key(opts, :vst_maxsize, "Arangox.start_link(vst_maxsize: 12_345)")

    :ok
  end

  defp warn_app_config_key(opts, key, example) do
    # Only the fallback is deprecated. A pool that passes the start option is
    # already doing the right thing and hears nothing, whatever the app config says.
    if not Keyword.has_key?(opts, key) and Application.fetch_env(:arangox, key) != :error do
      Logger.warning("""
      Reading #{inspect(key)} from application config is deprecated and will be \
      removed in the next release. It is a per-pool start option now:

          #{example}
      """)
    end

    :ok
  end

  # Option keys owned and consumed by arangox itself.
  @arangox_opts [
    :allow_cleartext_auth,
    :auth,
    :client,
    :client_opts,
    :connect_timeout,
    :content_type,
    :database,
    :disconnect_on_error_codes,
    :endpoint_mapper,
    :endpoints,
    :failover_callback,
    :headers,
    :json_library,
    :max_body_size,
    :read_only?,
    :request_timeout,
    :ssl_opts,
    :tcp_opts,
    :vst_maxsize
  ]

  # DBConnection options that arangox forwards untouched.
  @db_connection_opts [
    :pool,
    :pool_size,
    :pool_index,
    :queue_target,
    :queue_interval,
    :timeout,
    :connect_timeout,
    :backoff_type,
    :backoff_min,
    :backoff_max,
    :after_connect,
    :after_connect_timeout,
    :configure,
    :idle_interval,
    :idle_limit,
    :max_restarts,
    :max_seconds,
    :name,
    :show_sensitive_data_on_connection_error,
    :disconnect_on_error_codes,
    :connection_listeners
  ]

  @known_opts Enum.uniq(@arangox_opts ++ @db_connection_opts)

  defp ensure_opts_valid!(opts) do
    # A present key always validates its value; only an absent key is skipped.
    # Keyword.get/2 must not be used here: it cannot tell `client: false` or
    # `auth: nil` apart from an absent key, which silently skipped validation.
    case Keyword.fetch(opts, :endpoints) do
      {:ok, endpoints} -> validate_endpoints!(endpoints)
      :error -> :ok
    end

    case Keyword.fetch(opts, :endpoint_mapper) do
      {:ok, endpoint_mapper} -> validate_endpoint_mapper!(endpoint_mapper)
      :error -> :ok
    end

    case Keyword.fetch(opts, :auth) do
      {:ok, auth} -> Auth.validate(auth)
      :error -> :ok
    end

    case Keyword.fetch(opts, :headers) do
      {:ok, headers} -> validate_headers!(headers)
      :error -> :ok
    end

    validate_cleartext_auth!(opts)

    case Keyword.fetch(opts, :client) do
      {:ok, client} -> ensure_client_loaded!(client)
      :error -> :ok
    end

    case Keyword.fetch(opts, :database) do
      {:ok, database} -> validate_database!(database)
      :error -> :ok
    end

    # `Arangox.Connection.resolve_options/1` cannot raise on a bad value
    # , so this is the only place a pool started through arangox can be
    # told about one. The same check runs per request in
    # `Arangox.Connection.handle_execute/4`.
    case Keyword.fetch(opts, :request_timeout) do
      {:ok, request_timeout} -> validate_request_timeout!(request_timeout)
      :error -> :ok
    end

    # A pool-level transaction default would attach the
    # previous caller's transaction to whoever draws a connection next —
    # exactly the state leak the handle form exists to prevent. Rejected
    # rather than warned about, because unlike a typo it looks coherent while
    # meaning something incoherent. The value is not echoed; it may hold a
    # live transaction identifier.
    if Keyword.has_key?(opts, :transaction) do
      raise ArgumentError, """
      The :transaction option is per-request, not per-pool: a pool-level \
      transaction would apply one caller's transaction to every caller. Pass \
      the handle to each request instead:

          Arangox.get(conn, path, [], transaction: trx)
      """
    end

    case fetch_opt_or_app_config(opts, :json_library) do
      {:ok, json_library, source} -> validate_json_library!(json_library, source)
      :error -> :ok
    end

    case fetch_opt_or_app_config(opts, :vst_maxsize) do
      {:ok, vst_maxsize, source} -> validate_vst_maxsize!(vst_maxsize, source)
      :error -> :ok
    end

    case Keyword.fetch(opts, :content_type) do
      {:ok, content_type} -> validate_content_type!(content_type)
      :error -> :ok
    end

    case Keyword.fetch(opts, :max_body_size) do
      {:ok, max_body_size} -> validate_max_body_size!(max_body_size)
      :error -> :ok
    end

    warn_unknown_opts(opts)

    :ok
  end

  # VelocyPack is opt-in and needs `:velocy`, which is an optional
  # dependency — so an unavailable codec is refused here rather than at the
  # first request, where `Arangox.Connection` could only answer with an error
  # per call.
  defp validate_content_type!(:json), do: :ok

  defp validate_content_type!(:velocypack) do
    unless Code.ensure_loaded?(VelocyPack) do
      raise ArgumentError, """
      The :content_type option was set to :velocypack, which requires the \
      :velocy library. Add it to your mix deps:

          # mix.exs
          defp deps do
            ...
            {:velocy, "~> 0.1"}
          end
      """
    end

    :ok
  end

  defp validate_content_type!(content_type) do
    raise ArgumentError, """
    The :content_type option expects :json or :velocypack, got: \
    #{inspect(content_type)}
    """
  end

  # Refused here rather than at the first response, where a zero or
  # negative bound would reject every body the pool ever reads.
  defp validate_max_body_size!(value) when is_integer(value) and value > 0, do: :ok

  defp validate_max_body_size!(value) do
    raise ArgumentError, """
    The :max_body_size option expects a positive integer number of bytes, got: \
    #{inspect(value)}
    """
  end

  defp validate_endpoints!(endpoints) do
    unless is_binary(endpoints) or (is_list(endpoints) and endpoints_valid?(endpoints)) do
      raise ArgumentError, """
      The :endpoints option expects a binary or a non-empty list of binaries,\
      got: #{inspect(redact_endpoints(endpoints))}
      """
    end
  end

  # An endpoint may carry userinfo, and a `start_link/1` that raises is the most
  # likely thing anyone pastes into an issue.
  defp redact_endpoints(endpoints) when is_list(endpoints),
    do: Enum.map(endpoints, &Endpoint.redact/1)

  defp redact_endpoints(endpoints), do: Endpoint.redact(endpoints)

  # `:endpoint_mapper` decides whether the pool's credentials may be sent to an
  # endpoint the server named, so a malformed one is rejected here rather than
  # silently refusing every redirect at connect time.
  defp validate_endpoint_mapper!(mapper) when is_function(mapper, 1), do: :ok

  defp validate_endpoint_mapper!({mod, fun, args})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    arity = length(args) + 1

    unless Code.ensure_loaded?(mod) and function_exported?(mod, fun, arity) do
      raise ArgumentError, """
      The :endpoint_mapper option expects a {module, function, args} tuple naming \
      an exported function of arity #{arity} (the advertised endpoint is prepended \
      to args), got: #{inspect({mod, fun, args})}
      """
    end

    :ok
  end

  defp validate_endpoint_mapper!(mapper) when is_map(mapper) and not is_struct(mapper) do
    Enum.each(mapper, fn {advertised, target} ->
      unless is_binary(advertised) and is_binary(target) do
        raise ArgumentError, """
        The :endpoint_mapper option expects a map of endpoint binaries, \
        got: #{inspect(Endpoint.redact(advertised))} => #{inspect(Endpoint.redact(target))}
        """
      end

      case Endpoint.parse(target) do
        {:ok, _endpoint} ->
          :ok

        {:error, message} ->
          raise ArgumentError, """
          The :endpoint_mapper option maps #{inspect(Endpoint.redact(advertised))} to an \
          invalid endpoint: #{message}
          """
      end
    end)
  end

  defp validate_endpoint_mapper!(mapper) do
    raise ArgumentError, """
    The :endpoint_mapper option expects a map of advertised endpoint => target \
    endpoint, a one-argument function or a {module, function, args} tuple, \
    got: #{inspect(mapper)}
    """
  end

  # Cleartext is supported deliberately — plenty of deployments run
  # ArangoDB on a private network and have no interest in terminating TLS for
  # it. What should not happen silently is sending credentials over it to
  # another machine, where every hop in between can read them.
  #
  # So the opt-in is required only where the risk is: credentials configured,
  # cleartext scheme, and an endpoint that is not this machine. A loopback
  # endpoint never leaves the host and is exempt, which is what keeps the
  # documented default configuration — `http://localhost:8529` with `:auth` —
  # working untouched.
  # The message never renders an element: an authorization entry in `:headers`
  # is a documented way to carry a credential.
  defp validate_headers!(headers) do
    valid? =
      is_list(headers) and
        Enum.all?(headers, fn
          {name, value} -> is_binary(name) and is_binary(value)
          _other -> false
        end)

    unless valid? do
      raise ArgumentError, """
      :headers must be a list of {name, value} tuples of strings since 0.8, \
      sent in order before each request's own headers. Maps are no longer \
      accepted; nothing is merged, deduplicated or re-cased.
      """
    end

    :ok
  end

  defp validate_cleartext_auth!(opts) do
    with false <- Keyword.get(opts, :allow_cleartext_auth, false) == true,
         true <- credentialed?(opts),
         [_ | _] = exposed <- cleartext_remote_endpoints(opts) do
      raise ArgumentError, """
      Refusing to send credentials in cleartext to #{Enum.map_join(exposed, ", ", &inspect/1)}.

      Credentials are configured — :auth, or an authorization header in \
      :headers — and these endpoints are neither encrypted nor on this \
      machine, so they would be readable by anything on the path. Either use https:// for them, or pass allow_cleartext_auth: true \
      to say that the network between here and there is trusted.

      Loopback endpoints do not need this.
      """
    else
      _no_exposure -> :ok
    end
  end

  # `:auth` is not the only way a pool carries a credential: `:headers` is
  # merged into every request, so an `authorization` header configured there
  # reaches the wire exactly as a resolved `:auth` would. Header names are
  # case-insensitive, so the match is too.
  defp credentialed?(opts) do
    case Keyword.fetch(opts, :auth) do
      {:ok, {:basic, _username, _password}} -> true
      {:ok, {:bearer, _token}} -> true
      _absent_or_disabled -> authorization_header?(Keyword.get(opts, :headers))
    end
  end

  defp authorization_header?(headers) when is_map(headers) or is_list(headers) do
    Enum.any?(headers, fn
      {name, _value} -> String.downcase(to_string(name)) == "authorization"
      _other -> false
    end)
  end

  defp authorization_header?(_headers), do: false

  defp cleartext_remote_endpoints(opts) do
    opts
    |> Keyword.get(:endpoints, [])
    |> List.wrap()
    |> Enum.filter(&cleartext_remote?/1)
    |> Enum.map(&Endpoint.redact/1)
  end

  defp cleartext_remote?(endpoint) when is_binary(endpoint) do
    case Endpoint.parse(endpoint) do
      {:ok, %Endpoint{ssl?: false, addr: {:tcp, host, _port}}} -> not loopback?(host)
      _unparseable_or_unix_or_tls -> false
    end
  end

  defp cleartext_remote?(_endpoint), do: false

  # A unix socket never leaves the machine and is handled above by not being a
  # `:tcp` address at all.
  #
  # The host is parsed as an address rather than matched as text. A prefix test
  # for "127." also accepts *hostnames* beginning with those characters —
  # `127.0.0.1.nip.io` and any wildcard-DNS name like it resolve wherever their
  # zone says, usually off this machine — so it would exempt exactly the
  # endpoints this check exists to refuse. Anything that is not a recognisable
  # loopback address is treated as remote: this gate fails closed, and the cost
  # of being wrong is an opt-in the operator can grant.
  defp loopback?(host) do
    host = host |> to_string() |> String.trim_leading("[") |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(host)) do
      # 127.0.0.0/8, all of which the stack routes to this machine.
      {:ok, {127, _, _, _}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      # `::ffff:127.0.0.1` and the rest of the IPv4-mapped loopback range; the
      # seventh group holds the high half of the embedded IPv4 address.
      {:ok, {0, 0, 0, 0, 0, 0xFFFF, high, _low}} -> div(high, 256) == 127
      _not_an_address -> host == "localhost"
    end
  end

  defp validate_request_timeout!(request_timeout) do
    case Client.validate_request_timeout(request_timeout) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end
  end

  # The start-up half of path validation. The rule itself lives with the request seam in
  # `Arangox.Connection`, which enforces it again on every request — one rule,
  # two entry points, so a name this raises on cannot reach a path by some
  # other route.
  defp validate_database!(database) do
    case __MODULE__.Connection.validate_database(database) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end
  end

  # The two options that still have a deprecated application-config fallback are
  # validated against whichever source will actually be used, not just against
  # the start option.
  #
  # It has to be here. `Arangox.Connection.resolve_options/1` reads the fallback
  # on every connect attempt and must not raise — a raise there escapes the
  # `DBConnection` callback and turns backoff into a supervisor crash loop — so
  # `start_link/1` and `child_spec/1` are the only places left that can reject
  # it. Validating only the option would be a real loss of assertiveness:
  # `config :arangox, :vst_maxsize, 10` would reach `build_stream/2` as a
  # negative chunk size and raise a MatchError out of
  # `Arangox.VelocyClient.request/2`.
  # Returns the value along with a description of where it came from, so the
  # error names the thing the caller actually has to go and change.
  defp fetch_opt_or_app_config(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        {:ok, value, "The #{inspect(key)} option"}

      :error ->
        case Application.fetch_env(:arangox, key) do
          {:ok, value} -> {:ok, value, "The deprecated `config :arangox, #{inspect(key)}`"}
          :error -> :error
        end
    end
  end

  defp validate_json_library!(json_library, source)
       when is_boolean(json_library) or is_nil(json_library) or not is_atom(json_library) do
    raise ArgumentError, """
    #{source} expects a module, got: #{inspect(json_library)}
    """
  end

  defp validate_json_library!(json_library, source) do
    unless Code.ensure_loaded?(json_library) do
      raise ArgumentError, """
      #{source} expects a module that can be loaded, got: #{inspect(json_library)}
      """
    end

    :ok
  end

  # The VelocyStream chunk header is 24 bytes, so a chunk smaller than that
  # cannot carry a single payload byte. The constant is repeated here rather
  # than read from `Arangox.VelocyClient`, which is only compiled when
  # `:velocy` is available — `:vst_maxsize` has to be validated either way.
  @vst_chunk_header_size 24

  defp validate_vst_maxsize!(vst_maxsize, source) when not is_integer(vst_maxsize) do
    raise ArgumentError, """
    #{source} expects an integer greater than #{@vst_chunk_header_size}, \
    got: #{inspect(vst_maxsize)}
    """
  end

  defp validate_vst_maxsize!(vst_maxsize, source) when vst_maxsize <= @vst_chunk_header_size do
    raise ArgumentError, """
    #{source} must be greater than #{@vst_chunk_header_size}, the size of a \
    VelocyStream chunk header, otherwise a chunk cannot carry any payload. \
    Got: #{inspect(vst_maxsize)}
    """
  end

  defp validate_vst_maxsize!(_vst_maxsize, _source), do: :ok

  # DECISION (unknown options): validate-and-warn, not raise. Arangox forwards
  # opts to DBConnection and cannot enumerate DBConnection's full option
  # surface (pools and future versions add keys), so raising on unknown keys
  # would break valid DBConnection options. Instead, keys that are neither
  # arangox-owned nor known DBConnection options emit a Logger warning naming
  # the unknown key and the closest known key. A typo'd option must not pass
  # silently: `Connection.new/3` builds state with `struct/2`, which drops a
  # key it does not know without complaint.
  defp warn_unknown_opts(opts) do
    for {key, _value} <- opts, is_atom(key) and key not in @known_opts do
      Logger.warning(
        "Unknown option #{inspect(key)} given to arangox#{closest_known_opt(key, @known_opts)}"
      )
    end

    :ok
  end

  # Options a *request* may carry: the per-request arangox options, whatever
  # `DBConnection` accepts, and every AQL option `Arangox.Query` knows.
  @known_query_opts Enum.uniq(
                      [:database, :transaction, :request_timeout, :deadline] ++
                        @db_connection_opts ++ Query.known_options()
                    )

  # The pool-level check above warns about every unknown key, which it can
  # afford because it runs once per pool. This one runs on every query, so it
  # speaks only when it has something specific to say: a key close enough to a
  # known one to be a typo of it. Anything else is far more likely to be a
  # `DBConnection` option this driver does not enumerate — the same reason that
  # check warns rather than raises, and warning once per request would be
  # unsilenceable noise.
  defp warn_unknown_query_opts(opts) do
    for {key, _value} <- opts, is_atom(key) and key not in @known_query_opts do
      case closest_known_opt(key, @known_query_opts) do
        "" ->
          :ok

        suggestion ->
          Logger.warning("Unknown option #{inspect(key)} given to a query#{suggestion}")
      end
    end

    opts
  end

  defp closest_known_opt(key, known) do
    key_string = Atom.to_string(key)

    {closest, distance} =
      known
      |> Enum.map(&{&1, String.jaro_distance(key_string, Atom.to_string(&1))})
      |> Enum.max_by(fn {_key, distance} -> distance end)

    if distance >= 0.77, do: ". Did you mean #{inspect(closest)}?", else: ""
  end

  defp endpoints_valid?(endpoints) when is_list(endpoints) do
    length(endpoints) > 0 and
      Enum.count(endpoints, &is_binary/1) == length(endpoints)
  end

  defp ensure_client_loaded!(client) do
    cond do
      is_boolean(client) or is_nil(client) or not is_atom(client) ->
        raise ArgumentError, """
        The :client option expects a module, got: #{inspect(client)}
        """

      client in [VelocyClient, MintClient, GunClient] ->
        unless Code.ensure_loaded?(client) do
          library = client_dependency(client)

          raise """
          Missing client dependency. Please add #{library} to your mix deps:

              # mix.exs
              defp deps do
                ...
                {:#{library}, "~> ..."}
              end
          """
        end

      true ->
        unless Code.ensure_loaded?(client),
          do: raise("Module #{client} does not exist")
    end

    ensure_client_contract!(client)
  end

  # The hex package, which is not the module name downcased: the modules are
  # `VelocyClient`, `MintClient` and `GunClient`, the packages are `velocy`,
  # `mint` and `gun`.
  defp client_dependency(VelocyClient), do: "velocy"
  defp client_dependency(MintClient), do: "mint"
  defp client_dependency(GunClient), do: "gun"

  # The `Arangox.Client.request` callback gained the caller's per-request
  # options in v0.8. A third-party client still exporting the two-argument
  # version compiles (the compiler only warns about an unimplemented callback),
  # so without this the first request fails with a bare
  # `UndefinedFunctionError` naming an arity nobody wrote. Fail at `start_link`
  # instead, naming the new signature. `Arangox.Client.request/3` translates the
  # same mistake at runtime, for a pool started through `DBConnection`
  # directly.
  defp ensure_client_contract!(client) do
    loaded? = Code.ensure_loaded?(client)

    if loaded? and not function_exported?(client, :request, 3) and
         function_exported?(client, :request, 2) do
      raise ArgumentError, """
      #{inspect(client)} implements the pre-v0.8 Arangox.Client.request/2 callback. \
      Since v0.8 the callback takes the caller's per-request options as its second \
      argument:

          @impl true
          def request(%Arangox.Request{} = request, opts, %Arangox.Connection{} = state)

      It must also return {:ok, %Arangox.Response{}, state} or \
      {:error, %Arangox.Error{}, state}; a bare reason atom or a library exception \
      struct is no longer accepted.
      """
    end

    :ok
  end
end
