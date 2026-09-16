defmodule Arangox.ProtocolTest do
  @moduledoc """
  Request timeouts.

  Protocol tier: real clients over real sockets against
  `Arangox.ProtocolServer` on an ephemeral local port, plus a bare `:gen_tcp`
  listener for the VelocyStream cases (a `Plug` harness cannot speak
  VelocyStream, but `Arangox.VelocyClient.connect/2` never reads, so a socket
  that accepts and stays silent is enough to exercise the receive bound). No
  Docker.

  `async: false`: several tests count VM ports, which is global state, and
  several assert on wall-clock ordering that a saturated scheduler would blur.

  The scenario that distinguishes a *deadline* from a *duration* is
  "a caller that queued out most of its budget" below. Every other test here
  passes under both the correct and the incorrect derivation; see
  `docs/solutions/architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md`.
  """

  use ExUnit.Case, async: false

  import TestHelper, only: [stop_pool: 1]

  alias Arangox.{
    Client,
    Connection,
    Endpoint,
    Error,
    GunClient,
    MintClient,
    ProtocolServer,
    Query,
    Request,
    Response,
    VelocyClient
  }

  doctest Arangox.Client, only: [validate_request_timeout: 1]

  @availability "/_admin/server/availability"
  @version "/_api/version"
  @json [{"content-type", "application/json"}]
  @ok_body ~s({"error":false,"code":200})
  @version_body ~s({"server":"arango","license":"community","version":"3.12.5"})

  ## Helpers

  # Routes for a server that passes every connect probe, plus whatever the test
  # needs on top.
  defp routes(extra) do
    Map.merge(
      %{
        @availability => {200, @json, @ok_body},
        @version => {200, @json, @version_body},
        "/fast" => {200, @json, ~s({"marker":"fresh"})}
      },
      extra
    )
  end

  defp start_server!(extra \\ %{}) do
    {:ok, port, server} = ProtocolServer.start(routes: routes(extra))
    on_exit(fn -> ProtocolServer.stop(server) end)
    {port, "http://127.0.0.1:#{port}", server}
  end

  defp start_pool!(url, opts) do
    {:ok, pool} =
      Arangox.start_link(
        Keyword.merge(
          [
            endpoints: [url],
            client: MintClient,
            pool_size: 1,
            backoff_min: 10,
            backoff_max: 20,
            show_sensitive_data_on_connection_error: true
          ],
          opts
        )
      )

    on_exit(fn -> stop_pool(pool) end)
    pool
  end

  defp state_for(client, socket, fields) do
    struct(Connection, [socket: socket, client: client] ++ fields)
  end

  defp timed(fun) do
    {microseconds, result} = :timer.tc(fun)
    {div(microseconds, 1000), result}
  end

  # Client-side sockets currently connected to `port_number`. The harness's own
  # accepted sockets are excluded: their peer is the client's ephemeral port,
  # not the listen port.
  defp sockets_to(port_number) do
    Enum.filter(Port.list(), fn port ->
      with ~c"tcp_inet" <- port_name(port),
           {:ok, {_ip, ^port_number}} <- :inet.peername(port) do
        true
      else
        _other -> false
      end
    end)
  end

  defp port_name(port) do
    case :erlang.port_info(port, :name) do
      {:name, name} -> name
      _other -> nil
    end
  end

  # A local TCP listener that accepts and then says nothing at all. This is the
  # VelocyStream analogue of the harness's `/hang`.
  defp silent_listener! do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)

    acceptor =
      spawn(fn ->
        {:ok, _socket} = :gen_tcp.accept(listen)
        Process.sleep(:infinity)
      end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listen)
    end)

    port
  end

  describe "header passthrough (0.8 list semantics)" do
    # End-to-end through a real pool: pool and request headers both reach the
    # server. Mint lowercases header *names* on the wire — that is the
    # client's documented business — so the assertion compares lowercased
    # names. The receiving end here is cowboy, which parses request headers
    # into a *map*, losing order and duplicates — the same thing any server is
    # free to do — so this test pins presence only; order and duplicates are
    # pinned below against the raw listener, which records the header lines as
    # they arrived.
    test "pool and request headers both reach the server" do
      {_port, url, _server} = start_server!()

      pool = start_pool!(url, headers: [{"X-Pool", "p"}, {"x-order", "pool"}])

      assert {:ok, %Response{status: 200, body: body}} =
               Arangox.get(pool, "/echo", [{"x-request", "req"}])

      arrived = for [name, value] <- body["headers"], do: {String.downcase(name), value}

      assert {"x-pool", "p"} in arrived, "the pool header never reached the wire"
      assert {"x-order", "pool"} in arrived, "the pool's second header never reached the wire"
      assert {"x-request", "req"} in arrived, "the request header never reached the wire"
    end

    # The response direction of the same contract: headers come back as a
    # list of `{name, value}` tuples, never a map. Both HTTP clients lowercase
    # the names; membership is the pin because the server interleaves its own
    # headers (date, server) with the configured ones.
    for {client, connect} <- [
          {MintClient, &MintClient.connect/2},
          {GunClient, &GunClient.connect/2}
        ] do
      @client client
      @connect connect

      test "#{inspect(client)} returns response headers as a list of tuples" do
        {:ok, port, server} = ProtocolServer.start()
        on_exit(fn -> ProtocolServer.stop(server) end)
        ProtocolServer.set_response_headers(server, [{"x-resp-a", "1"}, {"x-resp-b", "2"}])

        assert {:ok, socket} = @connect.(Endpoint.new("http://127.0.0.1:#{port}"), [])
        state = state_for(@client, socket, request_timeout: 5_000)

        assert {:ok, %Response{status: 200, headers: headers}, %Connection{}} =
                 @client.request(%Request{method: :get, path: "/status/200"}, [], state)

        assert is_list(headers)

        assert Enum.all?(headers, fn
                 {name, value} -> is_binary(name) and is_binary(value)
                 _other -> false
               end)

        assert {"x-resp-a", "1"} in headers
        assert {"x-resp-b", "2"} in headers
      end
    end

    # A response that repeats a name must deliver every occurrence — the raw
    # listener's 404 carries a fixed duplicated header for exactly this
    # question, since cowboy's `put_resp_header` replaces by name.
    test "duplicate response headers survive as separate entries" do
      {:ok, port, server} = ProtocolServer.start(listener: :raw)
      on_exit(fn -> ProtocolServer.stop(server) end)

      {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = struct(Connection, socket: socket, client: MintClient)

      assert {:ok, %Response{status: 404, headers: headers}, %Connection{}} =
               MintClient.request(%Request{method: :get, path: "/any"}, [], state)

      dups = for {"x-raw-dup", value} <- headers, do: value
      assert dups == ["one", "two"]
    end

    # The driver's own promise ends at the socket: header lines leave in list
    # order, duplicates included. What a server does with them afterwards is
    # its own policy (cowboy above keeps one; ArangoDB applies whatever rule
    # it has). The raw listener records the lines as they arrived.
    test "header lines leave in list order, duplicates intact" do
      {:ok, port, server} = ProtocolServer.start(listener: :raw)
      on_exit(fn -> ProtocolServer.stop(server) end)

      {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = struct(Connection, socket: socket, client: MintClient)

      request = %Request{
        method: :get,
        path: "/any",
        headers: [{"x-a", "1"}, {"x-dup", "one"}, {"x-b", "2"}, {"x-dup", "two"}]
      }

      assert {:ok, %Response{status: 404}, %Connection{}} =
               MintClient.request(request, [], state)

      assert [%{"headers" => headers}] = ProtocolServer.requests(server)

      sent = for [name, value] <- headers, String.starts_with?(name, "x-"), do: {name, value}
      assert sent == [{"x-a", "1"}, {"x-dup", "one"}, {"x-b", "2"}, {"x-dup", "two"}]
    end
  end

  ## TLS trust

  # Not a test that Mint and `:ssl` verify certificates — that is theirs, and
  # covered where they live. These pin the driver's part: it adds no TLS
  # defaults, removes none, and passes the caller's options through intact. An
  # unconditional, undocumented `verify: :verify_none` fails every one of
  # them.
  #
  # The harness certificate is signed by the harness authority, which nothing
  # trusts, so it stands in for a database's self-signed certificate.
  describe "transport options reach the transport" do
    defp tls_url(port), do: "https://localhost:#{port}"

    defp tls_server!(opts \\ []) do
      {:ok, port, server} = ProtocolServer.start([tls: true, routes: routes(%{})] ++ opts)
      on_exit(fn -> ProtocolServer.stop(server) end)
      port
    end

    defp tls_connect(client, port, opts) do
      {:ok, endpoint} = Endpoint.parse(tls_url(port))
      client.connect(endpoint, opts)
    end

    test "no override re-enables an untrusted certificate" do
      port = tls_server!()

      assert {:error, %Error{reason: :tls_alert}} = tls_connect(MintClient, port, [])
    end

    test "the documented opt-out reaches the socket" do
      port = tls_server!()

      assert {:ok, _conn} = tls_connect(MintClient, port, ssl_opts: [verify: :verify_none])
    end

    test "a caller-supplied authority reaches the socket" do
      port = tls_server!()

      assert {:ok, _conn} =
               tls_connect(MintClient, port, ssl_opts: [cacertfile: ProtocolServer.ca_path()])
    end

    # Guards the regression where one unrelated transport option replaced the
    # whole list, carrying the trust configuration out with it.
    test "an unrelated transport option leaves verification in place" do
      port = tls_server!()

      assert {:error, %Error{reason: :tls_alert}} =
               tls_connect(MintClient, port, ssl_opts: [depth: 5])
    end

    # Guards the regression where `:client_opts` replaced `:transport_opts`
    # outright, discarding everything under `:ssl_opts` — trust material
    # included. Merged per key the authority survives the `depth` beside it.
    test "client_opts merges into transport options rather than replacing them" do
      port = tls_server!()

      assert {:ok, _conn} =
               tls_connect(MintClient, port,
                 ssl_opts: [cacertfile: ProtocolServer.ca_path()],
                 client_opts: [transport_opts: [depth: 5]]
               )
    end

    # Same question of the other client: it adds nothing and removes nothing,
    # so `:ssl`'s own default is what applies.
    test "the VelocyStream client adds no default of its own either" do
      port = tls_server!()

      assert {:error, %Error{}} = tls_connect(VelocyClient, port, [])
    end

    # `:ssl` and Mint already floor at TLS 1.2, so what these pin is that the
    # driver does not lower it — an `ssl_opts` merge dropping `versions`, or a
    # blanket override in the shape of `verify: :verify_none`, would.
    #
    # The harness authority is supplied so these fail on the protocol version
    # rather than on trust, which the tests above cover.
    test "a server offering only TLS 1.1 is refused" do
      port = tls_server!(tls_versions: [:"tlsv1.1"])

      assert {:error, %Error{reason: :tls_alert}} =
               tls_connect(MintClient, port, ssl_opts: [cacertfile: ProtocolServer.ca_path()])
    end

    # Assert the reason, not just the error: every connect failure is an
    # `Arangox.Error`, so a bare `%Error{}` also matches a cipher mismatch, a
    # name mismatch or a closed socket.
    test "the VelocyStream client refuses TLS 1.1 too" do
      port = tls_server!(tls_versions: [:"tlsv1.1"])

      assert {:error, %Error{reason: :tls_alert}} =
               tls_connect(VelocyClient, port, ssl_opts: [cacertfile: ProtocolServer.ca_path()])
    end

    # Keeps the two tests above from passing vacuously: without this, a
    # listener that stopped constraining its versions would still leave them
    # green whenever the handshake failed for any other reason.
    test "the TLS 1.1 listener is genuinely serving TLS 1.1" do
      port = tls_server!(tls_versions: [:"tlsv1.1"])

      assert {:ok, socket} =
               :ssl.connect(
                 ~c"localhost",
                 port,
                 [
                   :binary,
                   active: false,
                   versions: [:"tlsv1.1"],
                   cacertfile: String.to_charlist(ProtocolServer.ca_path())
                 ],
                 5_000
               )

      :ok = :ssl.close(socket)
    end
  end

  ## The connect callback returns instead of raising

  # `Arangox.Connection.connect/1` is a `DBConnection` callback, and an
  # exception escaping it is not a failed connection: it crashes the connection
  # process, and DBConnection's own sanitizer reports the crash by advising that
  # sensitive-data logging be turned on to see what happened. Both clients
  # rescue for that reason and return an `Arangox.Error` instead. Nothing
  # asserted it until now -- `client_error` appeared in no test.
  #
  # Both triggers below are ordinary mistakes rather than contrived ones, which
  # matters because an unreachable rescue is untestable and an untested rescue
  # is the one that stops working.
  describe "connect returns instead of raising" do
    # This client documents `client_opts: [protocols: [:http2]]`, and `h2` is
    # what the very same protocol is called on the wire and in ALPN. Writing it
    # that way is the obvious slip, and `Mint.HTTP.connect/4` raises a
    # `CaseClauseError` on it rather than returning anything.
    test "a client option the library raises on becomes an error" do
      {_port, url, _server} = start_server!()

      assert {:error, %Error{reason: :client_error}} =
               MintClient.connect(Endpoint.new(url), client_opts: [protocols: [:h2]])
    end

    # Transport options are documented as a keyword list. Handing them over as a
    # map instead reaches `Keyword.merge/2`, which raises rather than returning.
    test "transport options of the wrong shape become an error" do
      {_port, url, _server} = start_server!()

      assert {:error, %Error{reason: :client_error}} =
               VelocyClient.connect(Endpoint.new(url), tcp_opts: %{nodelay: true})
    end
  end

  ## HTTP/2

  # ALPN settles the protocol during the TLS handshake: the client offers a
  # list, the server picks. A client pinned to `Mint.HTTP1` gets HTTP/1.1
  # whatever the server offers, which is the regression these guard.
  #
  # The assembler has to read both shapes. HTTP/2 can end one request without
  # ending the connection — a stream reset — which has no HTTP/1.1 equivalent.
  describe "protocol negotiation" do
    defp h2_server!(extra \\ %{}) do
      {:ok, port, server} = ProtocolServer.start(tls: :http2, routes: routes(extra))
      on_exit(fn -> ProtocolServer.stop(server) end)
      port
    end

    # The harness authority is supplied so these tests fail on the protocol
    # question rather than on trust, which the block above already covers.
    # HTTP/2 is opt-in on both schemes, so every test in this block asks for it
    # by name — on TLS the offer is settled by ALPN.
    defp h2_connect!(port, opts \\ []) do
      {:ok, endpoint} = Endpoint.parse(tls_url(port))

      defaults = [
        ssl_opts: [cacertfile: ProtocolServer.ca_path()],
        client_opts: [protocols: [:http2]]
      ]

      assert {:ok, socket} = MintClient.connect(endpoint, Keyword.merge(defaults, opts))

      socket
    end

    defp h2_state!(port, opts \\ []) do
      state_for(MintClient, h2_connect!(port, opts), request_timeout: 5_000)
    end

    test "a TLS endpoint negotiates HTTP/2 and a request round-trips" do
      port = h2_server!()
      socket = h2_connect!(port)

      assert Mint.HTTP.protocol(socket) == :http2

      state = state_for(MintClient, socket, request_timeout: 5_000)

      assert {:ok, %Response{status: 200, body: body}, %Connection{}} =
               MintClient.request(%Request{method: :get, path: @version}, [], state)

      assert body =~ "arango"
    end

    # HTTP/2 is opt-in on both schemes: a request body is sent whole, and
    # HTTP/2 refuses one above the peer's window. See `Arangox.MintClient`.
    test "a cleartext endpoint stays HTTP/1.1" do
      {_port, url, _server} = start_server!()

      assert {:ok, socket} = MintClient.connect(Endpoint.new(url), [])
      assert Mint.HTTP.protocol(socket) == :http1
    end

    test "a TLS endpoint stays HTTP/1.1 unless HTTP/2 is asked for" do
      port = tls_server!()
      {:ok, endpoint} = Endpoint.parse(tls_url(port))

      assert {:ok, socket} =
               MintClient.connect(endpoint, ssl_opts: [cacertfile: ProtocolServer.ca_path()])

      assert Mint.HTTP.protocol(socket) == :http1
    end

    test "HTTP/2 is reachable through client options" do
      {_port, url, _server} = start_server!()

      assert {:ok, socket} =
               MintClient.connect(Endpoint.new(url), client_opts: [protocols: [:http2]])

      assert Mint.HTTP.protocol(socket) == :http2
    end

    # A request body is sent whole rather than streamed, and HTTP/2
    # flow-controls request bodies: one larger than the peer's window is
    # refused outright instead of waiting for a `WINDOW_UPDATE`. Servers
    # commonly advertise 64 KiB, so bulk inserts and large documents sit above
    # it. HTTP/1.1 has no flow control, which is what makes the cleartext
    # default carry them.
    @body_over_h2_window 100_000

    test "the default cleartext pool carries a body larger than an HTTP/2 window" do
      {_port, url, _server} = start_server!()
      pool = start_pool!(url, [])

      body = %{"blob" => String.duplicate("x", @body_over_h2_window)}

      assert {:ok, %Response{status: 200}} = Arangox.post(pool, "/echo", body)
    end

    # The limitation itself, pinned so it is a known bound rather than a
    # surprise. Streaming the body in window-sized chunks is what removes it;
    # this test is the one to flip when that lands.
    test "an HTTP/2 connection refuses a body larger than the window" do
      port = h2_server!()
      state = h2_state!(port)

      request = %Request{
        method: :post,
        path: "/echo",
        body: String.duplicate("x", @body_over_h2_window)
      }

      assert {:error, %Error{reason: :exceeds_window_size}, %Connection{}} =
               MintClient.request(request, [], state)
    end

    # A server announcing shutdown (GOAWAY) leaves an HTTP/2 connection
    # write-closed while its socket stays open through the drain window. The
    # error a later request gets must carry a reason the pool retires on:
    # `:closed_for_writing` is not one, and a connection kept on it fails
    # every request drawn from the pool afterwards.
    test "a connection the server told to go away is retired rather than reused" do
      {:ok, port, server} = ProtocolServer.start(tls: :http2, routes: routes(%{}))
      on_exit(fn -> ProtocolServer.stop(server) end)

      state = h2_state!(port)

      assert {:ok, %Response{status: 200}, state} =
               MintClient.request(%Request{method: :get, path: @version}, [], state)

      # `stop/1` blocks until the listener has drained, so it runs from a task
      # while this process keeps using the connection inside the drain window:
      # cowboy has sent GOAWAY but still serves streams and holds the socket
      # open (`goaway_initial_timeout`).
      Task.start(fn -> ProtocolServer.stop(server) end)
      Process.sleep(150)

      # Served during the drain; reading its response also reads the GOAWAY
      # that precedes it on the wire.
      assert {:ok, %Response{status: 200}, state} =
               MintClient.request(%Request{method: :get, path: @version}, [], state)

      assert {:error, %Error{} = error, %Connection{}} =
               MintClient.request(%Request{method: :get, path: @version}, [], state)

      assert Client.connection_lost?(error),
             "reason #{inspect(error.reason)} does not retire a write-closed connection"
    end

    # Headers can arrive after the body. Both protocols send them only when the
    # request asked with `te: trailers`; over HTTP/2 that is RFC 7540 8.1.2.1,
    # which cowlib enforces by substituting an empty end-of-stream data frame.
    # However they were asked for, they are part of the response and belong in
    # it.
    test "trailing headers after the body reach the response" do
      port = h2_server!()
      state = h2_state!(port)

      request = %Request{method: :get, path: "/trailers", headers: [{"te", "trailers"}]}

      assert {:ok, %Response{status: 200, headers: headers, body: body}, %Connection{}} =
               MintClient.request(request, [], state)

      assert body == "body-before-trailers"
      assert {"x-protocol-server-trailer", "trailer-value"} in headers
    end

    # `103 Early Hints` is a complete status-and-headers pair that is not the
    # response; the real one follows on the same stream.
    test "an informational response is superseded by the real one" do
      port = h2_server!()
      state = h2_state!(port)

      assert {:ok, %Response{status: 200}, %Connection{}} =
               MintClient.request(%Request{method: :get, path: "/early-hints"}, [], state)
    end

    # The server abandons one stream and leaves the connection up. Waiting for
    # a completion the protocol already cancelled spends the caller's whole
    # budget and then reports the wrong reason.
    test "a stream-level error is reported as itself, not as a timeout" do
      port = h2_server!()
      state = h2_state!(port)

      {elapsed, result} =
        timed(fn -> MintClient.request(%Request{method: :get, path: "/h2-reset"}, [], state) end)

      assert {:error, %Error{reason: :server_closed_request}, %Connection{}} = result

      assert elapsed < 1_000,
             "a reset stream was waited out instead of reported, took #{elapsed}ms"
    end
  end

  ## The Gun client

  # This block covers for Gun the same questions the Mint blocks cover:
  # the negotiated protocol, the request-budget bound, and what a failure may
  # carry. `:gun.info/1` reports the connection's negotiated protocol. The
  # rejected-transport-option and connection-lost scenarios run in
  # `Arangox.ClientContractTest`, which covers every shipped client.
  describe "gun client" do
    # No `protocols` option here: the driver passes none, so this pins gun's
    # own TLS default — offer HTTP/2 and HTTP/1.1 via ALPN, prefer HTTP/2.
    test "a TLS endpoint negotiates HTTP/2 by default and a request round-trips" do
      port = h2_server!()

      {:ok, endpoint} = Endpoint.parse(tls_url(port))

      assert {:ok, pid} =
               GunClient.connect(endpoint, ssl_opts: [cacertfile: ProtocolServer.ca_path()])

      assert %{protocol: :http2} = :gun.info(pid)

      state = state_for(GunClient, pid, request_timeout: 5_000)

      assert {:ok, %Response{status: 200, body: body}, %Connection{}} =
               GunClient.request(%Request{method: :get, path: @version}, [], state)

      assert body =~ "arango"
    end

    test "a cleartext endpoint stays HTTP/1.1" do
      {_port, url, _server} = start_server!()

      assert {:ok, pid} = GunClient.connect(Endpoint.new(url), [])
      assert %{protocol: :http} = :gun.info(pid)
    end

    test "client options cannot downgrade a TLS endpoint to cleartext" do
      port = tls_server!()

      assert {:ok, pid} =
               GunClient.connect(Endpoint.new(tls_url(port)),
                 ssl_opts: [cacertfile: ProtocolServer.ca_path()],
                 client_opts: %{transport: :tcp}
               )

      assert %{transport: :tls} = :gun.info(pid)
    end

    # `/stall` sends the response line and headers, sends part of the body,
    # then hangs — so the budget has to cover the body, not just the first
    # await.
    test "a request whose budget elapses mid-response reports :timeout" do
      {:ok, port, server} = ProtocolServer.start(listener: :raw)
      on_exit(fn -> ProtocolServer.stop(server) end)

      {:ok, pid} = GunClient.connect(Endpoint.new("http://localhost:#{port}"), [])

      state = state_for(GunClient, pid, request_timeout: 300)

      {elapsed, result} =
        timed(fn -> GunClient.request(%Request{method: :get, path: "/stall"}, [], state) end)

      assert {:error, %Error{reason: :timeout}, %Connection{}} = result

      assert elapsed < 1_000,
             "a stalled response was waited out instead of bounded, took #{elapsed}ms"
    end

    test "a pool on this client completes a request" do
      {_port, url, _server} = start_server!()
      pool = start_pool!(url, client: GunClient)

      assert %Response{status: 200} = Arangox.get!(pool, "/fast")
    end

    # Gun reports a 1xx as its own `{:inform, status, headers}` before the
    # real response arrives on the same stream.
    test "an informational response is superseded by the real one" do
      {_port, url, _server} = start_server!()

      {:ok, pid} = GunClient.connect(Endpoint.new(url), [])
      state = state_for(GunClient, pid, request_timeout: 5_000)

      assert {:ok, %Response{status: 200}, %Connection{}} =
               GunClient.request(%Request{method: :get, path: "/early-hints"}, [], state)
    end

    # Gun validates header values in the calling process and raises with
    # the header *name* only; the rescue in `request/3` turns that raise into
    # an error return. What must hold whatever gun does: the value — a
    # credential — appears nowhere in what comes back.
    test "an invalid header value never reaches an error message" do
      {_port, url, _server} = start_server!()

      {:ok, pid} = GunClient.connect(Endpoint.new(url), [])
      state = state_for(GunClient, pid, request_timeout: 1_000)

      request = %Request{
        method: :get,
        path: "/fast",
        headers: [{"authorization", "Bearer topsecret\r\nx: y"}]
      }

      assert {:error, %Error{} = error, %Connection{}} = GunClient.request(request, [], state)

      refute error.message =~ "topsecret"
      refute Exception.message(error) =~ "topsecret"
    end
  end

  ## A drain that runs out of budget

  # `Arangox.query/4` drains a multi-batch result inside one request budget, so
  # a slow server can exhaust that budget in either of two ways, and they need
  # opposite handling.
  #
  # A wait that actually expires leaves an unread reply on the socket: retire
  # the connection or the next caller reads this caller's response. A budget
  # spent *before* a request is written leaves the socket untouched, so retiring
  # it would destroy a healthy connection over a caller's clock. That second
  # branch is covered by "a deadline that has already elapsed fails fast"
  # below — it is not drain-specific, and reproducing it precisely between two
  # batches means hitting a 25ms window, which is a race rather than a test.
  #
  # What is drain-specific, and untested until now, is the first: a drain makes
  # more than one request under one deadline, so it is the only path where a
  # request can expire with earlier batches already delivered.
  describe "a drain that outlives its deadline" do
    @cursor_body ~s({"id":"c1","hasMore":true,"result":[1],"error":false,"code":201})
    @last_batch ~s({"hasMore":false,"result":[2],"error":false,"code":200})

    defp drain_state!(url) do
      assert {:ok, %Connection{} = state} =
               Connection.connect(endpoints: [url], client: MintClient, request_timeout: 10_000)

      state
    end

    defp drain(state, budget) do
      Connection.handle_execute(
        %Query{query: "FOR i IN 1..2 RETURN i"},
        %{},
        [deadline: Client.monotonic_ms() + budget],
        state
      )
    end

    # The second batch is written and its response never arrives in time. The
    # socket now has a reply on it that nobody read.
    test "a wait that expires mid-batch retires the connection" do
      {_port, url, server} =
        start_server!(%{
          "/_api/cursor" => {201, @json, @cursor_body},
          "/_api/cursor/c1" => {:delay, 900, {200, @json, @last_batch}}
        })

      state = drain_state!(url)

      assert {:disconnect, %Error{reason: :timeout}, %Connection{}} = drain(state, 500)

      paths = for r <- ProtocolServer.requests(server), do: {r["method"], r["path"]}
      assert {"PUT", "/_api/cursor/c1"} in paths
      refute {"DELETE", "/_api/cursor/c1"} in paths

      Connection.disconnect(:normal, state)
    end

    # Neither path deletes the abandoned cursor, and neither should. One has no
    # connection left to send on; the other has no budget left to spend, and
    # spending it would be the driver overrunning the deadline the caller set.
    # The server's cursor TTL is what collects it.
    test "a drain that fits its budget still returns every row" do
      {_port, url, _server} =
        start_server!(%{
          "/_api/cursor" => {201, @json, @cursor_body},
          "/_api/cursor/c1" => {200, @json, @last_batch}
        })

      state = drain_state!(url)

      assert {:ok, %Query{}, %Response{body: %{"result" => [1, 2]}}, %Connection{}} =
               drain(state, 5_000)

      Connection.disconnect(:normal, state)
    end
  end

  ## Connect-time hangs

  describe "connect pipeline" do
    test "a probe that never responds does not wedge connect/1, and leaks no socket" do
      {port, url, _server} = start_server!(%{@availability => :hang})

      # A single binary endpoint rather than a list: failover collapses every
      # rejection into "all endpoints are unavailable", and the reason the probe
      # gave up is exactly what this test is about.
      task =
        Task.async(fn ->
          Connection.connect(
            endpoints: url,
            client: MintClient,
            connect_timeout: 300,
            show_sensitive_data_on_connection_error: true
          )
        end)

      result = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)

      assert {:ok, {:error, %Error{} = error}} = result,
             "connect/1 did not return within 5s against a server that never responds to a probe"

      assert error.reason == :timeout,
             "expected the probe to time out, got #{inspect(error.reason)}"

      assert Client.connection_lost?(error),
             "expected a socket-gone reason, got #{inspect(error.reason)}"

      assert sockets_to(port) == [],
             "a wedged connect probe left its socket open"
    end

    test "the probe stages share one :connect_timeout rather than being given one each" do
      {_port, url, _server} =
        start_server!(%{
          @availability => {:delay, 400, {200, @json, @ok_body}},
          @version => {:delay, 400, {200, @json, @version_body}}
        })

      {elapsed, result} =
        timed(fn ->
          Connection.connect(
            endpoints: url,
            client: MintClient,
            connect_timeout: 600,
            show_sensitive_data_on_connection_error: true
          )
        end)

      # Each probe responds inside 600ms on its own, so a budget stamped fresh
      # per stage admits both and the handshake runs for ~800ms — and every
      # stage added later would extend that by another 600ms. One budget for
      # the whole handshake does not: the availability probe spends 400ms of
      # the 600, and the version probe gets what is left of it.
      assert {:error, %Error{reason: :timeout}} = result

      assert elapsed < 750,
             "the handshake took #{elapsed}ms, so the probes were budgeted per stage " <>
               "rather than sharing one :connect_timeout"
    end

    test "failover gives each endpoint its own probe budget" do
      {_port_a, url_a, _server_a} =
        start_server!(%{
          @availability => {:delay, 400, {200, @json, @ok_body}},
          @version => {:delay, 400, {200, @json, @version_body}}
        })

      {_port_b, url_b, _server_b} =
        start_server!(%{@availability => {:delay, 400, {200, @json, @ok_body}}})

      # The first endpoint spends its whole budget and is rejected; the second
      # is slow but fits inside a budget of its own. A single budget spanning
      # the walk would leave nothing for it and report "all endpoints are
      # unavailable" instead.
      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [url_a, url_b],
                 client: MintClient,
                 connect_timeout: 600,
                 show_sensitive_data_on_connection_error: true
               )

      assert state.endpoint == url_b,
             "expected the walk to move past the endpoint that spent its budget"

      Connection.disconnect(:normal, state)
    end

    test "connect_timeout: :infinity falls the probes back to :request_timeout" do
      {port, url, _server} = start_server!(%{@availability => :hang})

      task =
        Task.async(fn ->
          Connection.connect(
            endpoints: url,
            client: MintClient,
            connect_timeout: :infinity,
            request_timeout: 300,
            show_sensitive_data_on_connection_error: true
          )
        end)

      result = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)

      assert {:ok, {:error, %Error{reason: :timeout}}} = result,
             "an unbounded :connect_timeout left the probes unbounded too"

      assert sockets_to(port) == [],
             "a wedged connect probe left its socket open"
    end
  end

  ## A request that gets no response

  describe "a server that accepts a request and never responds" do
    test "errors within the request timeout, disconnects, and the next request is served fresh" do
      {_port, url, server} =
        start_server!(%{
          "/slow" => {:delay, 800, {200, @json, ~s({"marker":"delayed"})}}
        })

      pool = start_pool!(url, request_timeout: 200)

      {elapsed, result} = timed(fn -> Arangox.get(pool, "/slow") end)

      assert {:error, %Error{reason: :timeout}} = result
      assert elapsed < 700, "the timeout took #{elapsed}ms, past the 200ms request timeout"

      # Past the point the abandoned response is written. Its body must not
      # reach anyone: the timed-out connection was torn down, so this request
      # runs on a fresh one and gets its own body.
      Process.sleep(900)

      assert {:ok, %Response{body: %{"marker" => "fresh"}}} = Arangox.get(pool, "/fast")

      # The abandoned request really did reach the server and really was
      # responded late -- otherwise the assertion above proves nothing.
      assert Enum.any?(ProtocolServer.requests(server), &(&1["path"] == "/slow"))
    end
  end

  ## The derivation

  describe "socket timeout derivation" do
    test "a caller :timeout below the pool's :request_timeout still yields the driver's error" do
      {_port, url, _server} = start_server!(%{"/hang" => :hang})
      pool = start_pool!(url, request_timeout: 10_000)

      {elapsed, result} = timed(fn -> Arangox.get(pool, "/hang", [], timeout: 600) end)

      assert {:error, %Error{reason: :timeout}} = result

      assert elapsed < 600,
             "the driver's timeout must land before DBConnection's deadline, took #{elapsed}ms"
    end

    test "a caller that queued out most of its budget gets the remainder, not a fresh one" do
      {_port, url, _server} = start_server!(%{"/hang" => :hang})
      pool = start_pool!(url, request_timeout: 30_000)

      # Warm the single connection so the occupier does not pay for connecting.
      assert {:ok, %Response{}} = Arangox.get(pool, "/fast")

      occupier =
        Task.async(fn ->
          Arangox.run(pool, fn _conn -> Process.sleep(1_200) end, timeout: 10_000)
        end)

      # Let the occupier check the one connection out.
      Process.sleep(150)

      {elapsed, result} = timed(fn -> Arangox.get(pool, "/hang", [], timeout: 1_700) end)

      Task.await(occupier, 10_000)

      # A duration-based derivation restarts the 1_700ms clock at the socket,
      # so the caller is still in `recv` when DBConnection's deadline fires on
      # the pool process: it gets a DBConnection error at (or after) 1_700ms
      # instead of this one before it.
      assert {:error, %Error{reason: :timeout}} = result

      assert elapsed < 1_700,
             "the caller spent #{elapsed}ms, so it was given a fresh budget at the socket " <>
               "rather than the remainder of its own"
    end

    test "a deadline that has already elapsed fails fast without issuing the request" do
      {_port, url, server} = start_server!()

      assert {:ok, %Connection{} = state} =
               Connection.connect(endpoints: [url], client: MintClient)

      before = length(ProtocolServer.requests(server))

      assert {:error, %Error{reason: :deadline_exceeded} = error, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 %Request{method: :get, path: "/fast"},
                 [deadline: System.monotonic_time(:millisecond) - 1],
                 state
               )

      # Nothing was written, so the connection is healthy and must stay in the
      # pool -- disconnecting here would destroy a good connection every time a
      # caller queued too long, which is exactly when connections are scarce.
      refute Client.connection_lost?(error)
      assert length(ProtocolServer.requests(server)) == before

      Connection.disconnect(:normal, state)
    end

    test "raising :request_timeout lets a slow but valid request complete" do
      {_port, url, _server} =
        start_server!(%{"/slow" => {:delay, 600, {200, @json, ~s({"marker":"slow"})}}})

      pool = start_pool!(url, request_timeout: 200)

      assert {:error, %Error{reason: :timeout}} = Arangox.get(pool, "/slow")

      assert {:ok, %Response{body: %{"marker" => "slow"}}} =
               Arangox.get(pool, "/slow", [], request_timeout: 5_000)
    end

    test "a cursor honours the timeout per batch fetch rather than per stream" do
      {_port, url, _server} =
        start_server!(%{
          "/_api/cursor" =>
            {:delay, 400,
             {201, @json, ~s({"id":"c1","hasMore":true,"result":[1],"error":false,"code":201})}},
          "/_api/cursor/c1" =>
            {:delay, 400,
             {200, @json, ~s({"hasMore":false,"result":[2],"error":false,"code":200})}}
        })

      # Each batch waits 400ms; the whole stream waits 800ms. A budget spent
      # per stream would not survive the second batch.
      pool = start_pool!(url, request_timeout: 600)

      assert [1, 2] =
               Arangox.run(pool, fn conn ->
                 conn
                 |> Arangox.cursor("RETURN 1")
                 |> Enum.flat_map(& &1.body["result"])
               end)
    end
  end

  ## Validation

  describe ":request_timeout validation" do
    test "is rejected at pool start" do
      for invalid <- [0, -1, :infinity, "500", 1.5, nil] do
        assert_raise ArgumentError, ~r/:request_timeout/, fn ->
          Arangox.start_link(request_timeout: invalid)
        end
      end
    end

    test "is rejected per request, without harming the connection" do
      {_port, url, _server} = start_server!()
      pool = start_pool!(url, [])

      for invalid <- [0, -1, :infinity, "500"] do
        assert {:error, %Error{} = error} =
                 Arangox.get(pool, "/fast", [], request_timeout: invalid)

        assert Exception.message(error) =~ ":request_timeout"
        refute Client.connection_lost?(error)
      end

      assert {:ok, %Response{}} = Arangox.get(pool, "/fast")
    end

    test "a positive integer is accepted at pool start" do
      {_port, url, _server} = start_server!()
      pool = start_pool!(url, request_timeout: 1_000)

      assert {:ok, %Response{}} = Arangox.get(pool, "/fast")
    end
  end

  # A socket write blocks while the peer's receive window is full, and the
  # request budget bounds receives rather than writes. Gun applies its own
  # send bound only when `:tcp_opts` is absent from its options, and this
  # driver always passes the key — so the bound has to survive a caller
  # setting an unrelated transport option.
  describe "socket write bounds" do
    test "an unrelated tcp option does not remove the send bound" do
      {port, url, _server} = start_server!()

      assert {:ok, pid} =
               GunClient.connect(Endpoint.new(url), tcp_opts: [nodelay: true])

      assert %{socket: socket} = :gun.info(pid)
      assert {:ok, opts} = :inet.getopts(socket, [:send_timeout])
      assert opts[:send_timeout] == 15_000

      _ = port
    end

    test "a caller's own send_timeout wins" do
      {_port, url, _server} = start_server!()

      assert {:ok, pid} =
               GunClient.connect(Endpoint.new(url), tcp_opts: [send_timeout: 3_000])

      assert %{socket: socket} = :gun.info(pid)
      assert {:ok, opts} = :inet.getopts(socket, [:send_timeout])
      assert opts[:send_timeout] == 3_000
    end

    # Gun writes from its own process, so the per-request send bounds the
    # other clients carry do not apply — but the socket still gets the same
    # teardown hygiene: a bounded driver queue, and an abort on close instead
    # of a flush wait toward a peer that stopped reading.
    test "gun's socket carries the watermark and the zero linger" do
      {_port, url, _server} = start_server!()

      assert {:ok, pid} = GunClient.connect(Endpoint.new(url), [])
      assert %{socket: socket} = :gun.info(pid)

      assert {:ok, opts} = :inet.getopts(socket, [:high_watermark, :linger])
      assert opts[:high_watermark] == 65_536
      assert opts[:linger] == {true, 0}
    end

    # The pin that makes Gun's exclusion from per-request send bounds a fact
    # rather than an assumption: the caller's deadline covers it, because gun
    # writes from its own process and the caller only ever waits on messages.
    test "a Gun caller escapes a peer that never reads within its budget" do
      port = silent_listener!()

      assert {:ok, pid} = GunClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = state_for(GunClient, pid, request_timeout: 300)
      body = :binary.copy("x", 8 * 1024 * 1024)

      {elapsed, result} =
        timed(fn ->
          GunClient.request(%Request{method: :post, path: "/big", body: body}, [], state)
        end)

      assert {:error, %Error{} = error, _state} = result
      assert Client.connection_lost?(error)

      assert elapsed < 5_000,
             "the caller was held past its budget: took #{elapsed}ms"
    end

    # The write half of the deadline. A peer that accepts and never reads leaves the
    # caller blocked *inside* the socket write — the receive budget never
    # starts — so the send bound has to be derived from the remaining request
    # budget per request, not fixed at connect. The small sndbuf makes the
    # write block almost immediately; the elapsed bound is generous enough
    # for a loaded scheduler but far under the 15s connect-time default.
    test "a Mint write against a peer that never reads stops at the budget, not at 15s" do
      port = silent_listener!()

      assert {:ok, socket} =
               MintClient.connect(
                 Endpoint.new("http://localhost:#{port}"),
                 tcp_opts: [sndbuf: 16_384]
               )

      state = state_for(MintClient, socket, request_timeout: 300)
      body = :binary.copy("x", 8 * 1024 * 1024)

      {elapsed, result} =
        timed(fn ->
          MintClient.request(%Request{method: :post, path: "/big", body: body}, [], state)
        end)

      assert {:error, %Error{} = error, _state} = result
      assert Client.connection_lost?(error)

      assert elapsed < 5_000,
             "the write ignored the remaining budget: took #{elapsed}ms"
    end

    test "a VelocyStream write against a peer that never reads stops at the budget" do
      port = silent_listener!()

      assert {:ok, socket} =
               VelocyClient.connect(
                 Endpoint.new("http://localhost:#{port}"),
                 tcp_opts: [sndbuf: 16_384]
               )

      state = state_for(VelocyClient, socket, request_timeout: 300)
      body = :binary.copy("x", 8 * 1024 * 1024)

      {elapsed, result} =
        timed(fn ->
          VelocyClient.request(%Request{method: :post, path: "/big", body: body}, [], state)
        end)

      assert {:error, %Error{} = error, _state} = result
      assert Client.connection_lost?(error)

      assert elapsed < 5_000,
             "the write ignored the remaining budget: took #{elapsed}ms"
    end
  end

  describe "a budget spent before the write" do
    # The receive-phase wording claimed a response was in flight when no
    # request had been sent; the pre-send refusal must name the send.
    test "Mint names the send, not a phantom response" do
      {_port, url, _server} = start_server!()

      assert {:ok, socket} = MintClient.connect(Endpoint.new(url), [])
      state = state_for(MintClient, socket, request_timeout: 5_000)

      assert {:error, %Error{reason: :timeout} = error, %Connection{}} =
               MintClient.request(
                 %Request{method: :get, path: "/fast"},
                 [deadline: Client.monotonic_ms() - 1],
                 state
               )

      refute Exception.message(error) =~ "response"
      assert Exception.message(error) =~ "sent"
    end

    test "VelocyStream names the send too" do
      port = silent_listener!()

      assert {:ok, socket} = VelocyClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = state_for(VelocyClient, socket, request_timeout: 5_000)

      assert {:error, %Error{reason: :timeout} = error, %Connection{}} =
               VelocyClient.request(
                 %Request{method: :get, path: "/x"},
                 [deadline: Client.monotonic_ms() - 1],
                 state
               )

      refute Exception.message(error) =~ "response"
      assert Exception.message(error) =~ "sent"
    end
  end

  ## Client-level receive bounds

  # The budget covers the whole exchange. A client that hands its remaining
  # duration to a helper looping over chunks gets that duration *per chunk*,
  # which a peer trickling one byte at a time turns into an unbounded wait.
  describe "a chunked body is bounded by the request deadline, not per chunk" do
    for {client, connect} <- [
          {MintClient, &MintClient.connect/2},
          {GunClient, &GunClient.connect/2}
        ] do
      @client client
      @connect connect

      test "#{inspect(client)} gives up on a body that never finishes" do
        {_port, url, _server} = start_server!()

        assert {:ok, socket} = @connect.(Endpoint.new(url), [])
        state = state_for(@client, socket, request_timeout: 400)

        {elapsed, result} =
          timed(fn ->
            @client.request(%Request{method: :get, path: "/trickle"}, [], state)
          end)

        assert {:error, %Error{} = error, _state} = result

        assert elapsed < 2_000,
               "#{inspect(@client)} re-armed its budget per chunk: took #{elapsed}ms"

        assert Client.connection_lost?(error),
               "a part-read stream must retire the connection, got #{inspect(error.reason)}"
      end
    end
  end

  describe "a response body is bounded while it is received" do
    for {client, connect} <- [
          {MintClient, &MintClient.connect/2},
          {GunClient, &GunClient.connect/2}
        ] do
      @client client
      @connect connect

      test "#{inspect(client)} stops a streaming response at :max_body_size" do
        {_port, url, _server} = start_server!()

        assert {:ok, socket} = @connect.(Endpoint.new(url), [])
        state = state_for(@client, socket, request_timeout: 1_500, max_body_size: 4)

        {elapsed, result} =
          timed(fn ->
            @client.request(%Request{method: :get, path: "/trickle"}, [], state)
          end)

        assert {:error, %Error{reason: :body_too_large, status: 200} = error, _state} = result
        assert error.message =~ ":max_body_size (4)"
        assert elapsed < 1_000, "#{inspect(@client)} buffered past the configured limit"
        assert Client.connection_lost?(error)
      end
    end
  end

  describe "Arangox.MintClient" do
    test "times out on a server that sends headers then stalls mid-body" do
      {:ok, port, server} = ProtocolServer.start(listener: :raw)
      on_exit(fn -> ProtocolServer.stop(server) end)

      assert {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])

      state = state_for(MintClient, socket, request_timeout: 300)

      {elapsed, result} =
        timed(fn -> MintClient.request(%Request{method: :get, path: "/stall"}, [], state) end)

      assert {:error, %Error{reason: :timeout} = error, %Connection{}} = result
      assert elapsed < 1_500, "a stalled body was not bounded, took #{elapsed}ms"

      assert Client.connection_lost?(error),
             "a timed-out connection must not go back to the pool"
    end

    test "honours a caller deadline that is tighter than :request_timeout" do
      {:ok, port, server} = ProtocolServer.start(listener: :raw)
      on_exit(fn -> ProtocolServer.stop(server) end)

      assert {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])

      state = state_for(MintClient, socket, request_timeout: 30_000)

      {elapsed, result} =
        timed(fn ->
          MintClient.request(
            %Request{method: :get, path: "/hang"},
            [deadline: System.monotonic_time(:millisecond) + 400],
            state
          )
        end)

      assert {:error, %Error{reason: :timeout}, %Connection{}} = result
      assert elapsed < 1_500, "the caller deadline did not bound the receive, took #{elapsed}ms"
    end
  end

  describe "Arangox.VelocyClient" do
    test "times out against a socket that accepts and never responds" do
      port = silent_listener!()

      assert {:ok, socket} = VelocyClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = state_for(VelocyClient, socket, request_timeout: 300)

      {elapsed, result} =
        timed(fn -> VelocyClient.request(%Request{method: :get, path: @version}, [], state) end)

      assert {:error, %Error{reason: :timeout} = error, %Connection{}} = result
      assert elapsed < 1_500, "a VelocyStream receive was not bounded, took #{elapsed}ms"
      assert Client.connection_lost?(error)
    end

    test "honours a caller deadline that is tighter than :request_timeout" do
      port = silent_listener!()

      assert {:ok, socket} = VelocyClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = state_for(VelocyClient, socket, request_timeout: 30_000)

      {elapsed, result} =
        timed(fn ->
          VelocyClient.request(
            %Request{method: :get, path: @version},
            [deadline: System.monotonic_time(:millisecond) + 400],
            state
          )
        end)

      assert {:error, %Error{reason: :timeout}, %Connection{}} = result
      assert elapsed < 1_500, "the caller deadline did not bound the receive, took #{elapsed}ms"
    end

    @tag integration: :arango_3_11
    test "a real VelocyStream request against 3.11 still completes with the bound in place" do
      # All three members: only the leader responds to the availability probe with
      # 200, and which member leads is not fixed across container restarts, so
      # naming one port would tie the test to the current election. The walk
      # finding the leader is the driver's own failover behaviour.
      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [
                   TestHelper.failover_1(),
                   TestHelper.failover_2(),
                   TestHelper.failover_3()
                 ],
                 auth: {:basic, "root", ""},
                 client: VelocyClient,
                 request_timeout: 10_000
               )

      assert {:ok, _request, %Response{status: 200}, %Connection{}} =
               Connection.handle_execute(nil, %Request{method: :get, path: @version}, [], state)

      Connection.disconnect(:normal, state)
    end
  end
end
