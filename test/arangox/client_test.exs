defmodule Arangox.ClientTest do
  use ExUnit.Case, async: true

  alias Arangox.{
    Client,
    Connection,
    Endpoint,
    GunClient,
    MintClient,
    Request,
    Response,
    VelocyClient
  }

  @default Endpoint.new(TestHelper.default())
  @ssl Endpoint.new(TestHelper.ssl())

  describe "internal api:" do
    test "connect/3" do
      assert {:ok, _} = Client.connect(TestClient, "endpoint", [])
    end

    test "alive?/1" do
      state = struct(Connection, client: TestClient)

      assert true = Client.alive?(state)
    end

    test "request/2" do
      state = struct(Connection, client: TestClient)

      assert {:ok, %Response{}, _state} = Client.request(struct(Request, []), state)
    end

    test "close/1" do
      state = struct(Connection, client: TestClient)

      assert :ok = Client.close(state)
    end
  end

  describe "velocy client:" do
    test "implementation" do
      assert {:ok, socket} = VelocyClient.connect(@default, [])
      state = struct(Connection, socket: socket)
      assert VelocyClient.alive?(state)

      assert :ok = VelocyClient.authorize(state)

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(%Request{method: :get, path: "/_api/database/current"}, state)

      assert :ok = VelocyClient.close(state)
      refute VelocyClient.alive?(state)
    end

    @tag :unix
    test "connecting to a unix socket" do
      if File.exists?("_build/#{Mix.env()}/velocy.sock") do
        File.rm("_build/#{Mix.env()}/velocy.sock")
      end

      _port = Port.open({:spawn, "nc -lU _build/#{Mix.env()}/velocy.sock"}, [:binary])
      endpoint = Endpoint.new("unix://#{Path.expand("_build")}/#{Mix.env()}/velocy.sock")

      :timer.sleep(1000)

      assert {:ok, _conn} = VelocyClient.connect(endpoint, [])
    after
      File.rm("_build/#{Mix.env()}/velocy.sock")
    end

    test "building and receiving multiple chunks (large requests and responses)" do
      Application.put_env(:arangox, :vst_maxsize, 30)

      {:ok, socket} = VelocyClient.connect(@default, [])
      state = struct(Connection, socket: socket)
      :ok = VelocyClient.authorize(state)
      body = for _ <- 1..100, into: "", do: "a"

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(
                 %Request{method: :post, path: "/_admin/echo", body: body},
                 state
               )

      Application.put_env(:arangox, :vst_maxsize, 90)

      assert {:ok, %Response{status: 200}, ^state} =
               VelocyClient.request(
                 %Request{method: :post, path: "/_admin/echo", body: body},
                 state
               )
    after
      Application.delete_env(:arangox, :vst_maxsize)
    end

    test "ssl and ssl_opts" do
      assert {:ok, {:ssl, _port}} = VelocyClient.connect(@ssl, [])

      assert {:error, _} = VelocyClient.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    test "tcp_opts option" do
      catch_exit(VelocyClient.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    # test "connect_timeout option" do
    #   assert {:error, :timeout} = VelocyClient.connect(@default, connect_timeout: 0)
    # end

    test "arangox's transport opts can't be overridden" do
      assert {:ok, socket} =
               VelocyClient.connect(@default, packet: :raw, mode: :binary, active: false)

      state = struct(Connection, socket: socket)
      assert VelocyClient.alive?(state)

      assert {:ok, %Response{}, ^state} =
               VelocyClient.request(%Request{method: :options, path: "/"}, state)
    end
  end

  describe "gun client:" do
    test "implementation" do
      assert {:ok, pid} = GunClient.connect(@default, [])
      state = struct(Connection, socket: pid)
      assert GunClient.alive?(state)

      assert {:ok, %Response{}, ^state} =
               GunClient.request(%Request{method: :options, path: "/"}, state)

      assert :ok = GunClient.close(state)
      refute GunClient.alive?(state)
    end

    @tag :unix
    test "connecting to a unix socket" do
      if File.exists?("_build/#{Mix.env()}/gun.sock") do
        File.rm("_build/#{Mix.env()}/gun.sock")
      end

      _port = Port.open({:spawn, "nc -lU _build/#{Mix.env()}/gun.sock"}, [:binary])
      endpoint = Endpoint.new("unix://#{Path.expand("_build")}/#{Mix.env()}/gun.sock")

      :timer.sleep(1000)

      assert {:ok, _conn} = GunClient.connect(endpoint, [])
    after
      File.rm("_build/#{Mix.env()}/gun.sock")
    end

    test "ssl and ssl_opts" do
      assert {:ok, _pid} = GunClient.connect(@ssl, [])

      assert {:error, _} = GunClient.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    test "tcp_opts option" do
      assert {:error, _} = GunClient.connect(@default, tcp_opts: [verify: :verify_peer])
    end

    test "connect_timeout option" do
      assert {:error, :timeout} = GunClient.connect(@default, connect_timeout: 0)
    end

    test "client_opts option" do
      assert {:error, _} =
               GunClient.connect(@ssl, client_opts: %{transport_opts: [verify: :verify_peer]})
    end

    test "client_opts takes precedence" do
      assert {:error, _} =
               GunClient.connect(@ssl,
                 transport_opts: [verify: :verify_none],
                 client_opts: %{transport_opts: [verify: :verify_peer]}
               )
    end
  end

  describe "mint client:" do
    test "implementation" do
      assert {:ok, conn} = MintClient.connect(@default, [])
      state = struct(Connection, socket: conn)
      assert MintClient.alive?(state)

      assert {:ok, %Response{}, new_state} =
               MintClient.request(%Request{method: :options, path: "/"}, state)

      assert :ok = MintClient.close(new_state)
    end

    test "ssl and ssl_opts" do
      assert {:ok, _conn} = MintClient.connect(@ssl, [])

      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        MintClient.connect(@ssl, ssl_opts: [verify: :verify_peer])
      end
    end

    test "tcp_opts option" do
      catch_exit(MintClient.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    # Only fails in travis-ci :(
    # test "connect_timeout option" do
    #   assert {:error, %TransportError{reason: :timeout}} =
    #            MintClient.connect(@default, connect_timeout: 0)
    # end

    test "client_opts option" do
      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        MintClient.connect(@ssl, client_opts: [transport_opts: [verify: :verify_peer]])
      end
    end

    test "client_opts takes precedence" do
      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        MintClient.connect(
          @ssl,
          transport_opts: [verify: :verify_none],
          client_opts: [transport_opts: [verify: :verify_peer]]
        )
      end
    end

    test "mode is always :passive" do
      assert {:ok, %_{mode: :passive}} =
               MintClient.connect(@default, client_opts: [mode: :active])
    end
  end
end
