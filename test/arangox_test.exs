defmodule ArangoxTest do
  use ExUnit.Case, async: true

  alias Arangox.{
    Error,
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

  # TODO: Test the way duplicate headers are overridden

  describe "invalid endpoints option:" do
    test "not a list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(endpoints: {})
      end
    end

    test "empty list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(endpoints: [])
      end
    end

    test "non-binary element in list" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(endpoints: ["binary", :not_a_binary])
      end
    end
  end

  test "connecting with default options" do
    {:ok, conn} = Arangox.start_link()
    Arangox.options!(conn)
  end

  test "connecting with auth disabled" do
    {:ok, conn1} = Arangox.start_link(auth?: false)
    assert {:error, %Arangox.Error{status: 401}} = Arangox.get(conn1, "/_admin/server/mode")

    {:ok, conn2} = Arangox.start_link(endpoints: [@no_auth], auth?: false)
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/mode")
  end

  test "connecting with ssl" do
    {:ok, conn} = Arangox.start_link(endpoints: [@ssl])
    Arangox.options!(conn)
  end

  @tag :unix
  test "connecting to a unix socket" do
    if File.exists?("test/unix.sock") do
      File.rm!("test/unix.sock")
    end

    port = Port.open({:spawn, "nc -lU test/unix.sock"}, [:binary])
    endpoint = "unix://#{Path.expand("test")}/unix.sock"

    {:ok, _conn} = Arangox.start_link(endpoints: [endpoint])

    assert_receive {^port, {:data, _data}}
  after
    File.rm!("test/unix.sock")
  end

  test "finding an available endpoint" do
    {:ok, conn} = Arangox.start_link(endpoints: [@unreachable, @unreachable, @default])

    Arangox.options!(conn)
  end

  test "finding the leader in an active-failover setup" do
    {:ok, conn1} = Arangox.start_link(endpoints: [@failover_1, @failover_2, @failover_3])
    {:ok, conn2} = Arangox.start_link(endpoints: [@failover_3, @failover_1, @failover_2])
    {:ok, conn3} = Arangox.start_link(endpoints: [@failover_2, @failover_3, @failover_1])
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn3, "/_admin/server/availability")
  end

  test "finding a follower in an active-failover setup" do
    {:ok, conn1} =
      Arangox.start_link(endpoints: [@failover_1, @failover_2, @failover_3], read_only?: true)

    {:ok, conn2} =
      Arangox.start_link(endpoints: [@failover_3, @failover_1, @failover_2], read_only?: true)

    {:ok, conn3} =
      Arangox.start_link(endpoints: [@failover_2, @failover_3, @failover_1], read_only?: true)

    assert {:error, %Error{status: 403}} = Arangox.delete(conn1, "/_api/database/readOnly")
    assert {:error, %Error{status: 403}} = Arangox.delete(conn2, "/_api/database/readOnly")
    assert {:error, %Error{status: 403}} = Arangox.delete(conn3, "/_api/database/readOnly")
  end

  describe "database option:" do
    test "invalid value" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(database: :not_a_binary)
      end
    end

    test "prepends request paths unless already prepended" do
      {:ok, conn} = Arangox.start_link(database: "does_not_exist")

      assert %Response{status: 404} = Arangox.get!(conn, "/_api/database/current")

      assert %Response{body: %{"result" => %{"name" => "_system"}}} =
               Arangox.get!(conn, "/_db/_system/_api/database/current")
    end
  end

  test "username and password options" do
    {:ok, conn1} = Arangox.start_link(username: "root", password: "")
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")
    {:ok, conn2} = Arangox.start_link(username: "root", password: "invalid")
    assert {:error, %Arangox.Error{status: 401}} = Arangox.get(conn2, "/_admin/server/mode")
    {:ok, conn3} = Arangox.start_link(username: "invalid", password: "")
    assert {:error, %Arangox.Error{status: 401}} = Arangox.get(conn3, "/_admin/server/mode")
  end

  test "headers option" do
    header = {"header", "value"}
    {:ok, conn} = Arangox.start_link(headers: [header])
    {:ok, %Request{headers: headers}, %Response{}} = Arangox.options(conn)

    assert header in headers
  end

  describe "client option:" do
    test "not an atom" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(client: "client")
      end
    end

    test "not loaded" do
      assert_raise RuntimeError, fn ->
        Arangox.start_link(client: :not_a_loaded_module)
      end
    end

    test "valid" do
      {:ok, conn} = Arangox.start_link(client: Arangox.Client.Mint)

      assert {:ok, %Request{}, %Response{}} = Arangox.options(conn)
    end
  end

  test "failover_callback option" do
    pid = self()
    fun = fn exception -> send(pid, {:fun, exception}) end
    tuple = {TestHelper, :failover_callback, [pid]}

    {:ok, _} =
      Arangox.start_link(
        endpoints: [@unreachable, @unreachable, @default],
        failover_callback: fun
      )

    {:ok, _} =
      Arangox.start_link(
        endpoints: [@unreachable, @unreachable, @default],
        failover_callback: tuple
      )

    assert_receive {:fun, %Arangox.Error{}}
    assert_receive {:tuple, %Arangox.Error{}}
  end

  test "json_library function and config" do
    assert Arangox.json_library() == Jason

    Application.put_env(:arangox, :json_library, Poison)
    assert Arangox.json_library() == Poison
  after
    Application.delete_env(:arangox, :json_library)
  end

  test "request functions" do
    {:ok, conn} = Arangox.start_link()
    header = {"header", "value"}

    {:ok, %Request{body: body, headers: headers}, %Response{status: 200}} =
      Arangox.request(conn, :options, "/", %{}, [header])

    assert body == "{}"
    assert header in headers

    assert {:error, _} = Arangox.request(conn, :invalid_method, "/")
    assert_raise Arangox.Error, fn -> Arangox.request!(conn, :invalid_method, "/") end

    assert {:ok, %Request{method: :get}, %Response{}} = Arangox.get(conn, "/")
    assert %Response{} = Arangox.get!(conn, "/")

    assert {:ok, %Request{method: :head}, %Response{}} = Arangox.head(conn, "/")
    assert %Response{} = Arangox.head!(conn, "/")

    assert {:ok, %Request{method: :delete}, %Response{}} = Arangox.delete(conn, "/")
    assert %Response{} = Arangox.delete!(conn, "/")

    assert {:ok, %Request{method: :post}, %Response{}} = Arangox.post(conn, "/")
    assert %Response{} = Arangox.post!(conn, "/")

    assert {:ok, %Request{method: :put}, %Response{}} = Arangox.put(conn, "/")
    assert %Response{} = Arangox.put!(conn, "/")

    assert {:ok, %Request{method: :patch}, %Response{}} = Arangox.patch(conn, "/")
    assert %Response{} = Arangox.patch!(conn, "/")

    assert {:ok, %Request{method: :options}, %Response{}} = Arangox.options(conn)
    assert %Response{} = Arangox.options!(conn)
  end

  test "transaction execution" do
    {:ok, conn} = Arangox.start_link()

    assert {:ok, %Response{}} =
             Arangox.transaction(conn, fn c ->
               Arangox.options!(c)
             end)

    assert {:error, :rollback} =
             Arangox.transaction(conn, fn c ->
               Arangox.request(c, :invalid_method, "/")
             end)
  end

  test "ownership pool" do
    {:ok, conn} = Arangox.start_link(pool: DBConnection.Ownership)

    assert %Response{} = Arangox.options!(conn)
    assert :ok = DBConnection.Ownership.ownership_checkin(conn, [])
  end
end
