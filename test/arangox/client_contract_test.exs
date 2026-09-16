defmodule Arangox.ClientContractTest do
  @moduledoc """
  The single `Arangox.Client` error contract, run against
  both shipped clients from one set of assertions.

  Unit and protocol tier: no Docker. Real sockets go to
  `Arangox.ProtocolServer` on an ephemeral local port or unix socket.

  Every assertion here replaced a characterization assertion pinning the shape
  the same call once returned — a raw `Mint.TransportError`, a bare POSIX
  atom, an `{:error, :noproc, state}` sentinel, an `ArgumentError` for a unix
  endpoint and an `exit` for a bad transport option.
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
    Request,
    Response,
    VelocyClient
  }

  alias Arangox.ContractClients.{Alive, Legacy, NoAlive}

  doctest Arangox.Client, only: [connection_lost?: 1]

  # A port nothing is listening on.
  @refused 65_001

  # Every shipped client, run through the same assertions.
  @clients [MintClient, VelocyClient, GunClient]

  defp refused_endpoint, do: Endpoint.new("http://localhost:#{@refused}")

  defp state_for(client, socket), do: struct(Connection, socket: socket, client: client)

  describe "the socket options a caller sets reach the socket:" do
    # Both HTTP clients build their library's socket options from `:tcp_opts`
    # or `:ssl_opts` plus the write bounds, then merge `:client_opts` over
    # that per key. A client that replaced the key wholesale would drop the
    # write bounds for any caller who set one unrelated socket option.
    test "gun merges :client_opts over the derived socket options per key" do
      assert {:error, %Error{reason: reason}} =
               GunClient.connect(refused_endpoint(),
                 tcp_opts: [not_a_socket_option: true],
                 client_opts: %{tcp_opts: [nodelay: true]}
               )

      assert reason == :badarg,
             "the derived list was replaced rather than merged: the unrecognised option " <>
               "never reached the socket, so the write bounds would not have either"
    end

    test "gun reaches the socket at all when nothing is overridden" do
      assert {:error, %Error{reason: :econnrefused}} = GunClient.connect(refused_endpoint(), [])
    end

    # `Mint.TransportError` renders a reason it does not special-case through
    # `:ssl.format_error/1`, which requires an atom. A tagged tuple makes that
    # raise, and `Exception.message/1` answers with a diagnostic carrying a
    # stack trace, which would become this error's message.
    test "mint describes an unrecognised socket option instead of quoting a diagnostic" do
      assert {:error, %Error{reason: :badarg, message: message}} =
               MintClient.connect(Endpoint.new("https://localhost:#{@refused}"),
                 ssl_opts: [verify: :verify_none, not_a_socket_option: true]
               )

      assert message =~ "not_a_socket_option", "the message must name the option at fault"
      refute message =~ "Exception.message", "the message must not be a formatting diagnostic"
      refute message =~ "Stacktrace", "the message must not carry a stack trace"
    end

    test "mint still uses the library's own wording for a reason it can format" do
      assert {:error, %Error{reason: :econnrefused, message: "connection refused"}} =
               MintClient.connect(refused_endpoint(), [])
    end
  end

  describe "one error contract:" do
    for client <- @clients do
      @client client

      test "#{inspect(client)} returns a structured error with a reason atom from a refused port" do
        assert {:error, %Error{} = error} = @client.connect(refused_endpoint(), [])
        assert error.reason == :econnrefused
        assert is_binary(Exception.message(error))

        # The client never sees the configured endpoint, only a parsed one, so
        # it cannot leak userinfo. Arangox.Connection stamps the redacted
        # endpoint on.
        assert error.endpoint == nil
      end

      test "#{inspect(client)} returns an error rather than exiting on a rejected transport option" do
        assert {:error, %Error{} = error} =
                 @client.connect(refused_endpoint(), tcp_opts: [verify: :verify_peer])

        assert is_atom(error.reason)
      end

      test "#{inspect(client)} signals a mid-request socket close with a connection-lost reason" do
        {:ok, port, server} = ProtocolServer.start(listener: :raw)
        on_exit(fn -> ProtocolServer.stop(server) end)

        {:ok, socket} = @client.connect(Endpoint.new("http://localhost:#{port}"), [])

        assert {:error, %Error{} = error, _state} =
                 @client.request(
                   %Request{method: :get, path: "/truncate"},
                   [],
                   state_for(@client, socket)
                 )

        assert Client.connection_lost?(error),
               "#{inspect(@client)} returned #{inspect(error.reason)}, which is not in " <>
                 "Arangox.Client.connection_lost_reasons/0"
      end

      test "#{inspect(client)} accepts per-request options it does not understand" do
        {:ok, port, server} = ProtocolServer.start(listener: :raw)
        on_exit(fn -> ProtocolServer.stop(server) end)

        {:ok, socket} = @client.connect(Endpoint.new("http://localhost:#{port}"), [])

        assert {_, _, _} =
                 @client.request(
                   %Request{method: :get, path: "/truncate"},
                   [timeout: 5_000, some_future_option: :ignored],
                   state_for(@client, socket)
                 )
      end
    end
  end

  describe "mint over a unix domain socket:" do
    test "connects and completes a request instead of raising" do
      {:ok, path, server} = ProtocolServer.start(unix: true)
      on_exit(fn -> ProtocolServer.stop(server) end)

      endpoint = Endpoint.new("http://unix:#{path}")
      assert %Endpoint{addr: {:unix, ^path}} = endpoint

      assert {:ok, socket} = MintClient.connect(endpoint, [])

      assert {:ok, %Response{status: 200}, _state} =
               MintClient.request(
                 %Request{method: :get, path: "/status/200"},
                 [],
                 state_for(MintClient, socket)
               )
    end

    test "a unix path with nothing listening is an error, not a raise" do
      endpoint = Endpoint.new("http://unix:/tmp/arangox-does-not-exist.sock")

      assert {:error, %Error{reason: :enoent}} = MintClient.connect(endpoint, [])
    end
  end

  describe "the connection-lost reason forces a disconnect:" do
    # `:connection_listeners` is DBConnection's own notification channel: the
    # connection process itself sends `{:connected, pid}` and
    # `{:disconnected, pid}`, so the disconnect is observed rather than inferred
    # from a later symptom.
    #
    # What changes across a reconnect is the **socket**, not the connection
    # process: `DBConnection` re-enters `connect/1` in the same `:gen_statem`
    # under backoff and the pid is stable for the pool's lifetime. The client
    # hands out a fresh socket per connect and echoes it back in `x-socket`, so
    # the assertion is on the thing that actually moves.
    test "DBConnection disconnects and reconnects onto a new socket" do
      pool = listening_pool()

      assert_receive {:connected, connection}, 1_000
      assert {:ok, %Response{} = before} = Arangox.get(pool, "/fine")

      # `/boom` responds with reason :closed, which is in
      # Arangox.Client.connection_lost_reasons/0.
      assert {:error, %Error{reason: :closed}} = Arangox.get(pool, "/boom")

      assert_receive {:disconnected, ^connection}, 1_000
      assert_receive {:connected, ^connection}, 1_000

      assert after_socket =
               eventually(fn ->
                 case Arangox.get(pool, "/fine") do
                   {:ok, %Response{headers: headers}} ->
                     :proplists.get_value("x-socket", headers, nil)

                   _other ->
                     nil
                 end
               end)

      assert after_socket != :proplists.get_value("x-socket", before.headers, nil),
             "the pool kept using the socket the client declared lost"
    end

    test "a request after a mid-request socket close succeeds on a fresh connection" do
      pool = listening_pool()

      assert_receive {:connected, connection}, 1_000
      assert {:error, %Error{reason: :closed}} = Arangox.get(pool, "/boom")
      assert_receive {:disconnected, ^connection}, 1_000

      assert eventually(fn ->
               case Arangox.get(pool, "/fine") do
                 {:ok, %Response{status: 200}} -> true
                 _other -> nil
               end
             end),
             "the pool never recovered: a lost socket was returned to it intact"
    end

    test "an ordinary error does not disconnect" do
      pool = listening_pool()

      assert_receive {:connected, connection}, 1_000

      assert {:ok, %Response{status: 200}} = Arangox.get(pool, "/fine")

      refute_receive {:disconnected, ^connection}, 200
    end
  end

  describe "alive?/1 is optional:" do
    test "a client that does not implement it compiles and works" do
      refute function_exported?(NoAlive, :alive?, 1)
      refute Client.implements_alive?(NoAlive)

      assert Client.alive?(state_for(NoAlive, :socket)),
             "a client without alive?/1 must default to alive rather than crash"

      {:ok, pool} = Arangox.start_link(client: NoAlive, pool_size: 1)
      on_exit(fn -> stop_pool(pool) end)

      assert {:ok, %Response{status: 200}} = Arangox.get(pool, "/fine")
    end

    test "a client that does implement it keeps working unchanged" do
      assert Client.implements_alive?(Alive)

      refute Client.alive?(state_for(Alive, :socket))
      assert Process.get(:alive_called), "Arangox.Client.alive?/1 did not reach the callback"
    end

    # THE TRAP. `function_exported?/3` returns false for a module that has not
    # been *loaded*, which under lazy loading is any module nothing has called
    # into yet. Without `Code.ensure_loaded?/1` first, a client that does
    # implement alive?/1 would be reported as not implementing it, and the
    # default would be taken silently.
    #
    # This test creates the ordering rather than hoping for it: it purges the
    # module, asserts the bare check is wrong, and asserts the guarded one is
    # right. Purging while other tests could be using the module is why this
    # file is async: false.
    test "the export check survives a module that has not been loaded yet" do
      assert Code.ensure_loaded?(Alive)
      :code.purge(Alive)
      true = :code.delete(Alive)
      :code.purge(Alive)

      assert :code.is_loaded(Alive) == false,
             "the module is still loaded, so this test proves nothing"

      refute function_exported?(Alive, :alive?, 1),
             "function_exported?/3 returned true for an unloaded module; the trap is gone " <>
               "and this test no longer proves the guard is needed"

      assert Client.implements_alive?(Alive),
             "Arangox.Client.implements_alive?/1 missed a callback that exists, because the " <>
               "module was not loaded yet"
    end
  end

  describe "a client on the pre-0.8 two-argument callback:" do
    test "start_link/1 refuses it, naming the new signature" do
      assert_raise ArgumentError, ~r/request\(%Arangox\.Request\{\} = request, opts, /, fn ->
        Arangox.start_link(client: Legacy)
      end
    end

    test "the raised message names both the old callback and the new return contract" do
      error = assert_raise(ArgumentError, fn -> Arangox.start_link(client: Legacy) end)
      message = Exception.message(error)

      assert message =~ "pre-v0.8 Arangox.Client.request/2"
      assert message =~ "{:error, %Arangox.Error{}, state}"
    end

    test "calling it through Arangox.Client fails with the same explanation" do
      state = state_for(Legacy, :socket)

      error =
        assert_raise UndefinedFunctionError, fn ->
          Client.request(%Request{method: :get, path: "/"}, [], state)
        end

      assert Exception.message(error) =~ "pre-v0.8 Arangox.Client.request/2"
      assert Exception.message(error) =~ "opts, %Arangox.Connection{} = state"
    end
  end

  describe "an errorNum the vendored table does not contain:" do
    test "yields the catch-all reason and keeps the status and the number" do
      {:ok, port, server} = ProtocolServer.start()
      on_exit(fn -> ProtocolServer.stop(server) end)

      body = ~s({"error":true,"code":500,"errorNum":9999999,"errorMessage":"from the future"})

      ProtocolServer.set_routes(server, %{
        "/_admin/server/availability" => {200, [{"content-type", "application/json"}], "{}"},
        "/_api/version" => {200, [{"content-type", "application/json"}], "{}"},
        "/future" => {500, [{"content-type", "application/json"}], body}
      })

      {:ok, pool} =
        Arangox.start_link(
          client: MintClient,
          endpoints: "http://localhost:#{port}",
          pool_size: 1
        )

      on_exit(fn -> stop_pool(pool) end)

      assert {:error, %Error{} = error} = Arangox.get(pool, "/future")

      assert error.reason == Arangox.Errno.unknown()
      assert error.status == 500
      assert error.error_num == 9_999_999
      assert error.message == "from the future"
    end

    test "a known errorNum yields its atom" do
      {:ok, port, server} = ProtocolServer.start()
      on_exit(fn -> ProtocolServer.stop(server) end)

      body = ~s({"error":true,"code":404,"errorNum":1202,"errorMessage":"document not found"})

      ProtocolServer.set_routes(server, %{
        "/_admin/server/availability" => {200, [{"content-type", "application/json"}], "{}"},
        "/_api/version" => {200, [{"content-type", "application/json"}], "{}"},
        "/gone" => {404, [{"content-type", "application/json"}], body}
      })

      {:ok, pool} =
        Arangox.start_link(
          client: MintClient,
          endpoints: "http://localhost:#{port}",
          pool_size: 1
        )

      on_exit(fn -> stop_pool(pool) end)

      assert {:error, %Error{reason: :arango_document_not_found, status: 404, error_num: 1202}} =
               Arangox.get(pool, "/gone")
    end

    test "a body that cannot be decoded is a structured error with a bounded excerpt, not a raise" do
      {:ok, port, server} = ProtocolServer.start()
      on_exit(fn -> ProtocolServer.stop(server) end)

      html = "<html><body>" <> String.duplicate("x", 5_000) <> "</body></html>"

      ProtocolServer.set_routes(server, %{
        "/_admin/server/availability" => {200, [{"content-type", "application/json"}], "{}"},
        "/_api/version" => {200, [{"content-type", "application/json"}], "{}"},
        "/proxy" => {502, [{"content-type", "text/html"}], html}
      })

      {:ok, pool} =
        Arangox.start_link(
          client: MintClient,
          endpoints: "http://localhost:#{port}",
          pool_size: 1
        )

      on_exit(fn -> stop_pool(pool) end)

      assert {:error, %Error{status: 502} = error} = Arangox.get(pool, "/proxy")
      assert error.message =~ "truncated"
      assert byte_size(error.message) < byte_size(html)
      assert byte_size(Exception.message(error)) <= Error.message_limit() + 200
    end
  end

  ## Helpers

  defp listening_pool do
    {:ok, pool} =
      Arangox.start_link(
        client: NoAlive,
        pool_size: 1,
        backoff_min: 1,
        connection_listeners: [self()]
      )

    on_exit(fn -> stop_pool(pool) end)
    pool
  end

  defp eventually(fun, attempts \\ 200) do
    Enum.reduce_while(1..attempts, nil, fn _n, _acc ->
      case fun.() do
        nil ->
          Process.sleep(10)
          {:cont, nil}

        false ->
          Process.sleep(10)
          {:cont, nil}

        result ->
          {:halt, result}
      end
    end)
  end
end
