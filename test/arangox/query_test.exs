defmodule Arangox.QueryTest.StubClient do
  @moduledoc """
  A scripted `Arangox.Client` for the AQL query tests.

  Reports every wire request to the owning test process as
  `{:request, %Arangox.Request{}}`, so a test can assert on the body a query
  built or on the sequence of paths a cursor drove.

  A script value may be a **list** of responses, which the client serves in
  order and then repeats the last one. That is what makes a multi-batch drain
  assertable: `PUT /_api/cursor/c1` has to respond differently the second time.
  The cursor into that list lives in an unnamed `Agent` carried in the
  fabricated socket, so the tests stay `async: true`.
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

    case next(socket, {request.method, request.path}) do
      {:error, reason} ->
        {:error, %Error{reason: reason, message: "scripted #{inspect(reason)}"}, state}

      {status, body} ->
        {:ok, %Response{status: status, headers: [], body: body}, state}
    end
  end

  @impl true
  def close(%Connection{}), do: :ok

  defp next(socket, key) do
    case Map.get(socket.script, key, {200, "{}"}) do
      replies when is_list(replies) ->
        Agent.get_and_update(socket.seq, fn taken ->
          index = Map.get(taken, key, 0)
          {Enum.at(replies, index, List.last(replies)), Map.put(taken, key, index + 1)}
        end)

      reply ->
        reply
    end
  end
end

defmodule Arangox.QueryTest do
  @moduledoc """
  AQL queries.

  Protocol tier: no Docker, no network — the client is scripted. The scenarios
  that need a real server (plan-cache keys, the version gate, the management
  endpoints) belong to the unit's later stage and are not here.
  """

  use ExUnit.Case, async: true

  import TestHelper, only: [stop_pool: 1]

  import ExUnit.CaptureLog

  alias Arangox.{Connection, Error, Query, Request, Response}
  alias Arangox.QueryTest.StubClient

  @cursor "/_api/cursor"
  @version "/_api/version"

  # The connect pipeline reads the server version, and the plan-cache gate fails closed
  # without one. Unless a test says otherwise, the scripted server is new enough
  # for the plan cache.
  @version_body Jason.encode!(%{
                  "server" => "arango",
                  "license" => "community",
                  "version" => "3.12.10"
                })

  defp state(script \\ %{}, fields \\ []) do
    {:ok, seq} = Agent.start_link(fn -> %{} end)

    struct(
      Connection,
      [
        socket: %{owner: self(), script: script, seq: seq},
        client: StubClient,
        endpoint: "http://stub",
        headers: [],
        cursors: %{},
        server_version: Version.parse!("3.12.10")
      ] ++ fields
    )
  end

  defp start_pool(script \\ %{}) do
    {:ok, seq} = Agent.start_link(fn -> %{} end)
    script = Map.put_new(script, {:get, @version}, {200, @version_body})

    {:ok, conn} =
      Arangox.start_link(
        client: StubClient,
        client_opts: [owner: self(), script: script, seq: seq],
        pool_size: 1,
        idle_interval: 60_000
      )

    on_exit(fn -> stop_pool(conn) end)

    conn
  end

  defp query(text, opts \\ []), do: %Query{query: text, opts: opts}

  # The body as it went on the wire, already JSON-encoded by the connection.
  defp sent_body(%Request{body: body}), do: Jason.decode!(body)

  defp one_batch(rows), do: {201, Jason.encode!(%{"result" => rows, "hasMore" => false})}

  ## Steps 2 and 3: the struct, its protocol implementation, and execute

  describe "a query" do
    # The refusal is the documentation: ArangoDB has no prepared statements,
    # and the error says what to reach for instead.
    test "prepare is refused, and the error names the option that replaces it" do
      assert {:error, %Error{} = exception, %Connection{}} =
               Connection.handle_prepare(query("RETURN 1"), [], state())

      assert exception.message =~ "use_plan_cache"
      assert exception.message =~ "no prepared statements"
      refute_received {:request, %Request{}}
    end

    test "so is preparing anything else" do
      assert {:error, %Error{}, %Connection{}} =
               Connection.handle_prepare(%Request{method: :get, path: "/x"}, [], state())
    end

    test "executing returns the query struct itself, not a request" do
      conn = start_pool(%{{:post, @cursor} => one_batch([1])})
      q = query("RETURN 1")

      assert {:ok, ^q, %Response{}} = DBConnection.execute(conn, q, %{})
    end

    test "the caller gets the rows the server returned" do
      conn = start_pool(%{{:post, @cursor} => one_batch([1, 2, 3])})

      assert {:ok, %Response{body: %{"result" => [1, 2, 3]}}} =
               Arangox.query(conn, "RETURN 1..3", %{})
    end

    test "bind variables are sent under the server's key, never in the query text" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      assert {:ok, %Response{}} = Arangox.query(conn, "RETURN @n", %{n: 2})

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      body = sent_body(wire)

      assert body["bindVars"] == %{"n" => 2}
      assert body["query"] == "RETURN @n"
      refute body["query"] =~ "2"
    end
  end

  ## Close

  describe "closing" do
    test "a query struct is a no-op that issues no request" do
      q = query("RETURN 1")

      assert {:ok, :noop, %Connection{}} = Connection.handle_close(q, [], state())
      refute_received {:request, %Request{}}
    end

    test "anything else still returns the documented unsupported error" do
      assert {:error, %Error{} = exception, %Connection{}} =
               Connection.handle_close(%Request{method: :get, path: "/_api/version"}, [], state())

      assert exception.message =~ "Arangox.Query"
    end

    # DBConnection calls close for whatever it was handed whenever describe or
    # encode raises, so the clause has to return for types this driver never
    # produces rather than raising a second error over the first.
    test "a value this driver never produces does not raise a function-clause error" do
      assert {:error, %Error{}, %Connection{}} = Connection.handle_close(:nonsense, [], state())
    end
  end

  ## The option mapping

  describe "AQL options" do
    defp body_for(opts) do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      assert {:ok, %Response{}} = Arangox.query(conn, query("RETURN 1", opts), %{})

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      sent_body(wire)
    end

    test "snake_case names map to the server's top-level keys" do
      body = body_for(batch_size: 10, count: true, memory_limit: 1024, ttl: 30)

      assert body["batchSize"] == 10
      assert body["count"] == true
      assert body["memoryLimit"] == 1024
      assert body["ttl"] == 30
    end

    test "options the server nests are nested under its options key" do
      body = body_for(full_count: true, max_number_of_plans: 3, profile: 2)

      assert body["options"]["fullCount"] == true
      assert body["options"]["maxNumberOfPlans"] == 3
      assert body["options"]["profile"] == 2
      refute Map.has_key?(body, "fullCount")
    end

    # The one name in the server's schema that a snake_case-to-camelCase
    # transform gets wrong: it would produce `maxDnfConditionMembers`.
    test "a name whose casing is not mechanical still maps correctly" do
      assert body_for(max_dnf_condition_members: 8)["options"]["maxDNFConditionMembers"] == 8
    end

    test "an unknown option is refused rather than sent as an invented key" do
      conn = start_pool()

      assert {:error, %Error{} = exception} =
               Arangox.query(conn, query("RETURN 1", bacth_size: 10), %{})

      assert exception.message =~ ":bacth_size"
      refute_received {:request, %Request{method: :post, path: @cursor}}
    end

    test "the :properties escape hatch still passes camelCase through verbatim" do
      assert body_for(properties: [batchSize: 1])["batchSize"] == 1
    end

    test "the escape hatch has the last word over a mapped option" do
      assert body_for(batch_size: 10, properties: [batchSize: 1])["batchSize"] == 1
    end
  end

  ## The plan-cache option

  describe "the plan cache option" do
    # The server refuses to cache some statements outright — an UPSERT is
    # refused with 1584 — and the driver gates the option on server version. Sending it
    # uninvited would hand both of those to a caller who never asked.
    test "a query does not ask for the cache unless told to" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      assert {:ok, %Response{}} = Arangox.query(conn, "RETURN 1", %{})

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      refute get_in(sent_body(wire), ["options", "usePlanCache"])
    end

    test "a query can ask for it outright" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      assert {:ok, %Response{}} = Arangox.query(conn, "RETURN 1", %{}, use_plan_cache: true)

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      assert sent_body(wire)["options"]["usePlanCache"] == true
    end

    test "a streamed cursor does not ask for the cache either" do
      script = %{{:post, @cursor} => {201, Jason.encode!(%{"result" => [], "hasMore" => false})}}

      assert {:ok, _query, _cursor, %Connection{}} =
               Connection.handle_declare(query("RETURN 1"), %{}, [], state(script))

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      refute get_in(sent_body(wire), ["options", "usePlanCache"])
    end
  end

  ## Driver-local cursors

  # A cursor-create reply carries an id only when more batches follow; a
  # single-batch result has no id and exists nowhere on the server. The driver
  # keys it under a reference, and a reference must never reach the wire.
  describe "a cursor the server issued no id for" do
    test "is keyed under a reference" do
      script = %{{:post, @cursor} => one_batch([1, 2])}

      assert {:ok, %Query{}, cursor, %Connection{}} =
               Connection.handle_declare(query("RETURN 1"), %{}, [], state(script))

      assert is_reference(cursor)
    end

    test "abandoned before its batch is delivered, deallocate stays local" do
      script = %{{:post, @cursor} => one_batch([1])}

      assert {:ok, %Query{}, cursor, %Connection{} = state} =
               Connection.handle_declare(query("RETURN 1"), %{}, [], state(script))

      assert_receive {:request, %Request{method: :post, path: @cursor}}

      assert {:ok, :noop, %Connection{}} = Connection.handle_deallocate(nil, cursor, [], state)
      refute_received {:request, %Request{method: :delete}}
    end

    test "a fetch that misses its stored batch is served locally, not from the wire" do
      assert {:error, %Arangox.Error{}, %Connection{}} =
               Connection.handle_fetch(nil, make_ref(), [], state())

      refute_received {:request, %Request{}}
    end
  end

  describe "a cursor-create reply promising more batches without an id" do
    # Unaddressable: no request can ever name the batches the server is
    # holding back, so streaming would deliver the first batch and then have
    # nowhere to go.
    test "is refused at declare" do
      script = %{
        {:post, @cursor} => {201, Jason.encode!(%{"result" => [1], "hasMore" => true})}
      }

      assert {:error, %Arangox.Error{} = error, %Connection{}} =
               Connection.handle_declare(query("RETURN 1"), %{}, [], state(script))

      assert Exception.message(error) =~ "id"
    end
  end

  ## The version gate

  describe "the plan cache's version floor" do
    defp gated(version) do
      Connection.handle_execute(
        query("RETURN 1", use_plan_cache: true),
        %{},
        [],
        state(%{}, server_version: version)
      )
    end

    test "a server below the floor is refused, and the error names the version" do
      assert {:error, %Error{} = exception, %Connection{}} = gated(Version.parse!("3.12.3"))

      assert exception.message =~ "3.12.4"
      assert exception.message =~ "3.12.3"
      refute_received {:request, %Request{path: @cursor}}
    end

    # Exercised below the floor on both sides of the 3.11/3.12 line, because a
    # gate that only knew about 3.11 would pass every 3.12 patch that predates
    # the option.
    test "a 3.11 server is refused on the same rule" do
      assert {:error, %Error{}, %Connection{}} = gated(Version.parse!("3.11.14"))
      refute_received {:request, %Request{path: @cursor}}
    end

    test "the floor itself is allowed through" do
      assert {:ok, %Query{}, %Response{}, %Connection{}} = gated(Version.parse!("3.12.4"))
      assert_receive {:request, %Request{method: :post, path: @cursor}}
    end

    # Fails closed. An unparseable version means the check cannot be made, and
    # below the floor the option is ignored rather than refused, so guessing
    # risks running uncached without saying so.
    # `:properties` passes attributes through under the server's own names, so
    # this asks for the plan cache exactly as `use_plan_cache: true` does. An
    # atom-only lookup missed it, and the request then reached a server that
    # ignores the option silently — the outcome the gate exists to prevent.
    test "a request written with the server's key names is gated too" do
      result =
        Connection.handle_execute(
          query("RETURN 1", properties: %{"options" => %{"usePlanCache" => true}}),
          %{},
          [],
          state(%{}, server_version: Version.parse!("3.11.14"))
        )

      assert {:error, %Error{} = exception, %Connection{}} = result
      assert exception.message =~ "3.12.4"
      refute_received {:request, %Request{path: @cursor}}
    end

    # A mapped option writes `:options` while `:properties` merges `"options"`
    # verbatim, so one body carries both containers and the flag may be in
    # either. Looking only at the first one present missed it.
    test "a mapped option beside a server-keyed plan-cache request is still gated" do
      result =
        Connection.handle_execute(
          query("RETURN 1",
            full_count: true,
            properties: %{"options" => %{"usePlanCache" => true}}
          ),
          %{},
          [],
          state(%{}, server_version: Version.parse!("3.11.14"))
        )

      assert {:error, %Error{} = exception, %Connection{}} = result
      assert exception.message =~ "3.12.4"
      refute_received {:request, %Request{path: @cursor}}
    end

    test "an unknown version is refused rather than optimistically allowed" do
      assert {:error, %Error{} = exception, %Connection{}} = gated(nil)

      assert exception.message =~ "could not be determined"
      refute_received {:request, %Request{path: @cursor}}
    end

    test "a query that did not ask is untouched by the floor" do
      assert {:ok, %Query{}, %Response{}, %Connection{}} =
               Connection.handle_execute(
                 query("RETURN 1"),
                 %{},
                 [],
                 state(%{}, server_version: Version.parse!("3.11.14"))
               )

      assert_receive {:request, %Request{method: :post, path: @cursor}}
    end

    test "a streamed cursor asking for it is gated too" do
      assert {:error, %Error{}, %Connection{}} =
               Connection.handle_declare(
                 query("RETURN 1", use_plan_cache: true),
                 %{},
                 [],
                 state(%{}, server_version: Version.parse!("3.11.14"))
               )

      refute_received {:request, %Request{path: @cursor}}
    end

    # The gate reads what is about to be sent, not how the option was spelled,
    # so the escape hatch cannot route around it.
    test "asking through :properties is gated on the same rule" do
      assert {:error, %Error{}, %Connection{}} =
               Connection.handle_execute(
                 query("RETURN 1", properties: [options: %{usePlanCache: true}]),
                 %{},
                 [],
                 state(%{}, server_version: Version.parse!("3.11.14"))
               )

      refute_received {:request, %Request{path: @cursor}}
    end
  end

  ## Draining

  describe "draining batches inside the request path" do
    test "every row is returned, not just the first batch" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} => [
          {200, Jason.encode!(%{"result" => [2], "hasMore" => true, "id" => "c1"})},
          {200, Jason.encode!(%{"result" => [3], "hasMore" => false, "id" => "c1"})}
        ]
      }

      conn = start_pool(script)

      assert {:ok, %Response{body: body}} = Arangox.query(conn, "RETURN 1..3", %{})

      assert body["result"] == [1, 2, 3]
      assert body["hasMore"] == false
    end

    test "the drain leaves no cursor to delete — the server closed it" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} =>
          {200, Jason.encode!(%{"result" => [2], "hasMore" => false, "id" => "c1"})}
      }

      conn = start_pool(script)

      assert {:ok, %Response{}} = Arangox.query(conn, "RETURN 1..2", %{})

      assert_receive {:request, %Request{method: :post}}
      assert_receive {:request, %Request{method: :put}}
      refute_received {:request, %Request{method: :delete}}
    end

    test "a failure mid-drain surfaces as an error rather than a truncated result" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} => {:error, :econnreset}
      }

      conn = start_pool(script)

      assert {:error, %Error{}} = Arangox.query(conn, "RETURN 1..2", %{})
    end
  end

  ## The one-shot door

  describe "query/4" do
    test "returns the drained response rather than a cursor to read" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} => {200, Jason.encode!(%{"result" => [2], "hasMore" => false})}
      }

      assert {:ok, %Response{body: %{"result" => [1, 2]}}} =
               Arangox.query(start_pool(script), "RETURN 1..2", %{})
    end

    test "takes a query struct and the options it carries" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      assert {:ok, %Response{}} = Arangox.query(conn, query("RETURN 1", batch_size: 7), %{})

      assert_receive {:request, %Request{method: :post, path: @cursor} = wire}
      assert sent_body(wire)["batchSize"] == 7
    end

    test "the bang variant raises the error the other returns" do
      conn = start_pool(%{{:post, @cursor} => {:error, :econnreset}})

      assert_raise Error, fn -> Arangox.query!(conn, "RETURN 1", %{}) end
    end

    # The hard refusal only covers options carried by the query, because the
    # call's option list is shared with DBConnection and cannot be enumerated.
    # A near-miss of a name this driver does know is the part it can speak to.
    test "an option that is nearly a known one is warned about" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      log =
        capture_log(fn ->
          assert {:ok, %Response{}} = Arangox.query(conn, "RETURN 1", %{}, bacth_size: 10)
        end)

      assert log =~ ":bacth_size"
      assert log =~ ":batch_size"
    end

    test "an option it cannot know about passes without comment" do
      conn = start_pool(%{{:post, @cursor} => one_batch([])})

      log =
        capture_log(fn ->
          assert {:ok, %Response{}} =
                   Arangox.query(conn, "RETURN 1", %{}, some_future_pool_opt: 1)
        end)

      refute log =~ "some_future_pool_opt"
    end
  end

  ## The cursor callbacks and the removed BitString impl

  describe "streaming" do
    test "a binary still streams after the global protocol implementation is gone" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => false, "id" => "c1"})}
      }

      conn = start_pool(script)

      rows =
        Arangox.run(conn, fn c ->
          c
          |> Arangox.cursor("RETURN 1", %{})
          |> Enum.reduce([], fn response, acc -> acc ++ response.body["result"] end)
        end)

      assert rows == [1]
    end

    test "a query struct drives declare, fetch and deallocate" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} =>
          {200, Jason.encode!(%{"result" => [2], "hasMore" => false, "id" => "c1"})}
      }

      conn = start_pool(script)

      rows =
        Arangox.run(conn, fn c ->
          c
          |> Arangox.cursor(query("RETURN 1..2"), %{})
          |> Enum.reduce([], fn response, acc -> acc ++ response.body["result"] end)
        end)

      assert rows == [1, 2]
      assert_receive {:request, %Request{method: :post, path: @cursor}}
      assert_receive {:request, %Request{method: :put, path: "/_api/cursor/c1"}}
    end

    # Stopping early is the only case where a server-side cursor is still
    # standing when the stream ends. A drained one is already gone — the server
    # drops it on delivery of the last batch and responds `cursor not found` for
    # it afterwards — so `handle_deallocate/4`'s DELETE has something to delete
    # here and nowhere else. That also makes this the only path where getting
    # the fetch bookkeeping wrong leaks a cursor rather than merely erroring.
    test "stopping a stream early deletes the cursor the server is still holding" do
      script = %{
        {:post, @cursor} =>
          {201, Jason.encode!(%{"result" => [1], "hasMore" => true, "id" => "c1"})},
        {:put, @cursor <> "/c1"} =>
          {200, Jason.encode!(%{"result" => [2], "hasMore" => true, "id" => "c1"})}
      }

      conn = start_pool(script)

      rows =
        Arangox.run(conn, fn c ->
          c
          |> Arangox.cursor(query("FOR i IN 1..100 RETURN i"), %{})
          |> Enum.take(1)
          |> Enum.flat_map(& &1.body["result"])
        end)

      assert rows == [1]

      assert_receive {:request, %Request{method: :post, path: @cursor}}
      assert_receive {:request, %Request{method: :delete, path: "/_api/cursor/c1"}}

      # Laziness, asserted from the other side: the batch the caller never asked
      # for was never fetched.
      refute_received {:request, %Request{method: :put}}
    end

    # Guards a regression class: a `with` whose `else` matches its
    # own head's success shapes lets a batch response with no `hasMore` key
    # fall to a bare `error -> error` clause, forwarding `handle_execute/4`'s
    # four-tuple where DBConnection expects `{:cont | :halt, result, state}`.
    test "a batch response with no hasMore key halts instead of leaking a four-tuple" do
      script = %{{:put, @cursor <> "/c1"} => {200, Jason.encode!(%{"result" => [1]})}}

      assert {:halt, %Response{}, %Connection{}} =
               Connection.handle_fetch(query("RETURN 1"), "c1", [], state(script))
    end
  end

  ## The plan-cache listing's response shape

  # The listing's contract is a list of entries. A body of any other shape —
  # an error envelope behind a 200, a body left undecoded — must be an error,
  # not wrapped into a one-entry list of something that is not an entry.
  test "a plan-cache body that is not a list is an error, not an invented entry" do
    conn =
      start_pool(%{{:get, "/_api/query-plan-cache"} => {200, ~s({"error":false,"code":200})}})

    assert {:error, %Error{status: 200}} = Arangox.plan_cache(conn)
    assert_raise Error, fn -> Arangox.plan_cache!(conn) end
  end

  ## Live: the cache key and the management endpoints

  @tag :integration
  test "the plan cache round-trips: key on the response, entry in the listing, cleared" do
    {:ok, conn} = Arangox.start_link(endpoints: "http://localhost:8529", pool_size: 1)
    on_exit(fn -> stop_pool(conn) end)

    :ok = Arangox.clear_plan_cache(conn)
    assert {:ok, []} = Arangox.plan_cache(conn)

    statement = "FOR i IN 1..3 FILTER i != @skip RETURN i"
    q = query(statement, use_plan_cache: true)

    # The first execution populates the entry, so it is served from nothing and
    # carries no key. The second is served from the cache and names it.
    assert {:ok, %Response{} = first} = Arangox.query(conn, q, %{skip: 2})
    assert Response.plan_cache_key(first) == nil

    assert {:ok, %Response{} = second} = Arangox.query(conn, q, %{skip: 2})
    key = Response.plan_cache_key(second)
    assert is_binary(key)

    # The listing holds the entry that key identifies.
    assert {:ok, entries} = Arangox.plan_cache(conn)
    assert entry = Enum.find(entries, &(&1["hash"] == key))
    assert entry["query"] == statement

    :ok = Arangox.clear_plan_cache(conn)
    assert {:ok, []} = Arangox.plan_cache(conn)
  end

  # The version gate against a live server below the floor, which is the case the unit tests
  # can only simulate: the 3.11 member of the active-failover trio.
  @tag integration: :arango_3_11
  test "a live server below the floor refuses a query that asks for the cache" do
    {:ok, conn} =
      Arangox.start_link(
        endpoints: ["http://localhost:8003", "http://localhost:8004", "http://localhost:8005"],
        auth: {:basic, "root", ""},
        endpoint_mapper: %{
          "http://localhost:8529" => "http://localhost:8003",
          "http://localhost:8539" => "http://localhost:8004",
          "http://localhost:8549" => "http://localhost:8005"
        },
        pool_size: 1
      )

    on_exit(fn -> stop_pool(conn) end)

    assert {:error, %Error{} = exception} =
             Arangox.query(conn, query("RETURN 1", use_plan_cache: true), %{})

    assert exception.message =~ "3.12.4"

    # The same statement without the option runs, which is what keeps this tier
    # usable rather than gated wholesale.
    assert {:ok, %Response{body: %{"result" => [1]}}} = Arangox.query(conn, "RETURN 1", %{})
  end

  ## Live: what the server is actually left holding

  @tag :integration
  test "stopping a stream early removes the cursor from the server" do
    {:ok, conn} = Arangox.start_link(endpoints: "http://localhost:8529", pool_size: 1)
    on_exit(fn -> stop_pool(conn) end)

    id =
      Arangox.run(conn, fn c ->
        c
        |> Arangox.cursor("FOR i IN 1..100 RETURN i", %{}, batch_size: 2)
        |> Enum.take(1)
        |> hd()
        |> then(& &1.body["id"])
      end)

    assert is_binary(id), "the server should still hold a cursor after one batch of a hundred"

    # The stub proves a DELETE was sent. This proves it landed: the server no
    # longer knows the cursor, which is the leak the deallocate exists to avoid.
    assert {:error, %Error{status: 404, reason: :cursor_not_found}} =
             Arangox.put(conn, "/_api/cursor/#{id}", "")
  end
end
