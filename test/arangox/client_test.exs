defmodule Arangox.ClientTest.ScriptedTransport do
  @moduledoc """
  A `:gen_tcp`-shaped transport whose `recv/3` serves from a scripted queue.

  `Arangox.VelocyClient` treats a socket as `{module, port}`; here the port is
  an `Agent` holding a list of `recv/3` replies, popped in order. `send/2`
  accepts anything. A negative length raises, as `:gen_tcp.recv/3` would —
  a test that reaches that raise is exercising how the client reports a
  transport blow-up mid-response.
  """

  def start(replies), do: Agent.start_link(fn -> replies end)

  def send(_agent, _data), do: :ok

  def recv(_agent, length, _timeout) when length < 0 do
    raise ArgumentError, "negative receive length"
  end

  def recv(agent, _length, _timeout) do
    Agent.get_and_update(agent, fn [reply | rest] -> {reply, rest} end)
  end

  def close(_agent), do: :ok
end

defmodule Arangox.ClientTest do
  # Mixed tiers: the "internal api:" block is unit tier, the "velocy client:"
  # and "mint client:" blocks drive real sockets against the containers from
  # docker-compose.yml. `async: false` because those blocks share the same
  # containers.
  use ExUnit.Case, async: false

  alias Arangox.{
    Client,
    Connection,
    Endpoint,
    MintClient,
    Request,
    Response,
    VelocyClient
  }

  @auth Endpoint.new(TestHelper.auth())
  @ssl Endpoint.new(TestHelper.ssl())
  @vst Endpoint.new(TestHelper.vst())

  def default_opts do
    [
      auth: {:basic, "root", ""}
    ]
  end

  describe "internal api:" do
    test "connect/3" do
      assert {:ok, _} = Client.connect(TestClient, "endpoint", [])
    end

    test "alive?/1" do
      state = struct(Connection, client: TestClient)

      assert true = Client.alive?(state)
    end

    test "request/3" do
      state = struct(Connection, client: TestClient)

      assert {:ok, %Response{}, _state} = Client.request(struct(Request, []), [], state)
    end

    test "close/1" do
      state = struct(Connection, client: TestClient)

      assert :ok = Client.close(state)
    end
  end

  # Failures after the request is on the wire leave unread bytes on the
  # socket; checked back into the pool, the next request would read the
  # previous response. The reason must therefore be one the pool retires on
  # , whatever went wrong on the way to a complete response.
  describe "velocy client, a response the codec cannot survive:" do
    alias Arangox.{Error, VelocyClient}
    alias Arangox.ClientTest.ScriptedTransport

    test "a desynchronized stream retires the connection" do
      # What reading mid-stream garbage looks like: 24 bytes that parse as a
      # chunk header but describe a chunk smaller than the header itself.
      header =
        <<5::little-32, :binary.decode_unsigned(<<1::31, 1::1>>, :little)::32, 0::little-64,
          5::little-64>>

      {:ok, agent} = ScriptedTransport.start([{:ok, header}])

      state =
        struct(Connection,
          client: VelocyClient,
          socket: {ScriptedTransport, agent},
          vst_maxsize: 30_720
        )

      assert {:error, %Error{} = error, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)

      assert Client.connection_lost?(error),
             "reason #{inspect(error.reason)} does not retire a desynchronized connection"
    end

    test "a body that cannot be encoded fails without retiring the connection" do
      {:ok, agent} = ScriptedTransport.start([])

      state =
        struct(Connection,
          client: VelocyClient,
          socket: {ScriptedTransport, agent},
          vst_maxsize: 30_720
        )

      request = %Request{method: :post, path: "/x", body: self()}

      assert {:error, %Error{} = error, %Connection{}} = VelocyClient.request(request, [], state)

      refute Client.connection_lost?(error),
             "an unencodable body never reached the wire, yet reason " <>
               "#{inspect(error.reason)} retires the connection"
    end
  end

  # Every test here that actually speaks VelocyStream to a server points at
  # `@vst`, the 3.11 container, because 3.12 removed the protocol. The two
  # that do not are deliberate: `tcp_opts option` is refused by `:gen_tcp`
  # before a server is ever reached, and `ssl and ssl_opts` needs a TLS endpoint,
  # which only the 3.12 service has — neither exercises VelocyStream itself.
  describe "velocy client:" do
    @describetag integration: :arango_3_11

    # VelocyStream carries response headers as a VPack map, so the list is
    # built from it: no duplicates are possible and the order is the map's,
    # not the server's send order.
    test "response headers are a list of tuples" do
      assert {:ok, socket} = VelocyClient.connect(@vst, default_opts())
      state = struct(Connection, socket: socket, auth: {:basic, "root", ""})
      assert :ok = VelocyClient.maybe_authenticate(state)

      assert {:ok, %Response{status: 200, headers: headers}, ^state} =
               VelocyClient.request(
                 %Request{method: :get, path: "/_api/version"},
                 [],
                 state
               )

      assert is_list(headers)

      assert Enum.all?(headers, fn
               {name, value} -> is_binary(name) and is_binary(value)
               _other -> false
             end)
    end

    test "implementation" do
      assert {:ok, socket} = VelocyClient.connect(@vst, default_opts())
      state = struct(Connection, socket: socket, auth: {:basic, "root", ""})
      assert VelocyClient.alive?(state)

      assert :ok = VelocyClient.maybe_authenticate(state)

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(
                 %Request{method: :get, path: "/_api/database/current"},
                 [],
                 state
               )

      assert :ok = VelocyClient.close(state)
      refute VelocyClient.alive?(state)
    end

    @tag :unix
    test "connecting to a unix socket" do
      socket_path = "_build/#{Mix.env()}/velocy.sock"

      if File.exists?(socket_path) do
        File.rm(socket_path)
      end

      _port = Port.open({:spawn, "nc -lU #{socket_path}"}, [:binary])
      endpoint = Endpoint.new("unix://#{Path.expand(socket_path)}")

      TestHelper.await_unix_socket!(socket_path)

      assert {:ok, _conn} = VelocyClient.connect(endpoint, [])
    after
      File.rm("_build/#{Mix.env()}/velocy.sock")
    end

    # Stays integration tier: it proves a real ArangoDB reassembles what the
    # chunker writes. The chunk size now comes from connection state
    # rather than from application env, so the two sizes here genuinely take
    # effect and a 100-byte body genuinely chunks. Unit-tier framing coverage
    # (chunk count and chunk sizes, no server) is in `Arangox.ConfigTest`, and
    # protocol-tier coverage extends it against `Arangox.ProtocolServer`.
    # `resilient_single` is an active-failover trio. Any member serves a read or
    # an authentication, which is why most of this block can name one port and
    # stop thinking about it — but `/_admin/echo` is a POST, and a follower
    # responds to that with `503 "not a leader"` and the leader's advertised
    # endpoint. Which member leads is not fixed across container restarts, so it
    # is found rather than assumed.
    defp vst_leader! do
      url =
        Enum.find(
          [TestHelper.vst(), TestHelper.failover_2(), TestHelper.failover_3()],
          &leader?(Endpoint.new(&1))
        )

      assert url, "no leader among the 3.11 active-failover members"

      Endpoint.new(url)
    end

    defp leader?(endpoint) do
      case VelocyClient.connect(endpoint, default_opts()) do
        {:ok, socket} ->
          state =
            struct(Connection, socket: socket, auth: {:basic, "root", ""}, vst_maxsize: 30_720)

          :ok = VelocyClient.maybe_authenticate(state)

          leader? =
            match?(
              {:ok, %Response{status: 200}, _state},
              VelocyClient.request(
                %Request{method: :post, path: "/_admin/echo", body: "probe"},
                [],
                state
              )
            )

          VelocyClient.close(state)
          leader?

        {:error, _reason} ->
          false
      end
    end

    test "building and receiving multiple chunks (large requests and responses)" do
      opts = default_opts()
      {:ok, socket} = VelocyClient.connect(vst_leader!(), opts)
      state = struct(Connection, socket: socket, auth: {:basic, "root", ""}, vst_maxsize: 30)
      :ok = VelocyClient.maybe_authenticate(state)
      body = for _ <- 1..100, into: "", do: "a"

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(
                 %Request{method: :post, path: "/_admin/echo", body: body},
                 [],
                 state
               )

      state = %{state | vst_maxsize: 90}

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(
                 %Request{method: :post, path: "/_admin/echo", body: body},
                 [],
                 state
               )
    end

    # This client adds no TLS defaults of its own and takes none
    # away, so `:ssl`'s own default applies and the container's self-signed
    # certificate is refused until the caller says otherwise. Stays on the 3.12
    # service: it is the only one with a TLS endpoint, and nothing here reaches
    # the VelocyStream protocol — `connect/2` writes the handshake and returns.
    test "ssl and ssl_opts" do
      assert {:error, %Arangox.Error{}} = VelocyClient.connect(@ssl, [])

      assert {:ok, {:ssl, _port}} = VelocyClient.connect(@ssl, ssl_opts: [verify: :verify_none])

      assert {:error, %Arangox.Error{}} =
               VelocyClient.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    # A transport option `:gen_tcp` rejects comes back as an
    # `Arangox.Error`, like every other client failure — never an exit.
    test "tcp_opts option" do
      assert {:error, %Arangox.Error{}} =
               VelocyClient.connect(@auth, tcp_opts: [verify: :verify_peer])
    end

    # test "connect_timeout option" do
    #   assert {:error, :timeout} = VelocyClient.connect(@auth, connect_timeout: 0)
    # end

    test "arangox's transport opts can't be overridden" do
      opts = default_opts()
      opts = Keyword.merge(opts, packet: :raw, mode: :binary, active: false)

      assert {:ok, socket} =
               VelocyClient.connect(@vst, opts)

      state = struct(Connection, socket: socket)
      assert VelocyClient.alive?(state)

      assert {:ok, %Response{}, ^state} =
               VelocyClient.request(%Request{method: :options, path: "/"}, [], state)
    end
  end

  describe "mint client:" do
    @describetag :integration

    test "implementation" do
      assert {:ok, conn} = MintClient.connect(@auth, [])
      state = struct(Connection, socket: conn)
      assert MintClient.alive?(state)

      assert {:ok, %Response{}, new_state} =
               MintClient.request(%Request{method: :options, path: "/"}, [], state)

      assert :ok = MintClient.close(new_state)
    end

    # Verification is the default: with no options at all, the
    # handshake runs against real trust material — Mint falls back to the OS
    # trust store (`:public_key.cacerts_get/0`) — and fails on the harness's
    # self-signed certificate. That handshake failure is the proof the option
    # reached the socket, which is what each of these tests exists to show.
    test "ssl and ssl_opts" do
      assert {:error, %Arangox.Error{reason: :tls_alert} = error} = MintClient.connect(@ssl, [])
      assert Exception.message(error) =~ "Bad Certificate"

      assert {:error, %Arangox.Error{reason: :tls_alert}} =
               MintClient.connect(@ssl, ssl_opts: [verify: :verify_peer])

      # The documented opt-out, and the only thing that still gets through.
      assert {:ok, _conn} = MintClient.connect(@ssl, ssl_opts: [verify: :verify_none])
    end

    test "tcp_opts option" do
      assert {:error, %Arangox.Error{}} =
               MintClient.connect(@auth, tcp_opts: [verify: :verify_peer])
    end

    # Only fails in travis-ci :(
    # test "connect_timeout option" do
    #   assert {:error, %TransportError{reason: :timeout}} =
    #            MintClient.connect(@auth, connect_timeout: 0)
    # end

    test "client_opts option" do
      assert {:error, %Arangox.Error{reason: :tls_alert}} =
               MintClient.connect(@ssl, client_opts: [transport_opts: [verify: :verify_peer]])
    end

    test "client_opts takes precedence" do
      # The failure is the proof: had `transport_opts: [verify: :verify_none]`
      # won, this connect would have succeeded.
      assert {:error, %Arangox.Error{reason: :tls_alert}} =
               MintClient.connect(
                 @ssl,
                 transport_opts: [verify: :verify_none],
                 client_opts: [transport_opts: [verify: :verify_peer]]
               )
    end

    test "mode is always :passive" do
      assert {:ok, %_{mode: :passive}} =
               MintClient.connect(@auth, client_opts: [mode: :active])
    end
  end
end
