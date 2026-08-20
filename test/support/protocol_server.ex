defmodule Arangox.ProtocolServer do
  @moduledoc """
  Per-test HTTP server harness for the protocol tier.

  Starts a local, controlled server on an ephemeral port so protocol tests can
  exercise real clients against malformed responses, hangs, TLS
  (Transport Layer Security) failures and disconnects. Multiple instances can
  run concurrently (`async: true` safe): every instance gets its own port,
  listener and recorder.

  ## Usage

      {:ok, port, server} = Arangox.ProtocolServer.start()
      on_exit(fn -> Arangox.ProtocolServer.stop(server) end)

  `start/1` options:

    * `:listener` - `:cowboy` (default) for the well-formed paths, `:raw` for
      the raw-socket fault paths (see below)
    * `:tls` - `false` (default), `true`, or `:http2`. With `true` the server
      serves the harness certificate (`test/support/fixtures/localhost.pem`,
      signed by `test/support/fixtures/ca.pem`; SAN covers `DNS:localhost` and
      `IP:127.0.0.1`). `:http2` is accepted as an intent marker for tests that
      want ALPN (Application-Layer Protocol Negotiation) `h2`: it starts the
      exact same listener, because cowboy 2.x automatically advertises
      `["h2", "http/1.1"]` via ALPN on every TLS listener (verified in
      `cowboy.erl` `ensure_alpn/1` and `Plug.Cowboy.child_spec/1`), so any TLS
      instance negotiates HTTP/2 whenever the client offers it. The `:raw`
      listener also supports `tls: true` but always speaks HTTP/1.1.
    * `:tls_versions` - a list of TLS versions the listener will offer, e.g.
      `[:"tlsv1.1"]`, passed straight to `:ssl`. Omitted (the default), both
      listeners keep `:ssl`'s own defaults, which is what nearly every test
      wants. It exists for the one question that cannot be asked otherwise:
      whether a client refuses an obsolete protocol version, which needs a
      server that offers nothing else. Both listeners honour it.
    * `:redirect_to` - initial value for the `x-arango-endpoint` header served
      by `/redirect-503` (may also be set later with `set_redirect_endpoint/2`)
    * `:response_headers` - initial extra response headers for `/status/:code`
      (may also be set later with `set_response_headers/2`; names must be
      lowercase, `Plug` rejects uppercase header names)
    * `:unix` - `false` (default), `true`, or an explicit socket path. With a
      truthy value the `:cowboy` listener binds a **unix domain socket** instead
      of a TCP port, and `start/1` returns `{:ok, path, server}` with the socket
      path where it would otherwise return the port. Mutually exclusive with
      `:tls`. This is how a client's unix-socket support is exercised without a
      database.
    * `:routes` - a map of `request_path => route` consulted before every
      built-in path, so a test can serve arbitrary _ArangoDB_ paths
      (`/_admin/server/availability`, `/_api/version`, `/_admin/server/mode`,
      ...) without a database. May also be set later with `set_routes/2`.
      Header names must be lowercase. A route is one of:

        * `{status, headers, body}` - reply with exactly that
        * `:hang` - accept the request and never reply, keeping the socket
          open. This is `/hang` on an arbitrary path, which is what a test of
          the *connect pipeline* needs: the probe paths are fixed, so hanging
          has to be attached to `/_admin/server/availability` rather than to
          `/hang`.
        * `{:delay, milliseconds, route}` - sleep, then serve `route`. A
          request that outlives a client's timeout still arrives and is still
          answered, which is how "the late body is never delivered to any
          caller" becomes assertable.

  ## Paths (`:cowboy` listener)

    * `/status/:code` - replies with that status code, body `{}` (empty for
      1xx/204/304, which must not carry a body) and any headers configured via
      `set_response_headers/2`
    * `/echo` - replies 200 with a JSON object describing what arrived on the
      wire: `method`, `path`, `query`, `headers` (list of `[name, value]`
      pairs) and `body` (`body_base64` when the body is not valid UTF-8)
    * `/redirect-503` - replies 503 with an `x-arango-endpoint` header taken
      from server config (header omitted when unconfigured)
    * `/record` - replies 200 with the recorder contents as JSON. Every request
      to either listener kind is recorded (method, path, query, headers, body);
      query programmatically with `requests/1`. The `/record` request itself is
      recorded too, in arrival order.
    * `/hang` - accepts the request and never replies (also available on the
      `:raw` listener; the cowboy listener runs with `idle_timeout: :infinity`
      so cowboy never closes the hung connection itself)
    * `/trailers` - streams a chunked 200 body followed by the trailing header
      `x-protocol-server-trailer: trailer-value`. **Both** protocols emit the
      trailers only when the client sent `te: trailers`, so a test that wants
      them has to ask. Over HTTP/1.1 that is cowboy's own condition (verified
      in `cowboy_http.erl`); over HTTP/2 it is RFC 7540 8.1.2.1, enforced in
      `cow_http2_machine:send_or_queue_data/4`, which silently substitutes an
      empty end-of-stream data frame for trailers nobody requested.
    * `/early-hints` - sends an informational `103 Early Hints` response (with
      a `link` header) before the final 200
    * `/trickle` - streams a chunk every 120ms and never sends a terminating
      chunk, so a client that re-arms its budget per chunk waits forever while
      one carrying a deadline across them stops at its deadline
    * `/h2-reset` - starts a chunked 200 response, sends one chunk, then the
      handler process exits abnormally. Cowboy cannot send RST_STREAM from a
      handler on demand, but when a stream process dies after the response has
      started, `cowboy_http2` skips the 500 `error_response` (headers already
      sent) and executes the `internal_error` command, which resets the stream:
      the client observes HEADERS + DATA followed by a real
      RST_STREAM(INTERNAL_ERROR) frame. Over HTTP/1.1 the same path yields a
      connection closed mid-chunked-body (no terminating `0` chunk).

  ## Paths (`:raw` listener)

  Behaviors Plug/Cowboy cannot express, served by a minimal hand-rolled
  `:gen_tcp`/`:ssl` HTTP/1.1 responder:

    * `/hang` - reads the request, never replies, keeps the socket open
    * `/stall` - sends a 200 with `content-length: 100000`, sends a short
      partial body, then hangs with the socket open
    * `/truncate` - sends a 200 with `content-length: 100000`, sends a short
      partial body, then closes the socket
    * any other path - minimal 404, connection closed. The 404 carries the
      header `x-raw-dup` **twice** (values `one`, `two`): cowboy's
      `put_resp_header` replaces by name, so this is the one response a test
      can use to see a repeated response-header name arrive

  ## Cleanup

  Call `stop/1` (typically from `on_exit`). As a safety net each instance also
  monitors the process that started it and tears itself down when that process
  exits, so crashed tests do not leak listeners.
  """

  @enforce_keys [:kind, :tls, :port, :agent]
  defstruct [:kind, :tls, :port, :agent, :ref, :pid, :watchdog, :unix_path]

  @type t :: %__MODULE__{}

  @fixtures Path.expand("fixtures", __DIR__)

  # Lie about the body size on /stall and /truncate:
  @fault_content_length 100_000
  @fault_partial_body ~s({"partial":")

  @doc "Path to the test-only CA certificate (PEM)."
  def ca_path, do: Path.join(@fixtures, "ca.pem")

  @doc "Path to the test-only server certificate for localhost/127.0.0.1 (PEM)."
  def cert_path, do: Path.join(@fixtures, "localhost.pem")

  @doc "Path to the test-only server certificate key (PEM)."
  def key_path, do: Path.join(@fixtures, "localhost_key.pem")

  @doc """
  Starts a server instance on an ephemeral port.

  Returns `{:ok, port, server}`. See the module documentation for options.
  """
  @spec start(keyword) :: {:ok, :inet.port_number() | binary, t} | {:error, term}
  def start(opts \\ []) do
    kind = Keyword.get(opts, :listener, :cowboy)
    tls = Keyword.get(opts, :tls, false)
    tls_versions = Keyword.get(opts, :tls_versions)
    unix = unix_path(Keyword.get(opts, :unix, false))

    {:ok, agent} =
      Agent.start(fn ->
        %{
          requests: [],
          response_headers: Keyword.get(opts, :response_headers, []),
          redirect_to: Keyword.get(opts, :redirect_to),
          routes: Keyword.get(opts, :routes, %{})
        }
      end)

    result =
      case kind do
        :cowboy -> start_cowboy(agent, tls, tls_versions, unix)
        :raw -> start_raw(agent, tls, tls_versions)
      end

    case result do
      {:ok, port, ref_or_pid} ->
        server = %{build_server(kind, tls, port, agent, ref_or_pid) | unix_path: unix}
        {:ok, port, %{server | watchdog: spawn_watchdog(self(), server)}}

      {:error, reason} ->
        Agent.stop(agent)
        {:error, reason}
    end
  end

  defp unix_path(false), do: nil
  defp unix_path(nil), do: nil

  defp unix_path(true) do
    Path.join(System.tmp_dir!(), "arangox-ps-#{System.unique_integer([:positive])}.sock")
  end

  defp unix_path(path) when is_binary(path), do: path

  @doc "Stops a server instance. Idempotent."
  @spec stop(t) :: :ok
  def stop(%__MODULE__{watchdog: watchdog} = server) do
    if is_pid(watchdog), do: send(watchdog, :stop)
    teardown(server)
  end

  @doc "Returns all recorded requests, in arrival order."
  @spec requests(t) :: [map]
  def requests(%__MODULE__{agent: agent}) do
    agent |> Agent.get(& &1.requests) |> Enum.reverse()
  end

  @doc "Sets extra response headers for `/status/:code`. Names must be lowercase."
  @spec set_response_headers(t, [{binary, binary}]) :: :ok
  def set_response_headers(%__MODULE__{agent: agent}, headers) when is_list(headers) do
    Agent.update(agent, &%{&1 | response_headers: headers})
  end

  @typedoc """
  A route served by the `:cowboy` listener. See the `:routes` option.
  """
  @type route ::
          {pos_integer, [{binary, binary}], binary}
          | :hang
          | {:delay, non_neg_integer, route}

  @doc """
  Sets the explicit route table: `request_path => route`.

  Routes are consulted before every built-in path. Header names must be
  lowercase.
  """
  @spec set_routes(t, %{optional(binary) => route}) :: :ok
  def set_routes(%__MODULE__{agent: agent}, routes) when is_map(routes) do
    Agent.update(agent, &%{&1 | routes: routes})
  end

  @doc "Sets the `x-arango-endpoint` header value served by `/redirect-503`."
  @spec set_redirect_endpoint(t, binary | nil) :: :ok
  def set_redirect_endpoint(%__MODULE__{agent: agent}, endpoint) do
    Agent.update(agent, &%{&1 | redirect_to: endpoint})
  end

  @doc false
  def __record__(agent, method, path, query, headers, body) do
    entry = %{
      "method" => method,
      "path" => path,
      "query" => query,
      "headers" => Enum.map(headers, fn {name, value} -> [name, value] end),
      "body" => body
    }

    Agent.update(agent, &%{&1 | requests: [entry | &1.requests]})
  end

  @doc false
  # Read one field at a time: the state also holds every request the harness
  # has answered, and `Agent.get/2` copies whatever the function returns to
  # the calling process.
  def __config__(agent, field), do: Agent.get(agent, &Map.fetch!(&1, field))

  ## Cowboy listener

  # A client's refusal to speak an obsolete protocol version can only be
  # observed against a server that offers nothing else, and `:ssl` will not
  # negotiate one by default on any supported OTP. Naming the versions
  # explicitly is the only way to build that server; omitted, both listeners
  # keep `:ssl`'s own defaults.
  defp tls_version_opts(nil), do: []
  defp tls_version_opts(versions), do: [versions: versions]

  defp start_cowboy(agent, tls, tls_versions, unix) do
    {:ok, _} = Application.ensure_all_started(:plug_cowboy)
    ref = {__MODULE__, make_ref()}

    # A unix domain socket is bound by passing `{:local, path}` as the address
    # with port 0; ranch passes it straight to `:gen_tcp.listen/2`. A stale
    # socket file from a crashed run would make `bind` fail with `:eaddrinuse`.
    ip = if unix, do: {:local, unix}, else: {127, 0, 0, 1}
    if unix, do: File.rm(unix)

    base_opts = [
      ref: ref,
      port: 0,
      ip: ip,
      protocol_options: [idle_timeout: :infinity]
    ]

    result =
      if tls do
        {:ok, _} = Application.ensure_all_started(:ssl)

        Plug.Cowboy.https(
          __MODULE__.Handler,
          [agent: agent],
          base_opts ++
            [certfile: cert_path(), keyfile: key_path()] ++ tls_version_opts(tls_versions)
        )
      else
        Plug.Cowboy.http(__MODULE__.Handler, [agent: agent], base_opts)
      end

    case result do
      {:ok, _pid} -> {:ok, unix || :ranch.get_port(ref), ref}
      {:error, _} = error -> error
    end
  end

  ## Raw listener

  defp start_raw(agent, tls, tls_versions) do
    if tls, do: {:ok, _} = Application.ensure_all_started(:ssl)

    starter = self()
    start_ref = make_ref()

    acceptor =
      spawn(fn ->
        case raw_listen(tls, tls_versions) do
          {:ok, transport, listen_socket, port} ->
            send(starter, {start_ref, {:ok, port}})
            raw_accept_loop(transport, listen_socket, agent)

          {:error, reason} ->
            send(starter, {start_ref, {:error, reason}})
        end
      end)

    receive do
      {^start_ref, {:ok, port}} -> {:ok, port, acceptor}
      {^start_ref, {:error, reason}} -> {:error, reason}
    after
      5000 ->
        Process.exit(acceptor, :kill)
        {:error, :raw_listener_timeout}
    end
  end

  defp raw_listen(tls, tls_versions) do
    socket_opts = [
      :binary,
      packet: :http_bin,
      active: false,
      reuseaddr: true,
      ip: {127, 0, 0, 1}
    ]

    if tls do
      with {:ok, listen_socket} <-
             :ssl.listen(
               0,
               socket_opts ++
                 [certfile: cert_path(), keyfile: key_path()] ++ tls_version_opts(tls_versions)
             ),
           {:ok, {_ip, port}} <- :ssl.sockname(listen_socket) do
        {:ok, :ssl, listen_socket, port}
      end
    else
      with {:ok, listen_socket} <- :gen_tcp.listen(0, socket_opts),
           {:ok, port} <- :inet.port(listen_socket) do
        {:ok, :gen_tcp, listen_socket, port}
      end
    end
  end

  defp raw_accept_loop(:gen_tcp, listen_socket, agent) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        handler = spawn_link(fn -> raw_await_socket(:gen_tcp, agent) end)
        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, {:socket, socket})
        raw_accept_loop(:gen_tcp, listen_socket, agent)

      {:error, _reason} ->
        exit(:shutdown)
    end
  end

  defp raw_accept_loop(:ssl, listen_socket, agent) do
    case :ssl.transport_accept(listen_socket) do
      {:ok, socket} ->
        handler = spawn_link(fn -> raw_await_socket(:ssl, agent) end)
        :ok = :ssl.controlling_process(socket, handler)
        send(handler, {:socket, socket})
        raw_accept_loop(:ssl, listen_socket, agent)

      {:error, _reason} ->
        exit(:shutdown)
    end
  end

  defp raw_await_socket(transport, agent) do
    receive do
      {:socket, socket} ->
        socket =
          case transport do
            :gen_tcp ->
              socket

            :ssl ->
              case :ssl.handshake(socket, 5000) do
                {:ok, tls_socket} -> tls_socket
                {:error, _} -> exit(:normal)
              end
          end

        raw_handle(transport, socket, agent)
    after
      5000 -> exit(:normal)
    end
  end

  defp raw_handle(transport, socket, agent) do
    with {:ok, method, path} <- raw_read_request_line(transport, socket),
         {:ok, headers} <- raw_read_headers(transport, socket, []) do
      {path_only, query} =
        case String.split(path, "?", parts: 2) do
          [p] -> {p, ""}
          [p, q] -> {p, q}
        end

      __record__(agent, method, path_only, query, headers, nil)
      raw_respond(path_only, transport, socket)
    else
      _ -> transport.close(socket)
    end
  end

  defp raw_read_request_line(transport, socket) do
    case transport.recv(socket, 0, 10_000) do
      {:ok, {:http_request, method, {:abs_path, path}, _version}} ->
        {:ok, to_string(method), path}

      _other ->
        :error
    end
  end

  defp raw_read_headers(transport, socket, acc) do
    case transport.recv(socket, 0, 10_000) do
      {:ok, {:http_header, _, name, _, value}} ->
        raw_read_headers(transport, socket, [{String.downcase(to_string(name)), value} | acc])

      {:ok, :http_eoh} ->
        {:ok, Enum.reverse(acc)}

      _other ->
        :error
    end
  end

  defp raw_respond("/hang", _transport, _socket) do
    Process.sleep(:infinity)
  end

  defp raw_respond("/stall", transport, socket) do
    :ok = transport.send(socket, fault_response_head() ++ [@fault_partial_body])
    Process.sleep(:infinity)
  end

  defp raw_respond("/truncate", transport, socket) do
    :ok = transport.send(socket, fault_response_head() ++ [@fault_partial_body])
    _ = transport.shutdown(socket, :write)
    transport.close(socket)
  end

  defp raw_respond(_path, transport, socket) do
    body = ~s({"error":"unknown raw path"})

    # The duplicated x-raw-dup header is deliberate: cowboy's `put_resp_header`
    # replaces by name, so this responder is the only place a test can receive
    # a response that repeats a header name.
    :ok =
      transport.send(socket, [
        "HTTP/1.1 404 Not Found\r\n",
        "content-type: application/json\r\n",
        "x-raw-dup: one\r\n",
        "x-raw-dup: two\r\n",
        "content-length: #{byte_size(body)}\r\n",
        "connection: close\r\n\r\n",
        body
      ])

    transport.close(socket)
  end

  defp fault_response_head do
    [
      "HTTP/1.1 200 OK\r\n",
      "content-type: application/json\r\n",
      "content-length: #{@fault_content_length}\r\n\r\n"
    ]
  end

  ## Lifecycle plumbing

  defp build_server(:cowboy, tls, port, agent, ref) do
    %__MODULE__{kind: :cowboy, tls: tls, port: port, agent: agent, ref: ref}
  end

  defp build_server(:raw, tls, port, agent, pid) do
    %__MODULE__{kind: :raw, tls: tls, port: port, agent: agent, pid: pid}
  end

  defp spawn_watchdog(owner, server) do
    spawn(fn ->
      monitor_ref = Process.monitor(owner)

      receive do
        :stop -> :ok
        {:DOWN, ^monitor_ref, :process, _, _} -> teardown(server)
      end
    end)
  end

  defp teardown(%__MODULE__{kind: :cowboy, ref: ref, agent: agent, unix_path: unix}) do
    _ = Plug.Cowboy.shutdown(ref)
    if unix, do: File.rm(unix)
    stop_agent(agent)
  end

  defp teardown(%__MODULE__{kind: :raw, pid: pid, agent: agent}) do
    Process.exit(pid, :kill)
    stop_agent(agent)
  end

  defp stop_agent(agent) do
    Agent.stop(agent)
    :ok
  catch
    :exit, _ -> :ok
  end
end

defmodule Arangox.ProtocolServer.Handler do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias Arangox.ProtocolServer

  @bodyless_statuses [204, 304]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    agent = Keyword.fetch!(opts, :agent)
    {conn, body} = read_full_body(conn)

    ProtocolServer.__record__(
      agent,
      conn.method,
      conn.request_path,
      conn.query_string,
      conn.req_headers,
      body
    )

    case Map.fetch(ProtocolServer.__config__(agent, :routes), conn.request_path) do
      {:ok, route} -> serve_route(conn, route)
      :error -> dispatch(conn.path_info, conn, body, agent)
    end
  end

  defp serve_route(_conn, :hang), do: Process.sleep(:infinity)

  defp serve_route(conn, {:delay, milliseconds, route}) do
    Process.sleep(milliseconds)
    serve_route(conn, route)
  end

  defp serve_route(conn, {status, headers, body}) do
    conn
    |> then(fn c ->
      Enum.reduce(headers, c, fn {name, value}, acc -> put_resp_header(acc, name, value) end)
    end)
    |> send_resp(status, body)
  end

  defp dispatch(["status", code], conn, _body, agent) do
    status = String.to_integer(code)

    conn =
      Enum.reduce(ProtocolServer.__config__(agent, :response_headers), conn, fn {name, value},
                                                                                c ->
        put_resp_header(c, name, value)
      end)

    if status in @bodyless_statuses or status in 100..199 do
      send_resp(conn, status, "")
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, "{}")
    end
  end

  defp dispatch(["echo"], conn, body, _agent) do
    payload = %{
      "method" => conn.method,
      "path" => conn.request_path,
      "query" => conn.query_string,
      "headers" => Enum.map(conn.req_headers, fn {name, value} -> [name, value] end)
    }

    payload =
      if String.valid?(body) do
        Map.put(payload, "body", body)
      else
        Map.put(payload, "body_base64", Base.encode64(body))
      end

    json(conn, 200, payload)
  end

  defp dispatch(["redirect-503"], conn, _body, agent) do
    conn =
      case ProtocolServer.__config__(agent, :redirect_to) do
        nil -> conn
        endpoint -> put_resp_header(conn, "x-arango-endpoint", endpoint)
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(503, "{}")
  end

  defp dispatch(["record"], conn, _body, agent) do
    requests = agent |> Agent.get(& &1.requests) |> Enum.reverse()
    json(conn, 200, requests)
  end

  defp dispatch(["hang"], _conn, _body, _agent) do
    Process.sleep(:infinity)
  end

  defp dispatch(["trailers"], conn, _body, _agent) do
    # Plug has no trailer API; drop to the cowboy request underneath. Over
    # HTTP/1.1 cowboy only sends the trailers when the client sent
    # "te: trailers"; over HTTP/2 they are always sent.
    {Plug.Cowboy.Conn, req} = conn.adapter

    req =
      :cowboy_req.stream_reply(
        200,
        %{"content-type" => "text/plain", "trailer" => "x-protocol-server-trailer"},
        req
      )

    :ok = :cowboy_req.stream_body("body-before-trailers", :nofin, req)
    :ok = :cowboy_req.stream_trailers(%{"x-protocol-server-trailer" => "trailer-value"}, req)

    %{conn | adapter: {Plug.Cowboy.Conn, req}, state: :sent, status: 200}
  end

  defp dispatch(["early-hints"], conn, _body, _agent) do
    conn
    |> inform(103, [{"link", "</assets/app.css>; rel=preload; as=style"}])
    |> put_resp_content_type("application/json")
    |> send_resp(200, "{}")
  end

  defp dispatch(["h2-reset"], conn, _body, _agent) do
    # Start the response, then die. Because the response has started, cowboy
    # cannot send its 500 error_response and instead executes the
    # internal_error command: over HTTP/2 that is a genuine
    # RST_STREAM(INTERNAL_ERROR) frame mid-stream; over HTTP/1.1 the
    # connection is closed mid-chunked-body. exit(:shutdown) keeps
    # cowboy_stream_h from logging a crash report.
    conn = conn |> put_resp_content_type("text/plain") |> send_chunked(200)
    {:ok, _conn} = chunk(conn, "partial-before-reset")
    exit(:shutdown)
  end

  # Streams a chunk every 120 ms and never finishes. A client that re-arms its
  # whole remaining budget per chunk never gives up here; one that carries a
  # deadline across the chunks stops at its deadline.
  defp dispatch(["trickle"], conn, _body, _agent) do
    conn = conn |> put_resp_content_type("application/json") |> send_chunked(200)
    trickle(conn, 200)
  end

  defp dispatch(["stall"], conn, _body, _agent), do: raw_only(conn, "/stall")
  defp dispatch(["truncate"], conn, _body, _agent), do: raw_only(conn, "/truncate")

  defp dispatch(_path, conn, _body, _agent) do
    json(conn, 404, %{"error" => "unknown path"})
  end

  defp trickle(conn, 0), do: conn

  defp trickle(conn, remaining) do
    Process.sleep(120)

    case chunk(conn, "x") do
      {:ok, conn} -> trickle(conn, remaining - 1)
      {:error, _closed} -> conn
    end
  end

  defp raw_only(conn, path) do
    json(conn, 501, %{"error" => "#{path} requires start(listener: :raw)"})
  end

  defp json(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp read_full_body(conn, acc \\ "") do
    case read_body(conn) do
      {:ok, body, conn} -> {conn, acc <> body}
      {:more, part, conn} -> read_full_body(conn, acc <> part)
    end
  end
end
