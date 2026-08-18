defmodule ArangoxTest do
  # Mixed tiers. Option validation is unit tier (it raises before any socket is
  # opened); everything tagged `:integration` talks to the containers from
  # docker-compose.yml. `async: false` because those tests all share the same
  # containers, and a couple of the unit-tier ones mutate application env.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import TestHelper, only: [opts: 1, opts: 0]

  alias Arangox.{
    Error,
    Request,
    Response
  }

  @unreachable TestHelper.unreachable()
  @auth TestHelper.auth()
  @default TestHelper.default()
  @ssl TestHelper.ssl()
  @failover_1 TestHelper.failover_1()
  @failover_2 TestHelper.failover_2()
  @failover_3 TestHelper.failover_3()
  @vst TestHelper.vst()

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
  @tag :integration
  test "disconnect_on_error_codes option" do
    {:ok, conn_empty} =
      Arangox.start_link(opts(endpoints: [@auth], disconnect_on_error_codes: []))

    refute capture_log(fn ->
             Arangox.get(conn_empty, "/_admin/server/mode")
             :timer.sleep(500)
           end) =~ "disconnected"

    {:ok, conn_401} =
      Arangox.start_link(opts(endpoints: [@auth], disconnect_on_error_codes: [401]))

    assert capture_log(fn ->
             Arangox.get(conn_401, "/_admin/server/mode")
             :timer.sleep(500)
           end) =~ "disconnected"
  end

  @tag :integration
  test "connecting with default options" do
    {:ok, conn} = Arangox.start_link(opts())
    Arangox.get!(conn, "/_admin/time")
  end

  test "connecting with bogus auth" do
    assert_raise ArgumentError, fn ->
      Arangox.start_link(opts(auth: "bogus"))
    end
  end

  test "auth option present with nil value is validated, not skipped" do
    assert_raise ArgumentError, fn ->
      Arangox.start_link(opts(auth: nil))
    end
  end

  @tag :integration
  test "connecting with auth disabled" do
    {:ok, conn1} = Arangox.start_link(opts(endpoints: [@auth]))
    assert {:error, %Error{status: 401}} = Arangox.get(conn1, "/_admin/server/mode")

    {:ok, conn2} = Arangox.start_link(opts(endpoints: [@default]))
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/mode")
  end

  @tag :integration
  test "connecting with ssl" do
    {:ok, conn} =
      Arangox.start_link(
        opts(auth: {:basic, "root", ""}, endpoints: [@ssl], ssl_opts: [verify: :verify_none])
      )

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

    assert {:ok, _conn} =
             Arangox.start_link(opts(endpoints: endpoint, client: Arangox.VelocyClient))

    assert_receive {^port, {:data, _data}}
  after
    File.rm("_build/#{Mix.env()}/unix.sock")
  end

  @tag :integration
  test "finding an available endpoint" do
    {:ok, conn} = Arangox.start_link(opts(endpoints: [@unreachable, @unreachable, @default]))

    Arangox.get!(conn, "/_admin/time")
  end

  @tag integration: :arango_3_11
  test "finding the leader in an active-failover setup" do
    {:ok, conn1} = Arangox.start_link(opts(endpoints: [@failover_1, @failover_2, @failover_3]))
    {:ok, conn2} = Arangox.start_link(opts(endpoints: [@failover_3, @failover_1, @failover_2]))
    {:ok, conn3} = Arangox.start_link(opts(endpoints: [@failover_2, @failover_3, @failover_1]))
    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/availability")
    assert %Response{status: 200} = Arangox.get!(conn3, "/_admin/server/availability")
  end

  @tag integration: :arango_3_11
  test "finding a follower in an active-failover setup" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(
          endpoints: [@failover_1, @failover_2, @failover_3],
          auth: {:basic, "root", ""},
          read_only?: true
        )
      )

    {:ok, conn2} =
      Arangox.start_link(
        opts(
          endpoints: [@failover_3, @failover_1, @failover_2],
          auth: {:basic, "root", ""},
          read_only?: true
        )
      )

    {:ok, conn3} =
      Arangox.start_link(
        opts(
          endpoints: [@failover_2, @failover_3, @failover_1],
          auth: {:basic, "root", ""},
          read_only?: true
        )
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

    test "non-binary value error names the database value" do
      error =
        assert_raise ArgumentError, fn ->
          Arangox.start_link(opts(database: :not_a_binary))
        end

      assert error.message =~ ":not_a_binary"
      refute error.message =~ "endpoint"
    end

    test "rejects path and query delimiters" do
      for database <- ["app/_admin", "a?b", "a#b", "a%b"] do
        error =
          assert_raise ArgumentError, fn ->
            Arangox.start_link(opts(database: database))
          end

        assert error.message =~ inspect(database)
      end
    end

    test "rejects control characters, DEL, empty and dot names" do
      for database <- ["a\nb", <<?a, 0, ?b>>, <<?a, 0x7F, ?b>>, "", ".", ".."] do
        assert_raise ArgumentError, fn ->
          Arangox.start_link(opts(database: database))
        end
      end
    end

    test "accepts spaces and unicode at validation" do
      for database <- ["my db", "münchen", "数据库 db"] do
        assert {:ok, pid} =
                 Arangox.start_link(
                   opts(database: database, endpoints: "http://localhost:1", pool_size: 1)
                 )

        GenServer.stop(pid)
      end
    end

    @tag :integration
    test "prepends request paths when using velocy client unless already prepended" do
      {:ok, conn} = Arangox.start_link(opts(database: "does_not_exist"))

      assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/database/current")

      assert %Response{body: %{"result" => %{"name" => "_system"}}} =
               Arangox.get!(conn, "/_db/_system/_api/database/current")
    end

    @tag :integration
    test "prepends request paths when using an http client unless already prepended" do
      {:ok, conn} =
        Arangox.start_link(opts(database: "does_not_exist", client: Arangox.MintClient))

      assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/database/current")

      assert %Response{body: %{"result" => %{"name" => "_system"}}} =
               Arangox.get!(conn, "/_db/_system/_api/database/current")
    end
  end

  # VelocyStream and authentication only coexist on the 3.11 service: 3.12
  # has authentication but removed the protocol. The service runs with
  # authentication enabled precisely so the two refusals below assert
  # something — on an unauthenticated server any credential is accepted.
  @tag integration: :arango_3_11
  test "auth resolution with velocy client" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(endpoints: [@vst], auth: {:basic, "root", ""}, client: Arangox.VelocyClient)
      )

    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")

    {:ok, conn2} =
      Arangox.start_link(
        opts(
          endpoints: [@vst],
          auth: {:basic, "root", "invalid"},
          client: Arangox.VelocyClient
        )
      )

    assert {:error, %DBConnection.ConnectionError{}} = Arangox.get(conn2, "/_admin/server/mode")

    {:ok, conn3} =
      Arangox.start_link(
        opts(endpoints: [@vst], auth: {:basic, "invalid", ""}, client: Arangox.VelocyClient)
      )

    assert {:error, %DBConnection.ConnectionError{}} = Arangox.get(conn3, "/_admin/server/mode")
  end

  @tag :integration
  test "auth resolution with an http client" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(endpoints: [@auth], auth: {:basic, "root", ""}, client: Arangox.MintClient)
      )

    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")

    {:ok, conn2} =
      Arangox.start_link(
        opts(
          endpoints: [@auth],
          username: "root",
          password: "invalid",
          client: Arangox.MintClient
        )
      )

    assert {:error, %Error{status: 401}} = Arangox.get(conn2, "/_admin/server/mode")

    {:ok, conn3} =
      Arangox.start_link(
        opts(endpoints: [@auth], username: "invalid", password: "", client: Arangox.MintClient)
      )

    assert {:error, %Error{status: 401}} = Arangox.get(conn3, "/_admin/server/mode")
  end

  @tag :integration
  test "auth resolution with an http client and invalid Bearer token" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(endpoints: [@auth], auth: {:bearer, "invalid"}, client: Arangox.MintClient)
      )

    assert {:error, %Error{status: 401}} = Arangox.get(conn1, "/_admin/server/mode")
  end

  @tag :integration
  test "auth resolution with an http client and valid Bearer token" do
    {:ok, conn1} =
      Arangox.start_link(
        opts(endpoints: [@auth], auth: {:basic, "root", ""}, client: Arangox.MintClient)
      )

    assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")

    assert %Response{status: 200, body: body1} =
             Arangox.post!(conn1, "/_open/auth", %{"username" => "root", "password" => ""})

    assert Map.has_key?(body1, "jwt")

    {:ok, conn2} =
      Arangox.start_link(opts(auth: {:bearer, body1["jwt"]}, client: Arangox.MintClient))

    assert %Response{status: 200} = Arangox.get!(conn2, "/_admin/server/mode")
  end

  @tag :integration
  test "headers option" do
    header = {"header", "value"}
    {:ok, conn} = Arangox.start_link(opts(headers: [header]))
    {:ok, %Request{headers: headers}, %Response{}} = Arangox.request(conn, :get, "/_admin/time")

    assert header in headers
  end

  @tag :integration
  test "request headers are appended after the pool's, nothing replaced" do
    header = {"header", "value"}
    {:ok, conn} = Arangox.start_link(opts(headers: [header]))

    {:ok, %Request{headers: headers}, %Response{}} =
      Arangox.request(conn, :get, "/_admin/time", "", [{"header", "new_value"}])

    assert header in headers
    assert {"header", "new_value"} in headers

    pool_at = Enum.find_index(headers, &(&1 == header))
    request_at = Enum.find_index(headers, &(&1 == {"header", "new_value"}))
    assert pool_at < request_at
  end

  describe "client option:" do
    test "when not an atom" do
      assert_raise ArgumentError, fn ->
        Arangox.start_link(opts(client: "client"))
      end
    end

    test "when present with a falsy value it is validated, not skipped" do
      error =
        assert_raise ArgumentError, fn ->
          Arangox.start_link(opts(client: false))
        end

      assert error.message =~ "false"
    end

    test "when not loaded" do
      assert_raise RuntimeError, fn ->
        Arangox.start_link(opts(client: :not_a_loaded_module))
      end
    end

    @tag :integration
    test "when is loaded" do
      {:ok, conn} = Arangox.start_link(opts(client: Arangox.MintClient))

      assert {:ok, %Response{}} = Arangox.get(conn, "/_admin/time")
    end

    test "Arangox.GunClient is a supported client" do
      assert {:ok, pid} =
               Arangox.start_link(
                 opts(client: Arangox.GunClient, endpoints: "http://localhost:1", pool_size: 1)
               )

      GenServer.stop(pid)
    end
  end

  describe "unknown options:" do
    test "warns naming the unknown key and the closest known key" do
      log =
        capture_log(fn ->
          assert {:ok, pid} =
                   Arangox.start_link(
                     opts(pool_sze: 5, endpoints: "http://localhost:1", pool_size: 1)
                   )

          GenServer.stop(pid)
        end)

      assert log =~ ":pool_sze"
      assert log =~ ":pool_size"
    end

    test "does not warn for arangox or known DBConnection options" do
      log =
        capture_log(fn ->
          assert {:ok, pid} =
                   Arangox.start_link(
                     opts(
                       endpoints: "http://localhost:1",
                       pool_size: 1,
                       queue_target: 100,
                       backoff_min: 500,
                       read_only?: false
                     )
                   )

          GenServer.stop(pid)
        end)

      refute log =~ "Unknown option"
    end
  end

  test "failover_callback option" do
    pid = self()
    fun = fn exception -> send(pid, {:fun, exception}) end
    tuple = {TestHelper, :failover_callback, [pid]}

    {:ok, _} =
      Arangox.start_link(
        opts(
          endpoints: [@unreachable, @unreachable, @auth],
          failover_callback: fun
        )
      )

    {:ok, _} =
      Arangox.start_link(
        opts(
          endpoints: [@unreachable, @unreachable, @auth],
          failover_callback: tuple
        )
      )

    assert_receive {:fun, %Error{}}
    assert_receive {:tuple, %Error{}}
  end

  # The `:json_library` and `:vst_maxsize` options, their deprecated
  # application-config fallback and the two deprecated reader functions live in
  # `Arangox.ConfigTest`.

  @tag :integration
  test "request functions" do
    {:ok, conn} = Arangox.start_link(opts())

    assert {:error, _} = Arangox.request(conn, :invalid_method, "/")
    assert_raise Error, fn -> Arangox.request!(conn, :invalid_method, "/") end

    assert {:ok, %Request{method: :get}, %Response{}} = Arangox.request(conn, :get, "/")
    assert %Response{} = Arangox.get!(conn, "/")
  end

  @tag :integration
  test "transaction/3" do
    {:ok, conn1} =
      Arangox.start_link(opts(endpoints: [@auth], auth: {:basic, "root", ""}))

    assert {:ok, %Response{}} =
             Arangox.transaction(
               conn1,
               fn c -> Arangox.get!(c, "/_admin/time") end,
               timeout: 15_000
             )

    {:ok, conn2} = Arangox.start_link(opts(endpoints: [@auth]))

    assert {:error, :rollback} =
             Arangox.transaction(
               conn2,
               fn c -> Arangox.get(c, "/_admin/server/status") end,
               timeout: 15_000
             )
  end

  @tag :integration
  test "cursors and run/3" do
    {:ok, conn} = Arangox.start_link(opts())

    assert [%Response{status: 201}] =
             Arangox.run(conn, fn c ->
               stream = Arangox.cursor(c, "return @this", [this: "this"], timeout: 15_000)
               Enum.to_list(stream)
             end)
  end

  @tag :integration
  test "ownership pool" do
    {:ok, conn} = Arangox.start_link(opts(pool: DBConnection.Ownership))

    assert %Response{} = Arangox.get!(conn, "/_admin/time")
    assert :ok = DBConnection.Ownership.ownership_checkin(conn, [])
  end
end
