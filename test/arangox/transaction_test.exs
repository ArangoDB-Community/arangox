defmodule Arangox.TransactionTest.StubClient do
  @moduledoc """
  A scripted `Arangox.Client` for the transaction-callback tests, written
  against the **new** three-argument `c:Arangox.Client.request/3` shape and
  the one-error contract (the standing regression client for the legacy
  two-argument shape lives in `Arangox.ConnectionTest`).

  Scripts are keyed by `{method, path}` and travel in the fabricated socket
  inside the connection state, so there is no named process and the tests
  stay `async: true`. Every request is reported to the owning test process
  as `{:request, %Arangox.Request{}}` **as it went on the wire** — headers
  merged, body encoded — so a test can assert exactly what was sent, or
  that nothing was.

  A scripted response is `{status, json_binary}`; `{:error, reason}`
  returns an `%Arangox.Error{reason: reason}`. Anything unscripted returns
  `200 {}`, which is also what lets `connect/2` pass the connect pipeline's
  availability and version probes in the pool-backed tests.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Endpoint, Error, Request, Response}

  @impl true
  def connect(%Endpoint{}, opts) do
    {:ok, opts |> Keyword.fetch!(:client_opts) |> Map.new()}
  end

  @impl true
  def request(%Request{} = request, _opts, %Connection{socket: socket} = state) do
    send(socket.owner, {:request, request})

    case Map.get(socket.script, {request.method, request.path}, {200, "{}"}) do
      {:error, reason} ->
        {:error, %Error{reason: reason, message: "scripted #{inspect(reason)}"}, state}

      {status, body} ->
        {:ok, %Response{status: status, headers: [], body: body}, state}
    end
  end

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.TransactionTest do
  @moduledoc """
  Transactions, both forms.

  The DBConnection transaction callbacks (closure form) against a
  scripted client, plus the DBConnection-driven flows (nested transactions,
  commit-failure recovery) through a real pool.

  The handle form — `Arangox.begin_transaction/2` and
  friends, the `:transaction` per-request option, identifier validation and
  redaction. Protocol tier throughout; the tests that need true
  cross-connection and cross-coordinator application run against the live
  cluster from `docker-compose.yml` and are tagged `:integration`.

  Protocol tier: no Docker, no network — the client is scripted.
  """

  use ExUnit.Case, async: true

  import TestHelper, only: [stop_pool: 1]

  alias Arangox.{Connection, Error, Query, Request, Response, Transaction}
  alias Arangox.TransactionTest.StubClient

  doctest Arangox.Transaction

  @trx_header "x-arango-trx-id"
  @begin_path "/_api/transaction/begin"

  @begin_ok {201, ~s({"code":201,"error":false,"result":{"id":"123","status":"running"}})}
  @conflict {409, ~s({"code":409,"error":true,"errorNum":1200,"errorMessage":"conflict"})}
  @unavailable {503, ~s({"code":503,"error":true,"errorNum":503,"errorMessage":"unavailable"})}

  defp trx_body(status),
    do: ~s({"code":200,"error":false,"result":{"id":"123","status":"#{status}"}})

  ## Direct-callback harness

  defp state(script, fields \\ []) do
    struct(
      Connection,
      [
        socket: %{owner: self(), script: script},
        client: StubClient,
        endpoint: "http://stub",
        cursors: %{}
      ] ++ fields
    )
  end

  defp in_trx(script), do: state(script, trx_id: "123")

  ## Pool harness

  defp start_pool(script) do
    {:ok, conn} =
      Arangox.start_link(
        client: StubClient,
        client_opts: [owner: self(), script: script],
        pool_size: 1,
        idle_interval: 60_000
      )

    on_exit(fn -> stop_pool(conn) end)

    conn
  end

  defp drain_requests(acc \\ []) do
    receive do
      {:request, %Request{} = request} -> drain_requests([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # The connect pipeline probes (/_admin/server/availability, /_api/version)
  # also report through the stub, so pool-backed assertions about "no request
  # went out" filter down to the transaction API.
  defp drained_transaction_requests do
    drain_requests() |> Enum.filter(&String.starts_with?(&1.path, "/_api/transaction"))
  end

  defp get_request, do: %Request{method: :get, path: "/doc"}

  ## Cluster harness (integration tier)

  defp cluster_pool(endpoint) do
    {:ok, conn} =
      Arangox.start_link(
        endpoints: [endpoint],
        pool_size: 2,
        show_sensitive_data_on_connection_error: true
      )

    on_exit(fn -> stop_pool(conn) end)

    conn
  end

  defp create_collection(conn) do
    name = "u7_trx_#{System.unique_integer([:positive])}"
    %Response{} = Arangox.post!(conn, "/_api/collection", %{name: name})

    on_exit(fn ->
      {:ok, cleaner} = Arangox.start_link(endpoints: [TestHelper.cluster_1()], pool_size: 1)
      _ = Arangox.delete(cleaner, "/_api/collection/" <> name)
      GenServer.stop(cleaner)
    end)

    name
  end

  describe "Arangox.Transaction builders" do
    test "begin_body/1 shapes collections and merges :properties" do
      opts = [read: "a", write: ["b"], exclusive: "c", properties: [waitForSync: true]]

      assert Transaction.begin_body(opts) == %{
               collections: %{read: "a", write: ["b"], exclusive: "c"},
               waitForSync: true
             }

      assert Transaction.begin_body([]) == %{collections: %{}}
    end

    test "begin_body/1 accepts :properties as a map" do
      assert Transaction.begin_body(properties: %{allowImplicit: false}) == %{
               collections: %{},
               allowImplicit: false
             }
    end

    test "one builder per server operation" do
      assert %Request{method: :post, path: "/_api/transaction/begin", body: %{collections: %{}}} =
               Transaction.begin(%{collections: %{}})

      assert %Request{method: :get, path: "/_api/transaction/42"} = Transaction.status("42")
      assert %Request{method: :put, path: "/_api/transaction/42"} = Transaction.commit("42")
      assert %Request{method: :delete, path: "/_api/transaction/42"} = Transaction.abort("42")
    end
  end

  describe "handle_begin/2" do
    # The identifier is echoed into a request path and a header, so a value
    # this driver cannot address means a transaction is running server-side
    # that nothing can commit or abort. The connection goes; returning
    # `{:error, exception, state}` here would be outside the callback's
    # documented returns and DBConnection would raise it out of
    # `Arangox.transaction/3` rather than rolling back.
    test "a malformed server identifier disconnects rather than raising" do
      script = %{
        {:post, "/_api/transaction/begin"} =>
          {201, Jason.encode!(%{"result" => %{"id" => "not-an-id"}})}
      }

      assert {:disconnect, %Error{} = error, %Connection{}} =
               Connection.handle_begin([], state(script))

      assert error.message =~ "malformed transaction identifier"
    end

    test "posts to /_api/transaction/begin and stores the returned id in the headers" do
      script = %{{:post, @begin_path} => @begin_ok}

      assert {:ok, %Response{status: 201}, %Connection{} = new_state} =
               Connection.handle_begin([write: "coll"], state(script))

      assert new_state.trx_id == "123"
      assert_received {:request, %Request{method: :post, path: @begin_path} = request}
      assert Jason.decode!(request.body) == %{"collections" => %{"write" => "coll"}}
    end

    test "builds the collections document and merges :properties into the body" do
      script = %{{:post, @begin_path} => @begin_ok}

      opts = [
        read: ["a", "b"],
        write: "c",
        exclusive: "d",
        properties: [waitForSync: true, lockTimeout: 5]
      ]

      assert {:ok, %Response{}, %Connection{}} = Connection.handle_begin(opts, state(script))

      assert_received {:request, %Request{method: :post} = request}

      assert Jason.decode!(request.body) == %{
               "collections" => %{"read" => ["a", "b"], "write" => "c", "exclusive" => "d"},
               "waitForSync" => true,
               "lockTimeout" => 5
             }
    end

    test "a transaction already in flight reports :transaction and issues no request" do
      state = in_trx(%{})

      assert {:transaction, ^state} = Connection.handle_begin([], state)
      refute_received {:request, _request}
    end

    test "a 201 whose body lacks the transaction id is an error, not a crash" do
      script = %{{:post, @begin_path} => {201, ~s({"code":201,"error":false,"result":{}})}}

      assert {:error, %Connection{} = new_state} = Connection.handle_begin([], state(script))
      assert new_state.trx_id == nil
    end

    test "a success status other than 201 is an error" do
      # Unscripted returns 200 {} — a success, but not a begun transaction.
      assert {:error, %Connection{} = new_state} = Connection.handle_begin([], state(%{}))
      assert new_state.trx_id == nil
    end

    test "a server-side refusal is an error" do
      script = %{{:post, @begin_path} => @conflict}

      assert {:error, %Connection{}} = Connection.handle_begin([], state(script))
    end

    test "a 503 during begin is collapsed into a plain error (step-4 decision: preserved)" do
      script = %{{:post, @begin_path} => @unavailable}

      assert {:error, %Connection{}} = Connection.handle_begin([], state(script))
    end

    test "a dead socket during begin is collapsed into a plain error (step-4 decision: preserved)" do
      script = %{{:post, @begin_path} => {:error, :closed}}

      assert {:error, %Connection{}} = Connection.handle_begin([], state(script))
    end
  end

  describe "handle_status/2" do
    test "no transaction in flight reports :idle and issues no request" do
      state = state(%{})

      assert {:idle, ^state} = Connection.handle_status([], state)
      refute_received {:request, _request}
    end

    test "a running transaction reports :transaction; the probe carries the trx header" do
      script = %{{:get, "/_api/transaction/123"} => {200, trx_body("running")}}

      assert {:transaction, %Connection{} = new_state} =
               Connection.handle_status([], in_trx(script))

      assert new_state.trx_id == "123"

      assert_received {:request, %Request{method: :get, path: "/_api/transaction/123"} = request}
      assert {@trx_header, "123"} in request.headers
    end

    # The body's status decides, not the HTTP 200 — a 200 only means the
    # server responded, and its body can already name the transaction aborted.
    test "a transaction the server has aborted reports :error" do
      script = %{{:get, "/_api/transaction/123"} => {200, trx_body("aborted")}}

      assert {:error, %Connection{}} = Connection.handle_status([], in_trx(script))
    end

    test "a transaction the server has committed reports :idle" do
      script = %{{:get, "/_api/transaction/123"} => {200, trx_body("committed")}}

      assert {:idle, %Connection{}} = Connection.handle_status([], in_trx(script))
    end

    test "a status this driver does not recognize reports :error" do
      script = %{{:get, "/_api/transaction/123"} => {200, trx_body("hibernating")}}

      assert {:error, %Connection{}} = Connection.handle_status([], in_trx(script))
    end

    test "a server-side error reports :error" do
      script = %{{:get, "/_api/transaction/123"} => @conflict}

      assert {:error, %Connection{}} = Connection.handle_status([], in_trx(script))
    end

    test "a 503 propagates a disconnect" do
      script = %{{:get, "/_api/transaction/123"} => @unavailable}

      assert {:disconnect, %Error{status: 503}, %Connection{}} =
               Connection.handle_status([], in_trx(script))
    end
  end

  describe "handle_commit/2" do
    test "no transaction in flight reports :idle and issues no request" do
      state = state(%{})

      assert {:idle, ^state} = Connection.handle_commit([], state)
      refute_received {:request, _request}
    end

    test "a 200 commits, clears the header, and the request goes out without the trx header" do
      script = %{{:put, "/_api/transaction/123"} => {200, trx_body("committed")}}

      assert {:ok, %Response{status: 200}, %Connection{} = new_state} =
               Connection.handle_commit([], in_trx(script))

      assert new_state.trx_id == nil

      assert_received {:request, %Request{method: :put, path: "/_api/transaction/123"} = request}
      refute Enum.any?(request.headers, fn {name, _} -> name == @trx_header end)
    end

    # A failed commit must leave the identifier in state, or the
    # follow-up rollback finds nothing to address and the server-side
    # transaction leaks until it times out. A failed commit leaves the
    # transaction reachable, so the rollback issues a real request.
    test "a failed commit leaves the transaction reachable for the follow-up rollback" do
      script = %{
        {:put, "/_api/transaction/123"} => @conflict,
        {:delete, "/_api/transaction/123"} => {200, trx_body("aborted")}
      }

      assert {:error, %Connection{} = after_commit} = Connection.handle_commit([], in_trx(script))
      assert after_commit.trx_id == "123"

      assert {:ok, %Response{status: 200}, %Connection{} = after_rollback} =
               Connection.handle_rollback([], after_commit)

      assert_received {:request, %Request{method: :delete, path: "/_api/transaction/123"}}
      assert after_rollback.trx_id == nil
    end

    test "a 503 during commit propagates a disconnect" do
      script = %{{:put, "/_api/transaction/123"} => @unavailable}

      assert {:disconnect, %Error{status: 503}, %Connection{}} =
               Connection.handle_commit([], in_trx(script))
    end

    test "a dead socket during commit propagates a disconnect" do
      script = %{{:put, "/_api/transaction/123"} => {:error, :closed}}

      assert {:disconnect, %Error{reason: :closed}, %Connection{}} =
               Connection.handle_commit([], in_trx(script))
    end
  end

  describe "handle_rollback/2" do
    test "no transaction in flight reports :idle and issues no request" do
      state = state(%{})

      assert {:idle, ^state} = Connection.handle_rollback([], state)
      refute_received {:request, _request}
    end

    test "a 200 rolls back, clears the header, and the request goes out without the trx header" do
      script = %{{:delete, "/_api/transaction/123"} => {200, trx_body("aborted")}}

      assert {:ok, %Response{status: 200}, %Connection{} = new_state} =
               Connection.handle_rollback([], in_trx(script))

      assert new_state.trx_id == nil

      assert_received {:request,
                       %Request{method: :delete, path: "/_api/transaction/123"} = request}

      refute Enum.any?(request.headers, fn {name, _} -> name == @trx_header end)
    end

    # The identifier leaves state only when the server
    # acknowledges the request, for rollback just as for commit.
    test "a failed rollback leaves the transaction reachable" do
      script = %{{:delete, "/_api/transaction/123"} => @conflict}

      assert {:error, %Connection{} = new_state} = Connection.handle_rollback([], in_trx(script))
      assert new_state.trx_id == "123"
    end

    test "a 503 during rollback propagates a disconnect" do
      script = %{{:delete, "/_api/transaction/123"} => @unavailable}

      assert {:disconnect, %Error{status: 503}, %Connection{}} =
               Connection.handle_rollback([], in_trx(script))
    end
  end

  describe "through DBConnection" do
    test "begin, requests carrying the trx header, and commit" do
      script = %{{:post, @begin_path} => @begin_ok}

      conn = start_pool(script)

      assert {:ok, %Response{status: 200}} =
               Arangox.transaction(conn, fn c -> Arangox.get!(c, "/inside") end)

      requests = drain_requests()

      assert [%Request{}] =
               Enum.filter(requests, &match?(%Request{method: :post, path: @begin_path}, &1))

      assert [%Request{headers: headers}] =
               Enum.filter(requests, &(&1.path == "/inside"))

      assert {@trx_header, "123"} in headers

      assert [%Request{}] =
               Enum.filter(
                 requests,
                 &match?(%Request{method: :put, path: "/_api/transaction/123"}, &1)
               )
    end

    test "nested transactions begin and commit exactly once" do
      script = %{{:post, @begin_path} => @begin_ok}

      conn = start_pool(script)

      assert {:ok, {:ok, %Response{status: 200}}} =
               Arangox.transaction(conn, fn c ->
                 Arangox.transaction(c, fn c2 -> Arangox.get!(c2, "/inner") end)
               end)

      requests = drain_requests()

      assert Enum.count(requests, &match?(%Request{method: :post, path: @begin_path}, &1)) == 1

      assert Enum.count(
               requests,
               &match?(%Request{method: :put, path: "/_api/transaction/123"}, &1)
             ) == 1

      assert [%Request{headers: headers}] =
               Enum.filter(requests, &(&1.path == "/inner"))

      assert {@trx_header, "123"} in headers
    end

    # DBConnection responds to a commit failure by calling handle_rollback,
    # so the failed commit must still name the transaction — a rollback that
    # reports :idle without a request leaks the server-side transaction until
    # it times out. The
    # rollback reaches the server and aborts the real transaction.
    test "a failed commit rolls back the real server-side transaction" do
      script = %{
        {:post, @begin_path} => @begin_ok,
        {:put, "/_api/transaction/123"} => @conflict,
        {:delete, "/_api/transaction/123"} => {200, trx_body("aborted")}
      }

      conn = start_pool(script)

      assert {:error, :rollback} = Arangox.transaction(conn, fn _c -> :work end)

      requests = drain_requests()

      assert Enum.count(
               requests,
               &match?(%Request{method: :delete, path: "/_api/transaction/123"}, &1)
             ) == 1
    end
  end

  ## The handle form

  describe "the :transaction request option" do
    test "sets the transaction header on the wire request without touching state" do
      trx = %Transaction{id: "456"}
      state = state(%{})

      assert {:ok, _echoed, %Response{}, %Connection{} = after_state} =
               Connection.handle_execute(nil, get_request(), [transaction: trx], state)

      # The no-state-write property: a checked-in connection carries nothing.
      assert after_state.trx_id == nil

      assert_received {:request, %Request{} = wire}
      assert {@trx_header, "456"} in wire.headers
    end

    test "a request without the option carries no transaction header" do
      assert {:ok, _echoed, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [], state(%{}))

      assert_received {:request, %Request{} = wire}
      refute Enum.any?(wire.headers, fn {name, _} -> name == @trx_header end)
    end

    test "per-request identity wins over a closure-form transaction in state, without altering state" do
      trx = %Transaction{id: "456"}
      state = in_trx(%{})

      assert {:ok, _echoed, %Response{}, %Connection{} = after_state} =
               Connection.handle_execute(nil, get_request(), [transaction: trx], state)

      # The closure form's transaction is still in state for its own requests.
      assert after_state.trx_id == "123"

      assert_received {:request, %Request{} = wire}
      assert {@trx_header, "456"} in wire.headers
    end

    test "combines with the dirty-read header without corrupting either" do
      trx = %Transaction{id: "456"}
      state = state(%{}, headers: [{"x-arango-allow-dirty-read", "true"}])

      assert {:ok, _echoed, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [transaction: trx], state)

      assert_received {:request, %Request{} = wire}
      assert {@trx_header, "456"} in wire.headers
      assert {"x-arango-allow-dirty-read", "true"} in wire.headers
    end

    test "a cursor created with the option carries the header (the seam covers every request path)" do
      trx = %Transaction{id: "456"}
      script = %{{:post, "/_api/cursor"} => {201, ~s({"id":"c1","hasMore":false,"result":[1]})}}

      assert {:ok, _query, "c1", %Connection{} = after_state} =
               Connection.handle_declare(
                 %Query{query: "RETURN 1"},
                 %{},
                 [transaction: trx],
                 state(script)
               )

      assert after_state.trx_id == nil

      assert_received {:request, %Request{path: "/_api/cursor"} = wire}
      assert {@trx_header, "456"} in wire.headers
    end

    test "a bare binary is rejected before reaching the wire, and never echoed" do
      assert {:error, %Error{} = error, %Connection{} = after_state} =
               Connection.handle_execute(
                 nil,
                 get_request(),
                 [transaction: "3298558923352"],
                 state(%{})
               )

      refute_received {:request, _request}
      assert after_state.trx_id == nil

      message = Exception.message(error)
      assert message =~ "%Arangox.Transaction{}"
      assert message =~ "a binary"
      refute message =~ "3298558923352"
    end

    test "an identifier containing a control character is rejected before reaching a header" do
      trx = %Transaction{id: "123\r\nx-injected: 1"}

      assert {:error, %Error{} = error, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [transaction: trx], state(%{}))

      refute_received {:request, _request}

      message = Exception.message(error)
      assert message =~ "decimal digits"
      refute message =~ "injected"
      refute inspect(error) =~ "injected"
    end

    test "empty, non-digit and non-binary identifiers are rejected" do
      for bad <- ["", "abc", "12.3", "12 3", "-1", "١٢٣", nil, 123, :id] do
        trx = %Transaction{id: bad}

        assert {:error, %Error{}, %Connection{}} =
                 Connection.handle_execute(nil, get_request(), [transaction: trx], state(%{}))
      end

      refute_received {:request, _request}
    end

    test "other non-handle values are rejected with their type named, not their value" do
      values = [
        {:some_atom, "an atom"},
        {%{id: "1"}, "a map"},
        {123, "an integer"},
        {["1"], "a list"},
        {%Request{method: :get, path: "/"}, "Arangox.Request struct"}
      ]

      for {value, described} <- values do
        assert {:error, %Error{} = error, %Connection{}} =
                 Connection.handle_execute(nil, get_request(), [transaction: value], state(%{}))

        assert Exception.message(error) =~ described
      end

      refute_received {:request, _request}
    end

    test "the echoed request redacts the identifier; the wire request carries it" do
      trx = %Transaction{id: "456"}

      assert {:ok, %Request{} = echoed, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [transaction: trx], state(%{}))

      assert {@trx_header, "[redacted]"} in echoed.headers

      assert_received {:request, %Request{} = wire}
      assert {@trx_header, "456"} in wire.headers
    end
  end

  describe "the handle form through a pool" do
    test "begin_transaction/2 returns a handle and posts the collections body" do
      conn = start_pool(%{{:post, @begin_path} => @begin_ok})

      assert {:ok, %Transaction{id: "123"}} =
               Arangox.begin_transaction(conn, write: "coll", properties: [waitForSync: true])

      assert [%Request{} = begin_request] =
               Enum.filter(drain_requests(), &(&1.path == @begin_path))

      assert Jason.decode!(begin_request.body) == %{
               "collections" => %{"write" => "coll"},
               "waitForSync" => true
             }

      refute Enum.any?(begin_request.headers, fn {name, _} -> name == @trx_header end)
    end

    test "a connection that served a handle request serves the next caller clean" do
      conn = start_pool(%{})
      trx = Transaction.new("456")

      # pool_size is 1, so the same connection serves both requests.
      assert %Response{status: 200} = Arangox.get!(conn, "/with-handle", [], transaction: trx)
      assert %Response{status: 200} = Arangox.get!(conn, "/without")

      requests = drain_requests()

      assert [%Request{headers: headers}] =
               Enum.filter(requests, &(&1.path == "/with-handle"))

      assert {@trx_header, "456"} in headers

      assert [%Request{} = clean] = Enum.filter(requests, &(&1.path == "/without"))
      refute Enum.any?(clean.headers, fn {name, _} -> name == @trx_header end)
    end

    test "after a handle-form begin, the connection carries no transaction (the state-leak property)" do
      conn = start_pool(%{{:post, @begin_path} => @begin_ok})

      assert {:ok, %Transaction{}} = Arangox.begin_transaction(conn, write: "coll")

      # An unrelated caller drawing the same pooled connection sees a clean one.
      assert %Response{status: 200} = Arangox.get!(conn, "/unrelated")

      assert [%Request{} = unrelated] = Enum.filter(drain_requests(), &(&1.path == "/unrelated"))
      refute Enum.any?(unrelated.headers, fn {name, _} -> name == @trx_header end)

      # DBConnection's own view of the checked-in connection agrees: no
      # transaction in flight, handled locally without a request.
      assert Arangox.status(conn) == :idle
    end

    test "a failed begin is an error return and the connection stays healthy" do
      conn = start_pool(%{{:post, @begin_path} => @conflict})

      assert {:error, %Error{status: 409}} = Arangox.begin_transaction(conn, write: "coll")

      # No closure-form disconnect machinery here: the next request succeeds.
      assert %Response{status: 200} = Arangox.get!(conn, "/alive")
    end

    test "a begin response without a transaction id is an error, not a crash" do
      # A success that is not a 201...
      conn = start_pool(%{})
      assert {:error, %Error{status: 200}} = Arangox.begin_transaction(conn)

      # ...and a 201 whose body names no id.
      script = %{{:post, @begin_path} => {201, ~s({"code":201,"error":false,"result":{}})}}
      conn2 = start_pool(script)
      assert {:error, %Error{status: 201}} = Arangox.begin_transaction(conn2)
    end

    test "a server-issued identifier of unexpected shape is rejected and not echoed" do
      script = %{
        {:post, @begin_path} =>
          {201, ~s({"code":201,"error":false,"result":{"id":"evil\\nid","status":"running"}})}
      }

      conn = start_pool(script)

      assert {:error, %Error{} = error} = Arangox.begin_transaction(conn)

      message = Exception.message(error)
      assert message =~ "decimal digits"
      refute message =~ "evil"
    end

    test "commit_transaction/3 addresses the transaction by path, with no transaction header" do
      script = %{
        {:post, @begin_path} => @begin_ok,
        {:put, "/_api/transaction/123"} => {200, trx_body("committed")}
      }

      conn = start_pool(script)

      assert {:ok, %Transaction{} = trx} = Arangox.begin_transaction(conn)
      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(conn, trx)

      assert [%Request{} = commit] =
               Enum.filter(
                 drain_requests(),
                 &match?(%Request{method: :put, path: "/_api/transaction/123"}, &1)
               )

      refute Enum.any?(commit.headers, fn {name, _} -> name == @trx_header end)
    end

    test "a failed commit leaves the handle usable for abort" do
      script = %{
        {:post, @begin_path} => @begin_ok,
        {:put, "/_api/transaction/123"} => @conflict,
        {:delete, "/_api/transaction/123"} => {200, trx_body("aborted")}
      }

      conn = start_pool(script)

      assert {:ok, %Transaction{} = trx} = Arangox.begin_transaction(conn)
      assert {:error, %Error{status: 409}} = Arangox.commit_transaction(conn, trx)
      assert {:ok, %Response{status: 200}} = Arangox.abort_transaction(conn, trx)
    end

    test "transaction_status/3 reads from the body, not the HTTP status" do
      trx = Transaction.new("9")

      for {body_status, expected} <- [
            {"running", :running},
            {"committed", :committed},
            {"aborted", :aborted},
            {"hibernating", "hibernating"}
          ] do
        script = %{
          {:get, "/_api/transaction/9"} =>
            {200, ~s({"code":200,"error":false,"result":{"id":"9","status":"#{body_status}"}})}
        }

        conn = start_pool(script)

        assert Arangox.transaction_status(conn, trx) == {:ok, expected}

        # The probe addresses the transaction by path; no header.
        assert [%Request{} = probe] =
                 Enum.filter(
                   drain_requests(),
                   &match?(%Request{method: :get, path: "/_api/transaction/9"}, &1)
                 )

        refute Enum.any?(probe.headers, fn {name, _} -> name == @trx_header end)
      end
    end

    test "a 200 whose body names no status is an error, not a crash" do
      conn = start_pool(%{})

      assert {:error, %Error{status: 200}} =
               Arangox.transaction_status(conn, Transaction.new("9"))
    end

    # The body is the server's data, not the caller's argument, so a shape
    # this driver does not recognize is an error tuple, never a raise.
    test "a 200 whose status is not a binary is an error, not a crash" do
      script = %{
        {:get, "/_api/transaction/9"} =>
          {200, ~s({"code":200,"error":false,"result":{"id":"9","status":3}})}
      }

      conn = start_pool(script)

      assert {:error, %Error{status: 200}} =
               Arangox.transaction_status(conn, Transaction.new("9"))
    end

    # `Arangox.start_link/1` refuses `:transaction` as a pool option; the
    # state field behind it must not be reachable under its internal name
    # either, or every caller inherits a transaction nobody began.
    test "a start option cannot preload connection state with a transaction" do
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, conn} =
          Arangox.start_link(
            client: StubClient,
            client_opts: [owner: self(), script: %{}],
            pool_size: 1,
            idle_interval: 60_000,
            trx_id: "123"
          )

        on_exit(fn -> stop_pool(conn) end)

        assert {:ok, %Response{}} = Arangox.get(conn, "/data")

        assert %Request{headers: headers} = Enum.find(drain_requests(), &(&1.path == "/data"))
        refute Enum.any?(headers, fn {name, _value} -> name == @trx_header end)
      end)
    end

    test "a handle around a malformed identifier is rejected before any request" do
      conn = start_pool(%{})

      for bad_id <- ["123abc", "123\r\nx-injected: 1", "../1", "123 456"] do
        trx = %Transaction{id: bad_id}

        assert {:error, %Error{} = error} = Arangox.commit_transaction(conn, trx)
        assert Exception.message(error) =~ "decimal digits"
        refute Exception.message(error) =~ bad_id
      end

      assert drained_transaction_requests() == []
    end

    test "both forms coexist in one pool" do
      conn = start_pool(%{{:post, @begin_path} => @begin_ok})

      assert {:ok, %Transaction{} = trx} = Arangox.begin_transaction(conn)

      assert {:ok, %Response{}} =
               Arangox.transaction(conn, fn c -> Arangox.get!(c, "/inside") end)

      assert {:ok, %Response{}} = Arangox.commit_transaction(conn, trx)

      requests = drain_requests()

      # One begin each; the closure's requests carried its own transaction.
      assert Enum.count(requests, &match?(%Request{method: :post, path: @begin_path}, &1)) == 2

      assert [%Request{headers: headers}] =
               Enum.filter(requests, &(&1.path == "/inside"))

      assert {@trx_header, "123"} in headers

      # One commit each (the closure's and the handle's).
      assert Enum.count(
               requests,
               &match?(%Request{method: :put, path: "/_api/transaction/123"}, &1)
             ) == 2
    end
  end

  describe "handle-form bang variants" do
    test "begin_transaction!/2 returns the handle" do
      conn = start_pool(%{{:post, @begin_path} => @begin_ok})

      assert %Transaction{id: "123"} = Arangox.begin_transaction!(conn, write: "coll")
    end

    test "begin_transaction!/2 raises the server's error" do
      conn = start_pool(%{{:post, @begin_path} => @conflict})

      assert_raise Error, fn -> Arangox.begin_transaction!(conn, write: "coll") end
    end

    test "commit_transaction!/3 and abort_transaction!/3 return the response or raise" do
      script = %{
        {:post, @begin_path} => @begin_ok,
        {:put, "/_api/transaction/123"} => {200, trx_body("committed")},
        {:delete, "/_api/transaction/123"} => @conflict
      }

      conn = start_pool(script)
      trx = Arangox.begin_transaction!(conn)

      assert %Response{status: 200} = Arangox.commit_transaction!(conn, trx)
      assert_raise Error, fn -> Arangox.abort_transaction!(conn, trx) end
    end

    test "transaction_status!/3 returns the bare status" do
      script = %{
        {:get, "/_api/transaction/9"} => {200, trx_body("running") |> String.replace("123", "9")}
      }

      conn = start_pool(script)

      assert Arangox.transaction_status!(conn, Transaction.new("9")) == :running
    end
  end

  describe "the handle functions accept only the struct" do
    test "a bare identifier binary raises without being echoed" do
      funs = [
        &Arangox.commit_transaction/3,
        &Arangox.abort_transaction/3,
        &Arangox.transaction_status/3
      ]

      for fun <- funs do
        error = assert_raise(ArgumentError, fn -> fun.(self(), "3298558923352", []) end)

        message = Exception.message(error)
        assert message =~ "%Arangox.Transaction{}"
        assert message =~ "a binary"
        refute message =~ "3298558923352"
      end
    end

    test "the handle functions reject a :transaction option; their transaction is already named" do
      trx = %Transaction{id: "8675309"}

      error =
        assert_raise(ArgumentError, fn ->
          Arangox.begin_transaction(self(), transaction: trx)
        end)

      assert Exception.message(error) =~ "does not accept the :transaction option"
      refute Exception.message(error) =~ "8675309"

      assert_raise(ArgumentError, fn ->
        Arangox.commit_transaction(self(), trx, transaction: trx)
      end)
    end
  end

  describe "pool-level :transaction is rejected" do
    test "start_link/1 raises without echoing the identifier" do
      trx = %Transaction{id: "8675309"}

      error = assert_raise(ArgumentError, fn -> Arangox.start_link(transaction: trx) end)

      message = Exception.message(error)
      assert message =~ "per-request"
      refute message =~ "8675309"
    end

    test "child_spec/1 raises the same" do
      assert_raise(ArgumentError, fn ->
        Arangox.child_spec(transaction: %Transaction{id: "1"})
      end)
    end
  end

  describe "redaction of the handle" do
    @describetag :redaction

    test "inspect/1 redacts the identifier like authentication material" do
      trx = %Transaction{id: "3298558923352"}

      assert inspect(trx) == ~s(#Arangox.Transaction<id: "[redacted]">)
      refute inspect(trx, limit: :infinity) =~ "3298558923352"
      refute inspect(%{nested: [trx]}, limit: :infinity) =~ "3298558923352"
    end

    test "Transaction.new/1 validates and never echoes a rejected value" do
      assert %Transaction{id: "42"} = Transaction.new("42")

      for bad <- ["12a3", "12 3", "1\r\n2", "-1", "1.5", :atom, 123, nil] do
        error = assert_raise(ArgumentError, fn -> Transaction.new(bad) end)
        message = Exception.message(error)

        assert message =~ "decimal digits"

        if is_binary(bad) do
          refute message =~ bad
        end
      end
    end

    test "the request echoed through a pool redacts the header; the wire carries it" do
      conn = start_pool(%{})
      trx = Transaction.new("456")

      assert {:ok, %Request{} = echoed, %Response{}} =
               Arangox.request(conn, :get, "/doc", "", [], transaction: trx)

      assert {@trx_header, "[redacted]"} in echoed.headers

      assert [%Request{} = wire] = Enum.filter(drain_requests(), &(&1.path == "/doc"))
      assert {@trx_header, "456"} in wire.headers
    end
  end

  describe "cross-connection application (protocol tier)" do
    test "a handle begun through one pool applies to a request served by another pool" do
      pool_a = start_pool(%{{:post, @begin_path} => @begin_ok})
      pool_b = start_pool(%{})

      assert {:ok, %Transaction{} = trx} = Arangox.begin_transaction(pool_a, write: "coll")

      # A different pool is by construction a different connection; the
      # identity travels in the value, not the connection.
      assert %Response{status: 200} = Arangox.get!(pool_b, "/via-b", [], transaction: trx)

      assert [%Request{} = wire] = Enum.filter(drain_requests(), &(&1.path == "/via-b"))
      assert {@trx_header, "123"} in wire.headers
    end
  end

  describe "against the live cluster" do
    @describetag :integration

    test "a handle begun on one connection applies through a different pooled connection to the same coordinator" do
      pool_a = cluster_pool(TestHelper.cluster_1())
      pool_b = cluster_pool(TestHelper.cluster_1())
      coll = create_collection(pool_a)

      {:ok, trx} = Arangox.begin_transaction(pool_a, write: coll)

      assert %Response{status: status} =
               Arangox.post!(pool_b, "/_api/document/#{coll}", %{_key: "doc"}, [],
                 transaction: trx
               )

      assert status in [201, 202]

      # Visible under the handle, invisible without it.
      assert %Response{status: 200} =
               Arangox.get!(pool_b, "/_api/document/#{coll}/doc", [], transaction: trx)

      assert {:error, %Error{status: 404}} = Arangox.get(pool_b, "/_api/document/#{coll}/doc")

      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(pool_b, trx)
      assert %Response{status: 200} = Arangox.get!(pool_a, "/_api/document/#{coll}/doc")
    end

    test "identity routes across coordinators in full" do
      a = cluster_pool(TestHelper.cluster_1())
      b = cluster_pool(TestHelper.cluster_2())
      c = cluster_pool(TestHelper.cluster_3())
      coll = create_collection(a)

      {:ok, trx} = Arangox.begin_transaction(a, write: coll)

      # Write through the second coordinator...
      assert %Response{status: status} =
               Arangox.post!(b, "/_api/document/#{coll}", %{_key: "doc"}, [], transaction: trx)

      assert status in [201, 202]

      # ...isolated read through the third: visible under the handle, 404
      # without it...
      assert %Response{status: 200} =
               Arangox.get!(c, "/_api/document/#{coll}/doc", [], transaction: trx)

      assert {:error, %Error{status: 404}} = Arangox.get(c, "/_api/document/#{coll}/doc")

      # ...status through the second, commit through the third.
      assert {:ok, :running} = Arangox.transaction_status(b, trx)
      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(c, trx)

      # Durable from every coordinator, no handle needed.
      for conn <- [a, b, c] do
        assert %Response{status: 200} = Arangox.get!(conn, "/_api/document/#{coll}/doc")
      end

      # The finished transaction stays queryable for a retention window.
      assert {:ok, :committed} = Arangox.transaction_status(a, trx)
    end

    test "a committed handle passed to a request returns the server's error (measured: 400/1653)" do
      a = cluster_pool(TestHelper.cluster_1())
      b = cluster_pool(TestHelper.cluster_2())
      coll = create_collection(a)

      {:ok, trx} = Arangox.begin_transaction(a, write: coll)
      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(b, trx)

      # Measured against 3.12.4: HTTP 400, errorNum 1653 ("transaction has
      # already been committed") — not a 404, and not the 400/10 a fabricated
      # identifier gets.
      assert {:error,
              %Error{status: 400, error_num: 1653, reason: :transaction_disallowed_operation}} =
               Arangox.get(a, "/_api/document/#{coll}/any", [], transaction: trx)

      # Committing again is idempotent (200)...
      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(a, trx)

      # ...but aborting a committed transaction is refused with the same errorNum.
      assert {:error, %Error{status: 400, error_num: 1653}} = Arangox.abort_transaction(b, trx)
    end

    test "aborting a handle discards the writes cluster-wide (measured: 410/1654 afterwards)" do
      a = cluster_pool(TestHelper.cluster_1())
      b = cluster_pool(TestHelper.cluster_2())
      c = cluster_pool(TestHelper.cluster_3())
      coll = create_collection(a)

      {:ok, trx} = Arangox.begin_transaction(a, write: coll)

      assert %Response{} =
               Arangox.post!(b, "/_api/document/#{coll}", %{_key: "doomed"}, [], transaction: trx)

      assert {:ok, %Response{status: 200}} = Arangox.abort_transaction(c, trx)

      for conn <- [a, b, c] do
        assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/document/#{coll}/doomed")
      end

      assert {:ok, :aborted} = Arangox.transaction_status(b, trx)

      # Measured against 3.12.4: an aborted identifier on a request is HTTP
      # 410, errorNum 1654.
      assert {:error, %Error{status: 410, error_num: 1654, reason: :transaction_aborted}} =
               Arangox.get(a, "/_api/document/#{coll}/doomed", [], transaction: trx)
    end

    test "both forms coexist in one pool; the closure form still commits on success and rolls back on raise" do
      conn = cluster_pool(TestHelper.cluster_1())
      coll = create_collection(conn)

      {:ok, trx} = Arangox.begin_transaction(conn, write: coll)

      # Closure success commits.
      assert {:ok, %Response{}} =
               Arangox.transaction(
                 conn,
                 fn c -> Arangox.post!(c, "/_api/document/#{coll}", %{_key: "closure"}) end,
                 write: coll
               )

      assert %Response{status: 200} = Arangox.get!(conn, "/_api/document/#{coll}/closure")

      # Closure raise rolls back.
      assert_raise RuntimeError, "boom", fn ->
        Arangox.transaction(
          conn,
          fn c ->
            Arangox.post!(c, "/_api/document/#{coll}", %{_key: "raised"})
            raise "boom"
          end,
          write: coll
        )
      end

      assert {:error, %Error{status: 404}} = Arangox.get(conn, "/_api/document/#{coll}/raised")

      # The handle lived through both, invisible to them, and still commits.
      assert {:ok, :running} = Arangox.transaction_status(conn, trx)

      assert %Response{} =
               Arangox.post!(conn, "/_api/document/#{coll}", %{_key: "handle"}, [],
                 transaction: trx
               )

      assert {:ok, %Response{status: 200}} = Arangox.commit_transaction(conn, trx)
      assert %Response{status: 200} = Arangox.get!(conn, "/_api/document/#{coll}/handle")
    end
  end
end
