defmodule Arangox.ClientTest do
  use ExUnit.Case, async: true
  # alias Mint.TransportError

  alias Arangox.{
    Client,
    Client.Gun,
    Client.Mint,
    Client.Velocy,
    Connection,
    Endpoint,
    Request,
    Response
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

      assert {:ok, %Response{}, state} = Client.request(struct(Request, []), state)
    end

    test "close/1" do
      state = struct(Connection, client: TestClient)

      assert :ok = Client.close(state)
    end
  end

  describe "velocy client:" do
    test "implementation" do
      assert {:ok, socket} = Velocy.connect(@default, [])
      state = struct(Connection, socket: socket)
      assert Velocy.alive?(state)

      assert :ok = Velocy.authorize(state)

      assert {:ok, %Response{}, ^state} =
               Velocy.request(%Request{method: :options, path: "/"}, state)

      assert :ok = Velocy.close(state)
      refute Velocy.alive?(state)
    end

    @tag :unix
    test "connecting to a unix socket" do
      if File.exists?("_build/#{Mix.env()}/velocy.sock") do
        File.rm("_build/#{Mix.env()}/velocy.sock")
      end

      _port = Port.open({:spawn, "nc -lU _build/#{Mix.env()}/velocy.sock"}, [:binary])
      endpoint = Endpoint.new("unix://#{Path.expand("_build")}/#{Mix.env()}/velocy.sock")

      :timer.sleep(1000)

      assert {:ok, _conn} = Velocy.connect(endpoint, [])
    after
      File.rm("_build/#{Mix.env()}/velocy.sock")
    end

    test "building and receiving multiple chunks (large requests and responses)" do
      Application.put_env(:arangox, :vst_maxsize, 30)

      {:ok, socket} = Velocy.connect(@default, [])
      state = struct(Connection, socket: socket)
      :ok = Velocy.authorize(state)
      body = for _ <- 1..100, into: "", do: "a"

      assert {:ok, %Response{status: 200}, ^state} =
               Velocy.request(%Request{method: :post, path: "/_admin/echo", body: body}, state)

      Application.put_env(:arangox, :vst_maxsize, 90)

      assert {:ok, %Response{status: 200}, ^state} =
               Velocy.request(%Request{method: :post, path: "/_admin/echo", body: body}, state)
    after
      Application.delete_env(:arangox, :vst_maxsize)
    end

    test "ssl and ssl_opts" do
      assert {:ok, {:ssl, _port}} = Velocy.connect(@ssl, [])

      assert {:error, _} = Velocy.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    test "tcp_opts option" do
      catch_exit(Velocy.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    # test "connect_timeout option" do
    #   assert {:error, :timeout} = Velocy.connect(@default, connect_timeout: 0)
    # end

    test "arangox's transport opts can't be overridden" do
      assert {:ok, socket} = Velocy.connect(@default, packet: :raw, mode: :binary, active: false)
      state = struct(Connection, socket: socket)
      assert Velocy.alive?(state)

      assert {:ok, %Response{}, ^state} =
               Velocy.request(%Request{method: :options, path: "/"}, state)
    end
  end

  describe "gun client:" do
    test "implementation" do
      assert {:ok, pid} = Gun.connect(@default, [])
      state = struct(Connection, socket: pid)
      assert Gun.alive?(state)

      assert {:ok, %Response{}, ^state} =
               Gun.request(%Request{method: :options, path: "/"}, state)

      assert :ok = Gun.close(state)
      refute Gun.alive?(state)
    end

    @tag :unix
    test "connecting to a unix socket" do
      if File.exists?("_build/#{Mix.env()}/gun.sock") do
        File.rm("_build/#{Mix.env()}/gun.sock")
      end

      _port = Port.open({:spawn, "nc -lU _build/#{Mix.env()}/gun.sock"}, [:binary])
      endpoint = Endpoint.new("unix://#{Path.expand("_build")}/#{Mix.env()}/gun.sock")

      :timer.sleep(1000)

      assert {:ok, _conn} = Gun.connect(endpoint, [])
    after
      File.rm("_build/#{Mix.env()}/gun.sock")
    end

    test "ssl and ssl_opts" do
      assert {:ok, pid} = Gun.connect(@ssl, [])

      assert {:error, _} = Gun.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    test "tcp_opts option" do
      catch_exit(Gun.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    test "connect_timeout option" do
      assert {:error, :timeout} = Gun.connect(@default, connect_timeout: 0)
    end

    test "client_opts option" do
      assert {:error, _} =
               Gun.connect(@ssl, client_opts: %{transport_opts: [verify: :verify_peer]})
    end

    test "client_opts takes precedence" do
      assert {:error, _} =
               Gun.connect(@ssl,
                 transport_opts: [verify: :verify_none],
                 client_opts: %{transport_opts: [verify: :verify_peer]}
               )
    end
  end

  describe "mint client:" do
    test "implementation" do
      assert {:ok, conn} = Mint.connect(@default, [])
      state = struct(Connection, socket: conn)
      assert Mint.alive?(state)

      assert {:ok, %Response{}, new_state} =
               Mint.request(%Request{method: :options, path: "/"}, state)

      assert :ok = Mint.close(new_state)
    end

    test "ssl and ssl_opts" do
      assert {:ok, _conn} = Mint.connect(@ssl, [])

      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        Mint.connect(@ssl, ssl_opts: [verify: :verify_peer])
      end
    end

    test "tcp_opts option" do
      catch_exit(Mint.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    # Only fails in travis-ci :(
    # test "connect_timeout option" do
    #   assert {:error, %TransportError{reason: :timeout}} =
    #            Mint.connect(@default, connect_timeout: 0)
    # end

    test "client_opts option" do
      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        Mint.connect(@ssl, client_opts: [transport_opts: [verify: :verify_peer]])
      end
    end

    test "client_opts takes precedence" do
      assert_raise RuntimeError, ~r/CA trust store/, fn ->
        Mint.connect(
          @ssl,
          transport_opts: [verify: :verify_none],
          client_opts: [transport_opts: [verify: :verify_peer]]
        )
      end
    end

    test "mode is always :passive" do
      assert {:ok, %_{mode: :passive}} = Mint.connect(@default, client_opts: [mode: :active])
    end
  end
end
