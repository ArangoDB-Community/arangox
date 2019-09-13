defmodule Arangox.ClientTest do
  use ExUnit.Case, async: true
  # alias Mint.TransportError

  alias Arangox.{
    Client,
    Client.Mint,
    Client.Gun,
    Connection,
    Request,
    Response
  }

  @state struct(Connection, client: TestClient)
  @default TestHelper.default()
  @ssl TestHelper.ssl()

  describe "internal api:" do
    test "connect/3" do
      assert {:ok, _} = Client.connect(TestClient, "endpoint", [])
    end

    test "alive?/1" do
      assert true = Client.alive?(@state)
    end

    test "request/2" do
      assert {:ok, %Response{}, @state} = Client.request(struct(Request, []), @state)
    end

    test "close/1" do
      assert :ok = Client.close(@state)
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

    test "connect_timeout option" do
      assert {:error, :timeout} = Gun.connect(@default, connect_timeout: 0)
    end

    test "tcp_opts option" do
      catch_exit(Gun.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    test "ssl_opts option" do
      assert {:error, _} = Gun.connect(@ssl, ssl_opts: [verify: :verify_peer])
    end

    test "client_opts option" do
      assert {:error, _} =
               Gun.connect(@ssl, client_opts: %{transport_opts: [verify: :verify_peer]})
    end

    test "client_opts option takes precedence" do
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

    # test "connect_timeout option" do
    #   assert {:error, %TransportError{reason: :timeout}} =
    #            Mint.connect(@default, connect_timeout: 0)
    # end

    test "tcp_opts option" do
      catch_exit(Mint.connect(@default, tcp_opts: [verify: :verify_peer]))
    end

    test "ssl_opts option" do
      assert_raise RuntimeError, fn ->
        Mint.connect(@ssl, ssl_opts: [verify: :verify_peer])
      end
    end

    test "client_opts option" do
      assert_raise RuntimeError, fn ->
        Mint.connect(@ssl, client_opts: [transport_opts: [verify: :verify_peer]])
      end
    end

    test "client_opts option takes precedence" do
      assert_raise RuntimeError, fn ->
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
