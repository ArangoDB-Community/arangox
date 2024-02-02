defmodule ArangoxTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import TestHelper, only: [opts: 1, opts: 0]

  alias Arangox.{
    Error,
    GunClient,
    Request,
    Response
  }

  doctest Arangox

  @unreachable TestHelper.unreachable()
  @default TestHelper.default()
  @no_auth TestHelper.no_auth()
  @ssl TestHelper.ssl()
  @failover_1 TestHelper.failover_1()
  @failover_2 TestHelper.failover_2()
  @failover_3 TestHelper.failover_3()

  describe "invalid endpoints option:" do
    test "not a list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(endpoints: {}))
      end
    end

    test "empty list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(endpoints: []))
      end
    end

    test "non-binary element in list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(endpoints: ["binary", :not_a_binary]))
      end
    end
  end

  @tag capture_log: false
  test "disconnect_on_error_codes option" do
    {:ok, conn_empty} =
      Arangox.start_link(opts(disconnect_on_error_codes: [], auth_mode: Arangox.Auth.off()))

    refute capture_log(fn ->
             Arangox.get(conn_empty, "/_admin/server/mode")
             :timer.sleep(500)
           end) =~ "disconnected"

    {:ok, conn_401} =
      Arangox.start_link(opts(disconnect_on_error_codes: [401], auth_mode: Arangox.Auth.off()))

    assert capture_log(fn ->
             Arangox.get(conn_401, "/_admin/server/mode")
             :timer.sleep(500)
           end) =~ "disconnected"
  end

  test "connecting with default options" do
    {:ok, conn} = Arangox.start_link(opts())
    Arangox.get!(conn, "/_admin/time")
  end

  test "connecting with bogus mode" do
    assert_raise ArgumentError,  fn ->
      Arangox.start_link(opts(auth_mode: "bogus"))
      end
  end

  test "connecting with auth disabled" do
    {:ok, conn1} = Arangox.start_link(opts(auth_mode: :authentication_off))
    assert {:error, %Error{status: 401}} = Arangox.get(conn1, "/_admin/server/mode")

    {:ok, conn2} = Arangox.start_link(opts(endpoints: [@no_auth], auth_mode: :authentication_off))
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/mode")
  end

  test "connecting with ssl" do
    {:ok, conn} = Arangox.start_link(opts(endpoints: [@ssl]))
    Arangox.get!(conn, "/_admin/time")
  end

  @tag :unix
  test "connecting to a unix socket" do
    if File.exists?("_build/#{Mix.env()}/unix.sock") do
      File.rm("_build/#{Mix.env()}/unix.sock")
    end

    port = Port.open({:spawn, "nc -lU _build/#{Mix.env()}/unix.sock"}, [:binary])
    endpoint = "unix://#{Path.expand("_build")}/#{Mix.env()}/unix.sock"

    :timer.sleep(1000)

    assert {:ok, _conn} = Arangox.start_link(opts(endpoints: endpoint))

    assert_receive {^port, {:data, _data}}
  after
    File.rm("_build/#{Mix.env()}/unix.sock")
  end

  test "finding an available endpoint" do
    {:ok, conn} = Arangox.start_link(opts(endpoints: [@unreachable, @unreachable, @default]))

    Arangox.get!(conn, "/_admin/time")
  end

  test "finding the leader in an active-failover setup" do
    {:ok, conn1} = Arangox.start_link(opts(endpoints: [@failover_1, @failover_2, @failover_3]))
    {:ok, conn2} = Arangox.start_link(opts(endpoints: [@failover_3, @failover_1, @failover_2]))
    {:ok, conn3} = Arangox.start_link(opts(endpoints: [@failover_2, @failover_3, @failover_1]))
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn3, "/_admin/server/availability")
  end

  test "finding a follower in an active-failover setup" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(endpoints: [@failover_1, @failover_2, @failover_3], read_only?: true)
      )

    {:ok, conn2} =
      Arangox.start_link(
        opts(endpoints: [@failover_3, @failover_1, @failover_2], read_only?: true)
      )

    {:ok, conn3} =
      Arangox.start_link(
        opts(endpoints: [@failover_2, @failover_3, @failover_1], read_only?: true)
      )

    assert {:error, %Error{status: 403}} = Arangox.delete(conn1, "/_api/database/mydatabase")
    assert {:error, %Error{status: 403}} = Arangox.delete(conn2, "/_api/database/mydatabase")
    assert {:error, %Error{status: 403}} = Arangox.delete(conn3, "/_api/database/mydatabase")
  end

  describe "database option:" do
    test "invalid value" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(database: :not_a_binary))
      end
    end

    test "prepends request paths when using velocy client unless already prepended" do
      {:ok, conn} = Arangox.start_link(opts(database: "does_not_exist"))

      assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/database/current")

      assert %Response{body: %{"result" => %{"name" => "_system"}}} =
               Arangox.get!(conn, "/_db/_system/_api/database/current")
    end

    test "prepends request paths when using an http client unless already prepended" do
      {:ok, conn} = Arangox.start_link(opts(database: "does_not_exist", client: GunClient))

      assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/database/current")

      assert %Response{body: %{"result" => %{"name" => "_system"}}} =
               Arangox.get!(conn, "/_db/_system/_api/database/current")
    end
  end

  test "auth resolution with velocy client" do
    {:ok, conn1} = Arangox.start_link(opts(username: "root", password: ""))
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")
    {:ok, conn2} = Arangox.start_link(opts(username: "root", password: "invalid"))
    assert {:error, %DBConnection.ConnectionError{}} = Arangox.get(conn2, "/_admin/server/mode")
    {:ok, conn3} = Arangox.start_link(opts(username: "invalid", password: ""))
    assert {:error, %DBConnection.ConnectionError{}} = Arangox.get(conn3, "/_admin/server/mode")
  end

  test "auth resolution with an http client" do
    {:ok, conn1} = Arangox.start_link(opts(username: "root", password: "", client: GunClient))
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")

    {:ok, conn2} =
      Arangox.start_link(opts(username: "root", password: "invalid", client: GunClient))

    assert {:error, %Error{status: 401}} = Arangox.get(conn2, "/_admin/server/mode")
    {:ok, conn3} = Arangox.start_link(opts(username: "invalid", password: "", client: GunClient))
    assert {:error, %Error{status: 401}} = Arangox.get(conn3, "/_admin/server/mode")
  end

  test "auth resolution with an http client and invalid JWT token" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(auth_mode: :authentication_jwt, jwt_token: "invalid", client: GunClient)
      )

    assert {:error, %Error{status: 401}} = Arangox.get(conn1, "/_admin/server/mode")
  end

  test "auth resolution with an http client and valid JWT token" do
    {:ok, conn1} = Arangox.start_link(opts(username: "root", password: "", client: GunClient))
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")

    assert %Response{status: 200, body: body1} =
             Arangox.post!(conn1, "/_open/auth", %{"username" => "root", "password" => ""})

    assert Map.has_key?(body1, "jwt")

    {:ok, conn2} =
      Arangox.start_link(
        opts(auth_mode: :authentication_jwt, jwt_token: body1["jwt"], client: GunClient)
      )

    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/mode")
  end

  test "headers option" do
    header = {"header", "value"}
    {:ok, conn} = Arangox.start_link(opts(headers: Map.new([header])))
    {:ok, %Request{headers: headers}, %Response{}} = Arangox.request(conn, :get, "/_admin/time")

    assert header in headers
  end

  test "request headers override values in headers option" do
    header = {"header", "value"}
    {:ok, conn} = Arangox.start_link(opts(headers: Map.new([header])))

    {:ok, %Request{headers: headers}, %Response{}} =
      Arangox.request(conn, :get, "/_admin/time", "", %{"header" => "new_value"})

    assert header not in headers
  end

  describe "client option:" do
    test "when not an atom" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(client: "client"))
      end
    end

    test "when not loaded" do
      assert_raise RuntimeError, fn ->
        Arangox.start_link(opts(client: :not_a_loaded_module))
      end
    end

    test "when is loaded" do
      {:ok, conn} = Arangox.start_link(opts(client: Arangox.MintClient))

      assert {:ok, %Response{}} = Arangox.get(conn, "/_admin/time")
    end
  end

  test "failover_callback option" do
    pid = self()
    fun = fn exception -> send(pid, {:fun, exception}) end
    tuple = {TestHelper, :failover_callback, [pid]}

    {:ok, _} =
      Arangox.start_link(
        opts(
          endpoints: [@unreachable, @unreachable, @default],
          failover_callback: fun
        )
      )

    {:ok, _} =
      Arangox.start_link(
        opts(
          endpoints: [@unreachable, @unreachable, @default],
          failover_callback: tuple
        )
      )

    assert_receive {:fun, %Error{}}
    assert_receive {:tuple, %Error{}}
  end

  test "json_library function and config" do
    assert Arangox.json_library() == Jason

    Application.put_env(:arangox, :json_library, Poison)
    assert Arangox.json_library() == Poison
  after
    Application.delete_env(:arangox, :json_library)
  end

  test "request functions" do
    {:ok, conn} = Arangox.start_link(opts())

    assert {:error, _} = Arangox.request(conn, :invalid_method, "/")
    assert_raise Error, fn -> Arangox.request!(conn, :invalid_method, "/") end

    assert {:ok, %Request{method: :get}, %Response{}} = Arangox.request(conn, :get, "/")
    assert %Response{} = Arangox.get!(conn, "/")
  end

  test "transaction/3" do
    {:ok, conn1} = Arangox.start_link(opts())

    assert {:ok, %Response{}} =
             Arangox.transaction(
               conn1,
               fn c -> Arangox.get!(c, "/_admin/time") end,
               timeout: 15_000
             )

    {:ok, conn2} = Arangox.start_link(opts(auth_mode: :authentication_off))

    assert {:error, :rollback} =
             Arangox.transaction(
               conn2,
               fn c -> Arangox.get(c, "/_admin/server/status") end,
               timeout: 15_000
             )
  end

  test "cursors and run/3" do
    {:ok, conn} = Arangox.start_link(opts())

    assert [%Response{status: 201}] =
             Arangox.run(conn, fn c ->
               stream = Arangox.cursor(c, "return @this", [this: "this"], timeout: 15_000)
               Enum.to_list(stream)
             end)
  end

  test "ownership pool" do
    {:ok, conn} = Arangox.start_link(opts(pool: DBConnection.Ownership))

    assert %Response{} = Arangox.get!(conn, "/_admin/time")
    assert :ok = DBConnection.Ownership.ownership_checkin(conn, [])
  end
end
