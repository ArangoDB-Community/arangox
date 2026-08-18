defmodule Arangox.RequestSeamTest.StubClient do
  @moduledoc """
  A scripted `Arangox.Client` that reports the wire request to the owning test
  process as `{:request, %Arangox.Request{}}` — headers merged, path
  interpolated, body encoded — so a test can assert on the path a request left
  with, or that no request left at all.

  Scripts are keyed by `{method, path}` and travel in the fabricated socket
  inside the connection state, so there is no named process and the tests stay
  `async: true`. Anything unscripted answers `200 {}`.

  The same shape as `Arangox.TransactionTest.StubClient`, duplicated rather than
  shared: that one is the transaction suite's harness, and a stub two suites
  assert different things through is a stub neither can change.
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

defmodule Arangox.RequestSeamTest do
  @moduledoc """
  The shared request seam.

  It extracts the send-and-interpret body of `handle_execute/4` into a private
  function every internal call site reaches directly, deleting the `nil` query
  argument. The request-time half of path interpolation lives inside that
  same function: the per-request `:database` is validated and percent-encoded
  there, as is the server-supplied cursor identifier, so hand-written requests,
  cursors, prepared queries and the `Arangox.Api.*` operations all cross one
  point.

  Protocol tier: no Docker, no network — the client is scripted.
  """

  use ExUnit.Case, async: true

  alias Arangox.{Connection, Error, Query, Request, Response}
  alias Arangox.RequestSeamTest.StubClient

  @version "/_api/version"
  @availability "/_admin/server/availability"

  defp state(fields \\ []) do
    struct(
      Connection,
      [
        socket: %{owner: self(), script: Keyword.get(fields, :script, %{})},
        client: StubClient,
        endpoint: "http://stub",
        headers: [],
        cursors: %{}
      ] ++ Keyword.delete(fields, :script)
    )
  end

  defp get_request(path \\ @version), do: %Request{method: :get, path: path}

  ## Header assembly (0.8 list semantics)

  describe "header assembly:" do
    test "connection headers come first, request headers appended, duplicates intact" do
      request = %{get_request() | headers: [{"x-c", "3"}, {"x-a", "req"}]}

      assert {:ok, _req, %Response{}, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 request,
                 [],
                 state(headers: [{"x-a", "1"}, {"x-b", "2"}])
               )

      assert_received {:request, %Request{headers: headers}}
      assert headers == [{"x-a", "1"}, {"x-b", "2"}, {"x-c", "3"}, {"x-a", "req"}]
    end

    test "a :transaction option adds exactly one trx header, before the caller's headers" do
      trx = Arangox.Transaction.new("12345")
      request = %{get_request() | headers: [{"x-caller", "1"}]}

      assert {:ok, _req, %Response{}, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 request,
                 [transaction: trx],
                 state(headers: [{"x-pool", "1"}])
               )

      assert_received {:request, %Request{headers: headers}}
      assert headers == [{"x-pool", "1"}, {"x-arango-trx-id", "12345"}, {"x-caller", "1"}]
    end

    # A request that already names a transaction header — whatever the casing —
    # runs under that header alone; the connection's in-flight identifier is
    # not added next to it. Two transaction identities on one write is the
    # failure this rule exists to prevent.
    test "a request already naming a transaction header suppresses the connection's" do
      request = %{get_request() | headers: [{"X-Arango-Trx-Id", "999"}]}

      assert {:ok, _req, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, request, [], state(trx_id: "12345"))

      assert_received {:request, %Request{headers: headers}}
      assert headers == [{"X-Arango-Trx-Id", "999"}]
    end

    test "per-request headers must be a list" do
      assert_raise ArgumentError, ~r/list of \{name, value\} tuples/, fn ->
        Arangox.request(self(), :get, "/x", "", %{"x-a" => "1"})
      end
    end
  end

  describe "header entries at the request seam:" do
    # A malformed entry in a caller's header list is the caller's mistake on a
    # healthy connection: it must be refused described — the entry may carry a
    # credential — with nothing written, never raised through the callback,
    # which would retire the connection.
    test "a non-tuple header entry is refused without echoing it or crashing" do
      assert {:error, %Error{reason: :invalid_header_value} = error, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 %{get_request() | headers: [{"x-ok", "1"}, "authorization: Basic abc"]},
                 [],
                 state()
               )

      refute Exception.message(error) =~ "Basic abc"
      refute_received {:request, %Request{}}
    end
  end

  ## Validation at the shared seam

  describe "the per-request :database is validated at the seam" do
    test "a name carrying a path separator is rejected and nothing reaches the wire" do
      assert {:error, %Error{} = exception, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 get_request(),
                 [database: "app/_admin/log"],
                 state()
               )

      assert exception.message =~ ":database"
      assert exception.message =~ "/"
      refute_received {:request, %Request{}}
    end

    test "the query and fragment delimiters, the escape and control bytes are rejected" do
      for database <- ["a?b", "a#b", "a%2fb", <<"a", 0, "b">>, "a\nb", "a\x7Fb"] do
        assert {:error, %Error{}, %Connection{}} =
                 Connection.handle_execute(nil, get_request(), [database: database], state()),
               "expected #{inspect(database)} to be rejected"
      end

      refute_received {:request, %Request{}}
    end

    test "an empty name, a dot and a dot-dot are rejected" do
      for database <- ["", ".", ".."] do
        assert {:error, %Error{}, %Connection{}} =
                 Connection.handle_execute(nil, get_request(), [database: database], state()),
               "expected #{inspect(database)} to be rejected"
      end

      refute_received {:request, %Request{}}
    end

    test "a value that is not a binary is rejected" do
      assert {:error, %Error{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [database: :mydb], state())

      refute_received {:request, %Request{}}
    end

    # The same shape as an invalid `:transaction` or `:request_timeout`:
    # nothing was written, so the connection is healthy and stays checked in.
    # A disconnect here would retire a good connection over a caller's typo.
    test "the rejection leaves the connection exactly as it found it" do
      state = state()

      assert {:error, %Error{}, ^state} =
               Connection.handle_execute(nil, get_request(), [database: "a/b"], state)
    end
  end

  ## Encoding at the shared seam

  describe "values interpolated into the path are percent-encoded" do
    test "a per-request database needing encoding reaches the path encoded" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [database: "my db"], state())

      assert_received {:request, %Request{path: "/_db/my%20db/_api/version"}}
    end

    test "a unicode database name is encoded as UTF-8" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [database: "δοκιμή"], state())

      assert_received {:request, %Request{path: path}}
      assert path == "/_db/%CE%B4%CE%BF%CE%BA%CE%B9%CE%BC%CE%AE/_api/version"
    end

    test "a traditional database name is untouched" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [database: "my-db_1"], state())

      assert_received {:request, %Request{path: "/_db/my-db_1/_api/version"}}
    end

    test "the connection's own database is encoded on the same rule" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(nil, get_request(), [], state(database: "my db"))

      assert_received {:request, %Request{path: "/_db/my%20db/_api/version"}}
    end

    # A path the caller wrote themselves is not an interpolated value, so the
    # seam leaves it alone — encoding it would double-encode whatever the
    # caller already encoded.
    test "a path that already names a database is left alone" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 get_request("/_db/_system" <> @version),
                 [],
                 state(database: "other")
               )

      assert_received {:request, %Request{path: "/_db/_system/_api/version"}}
    end

    # `Arangox.start_link/1` documents the rule as "every request that isn't
    # already prepended", and does not distinguish the pool option from the
    # per-request one — prepending anyway would produce `/_db/b/_db/a/...`,
    # a path no server can answer.
    test "a per-request database does not prepend onto a path that already names one" do
      assert {:ok, _request, %Response{}, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 get_request("/_db/a" <> @version),
                 [database: "b"],
                 state()
               )

      assert_received {:request, %Request{path: "/_db/a/_api/version"}}
    end

    # Skipping the prepend must not skip the check: an option that cannot name
    # a database is refused whether or not this particular path would have used
    # it, so the same call does not start working because of where it points.
    test "the per-request database is validated even when the path already names one" do
      assert {:error, %Error{}, %Connection{}} =
               Connection.handle_execute(
                 nil,
                 get_request("/_db/a" <> @version),
                 [database: "b/c"],
                 state()
               )

      refute_received {:request, %Request{}}
    end

    test "a server-supplied cursor identifier is encoded before it reaches /_api/cursor/" do
      script = %{{:put, "/_api/cursor/c%201"} => {200, ~s({"hasMore":false,"result":[]})}}

      assert {:halt, %Response{}, %Connection{}} =
               Connection.handle_fetch(
                 %Query{query: "RETURN 1"},
                 "c 1",
                 [],
                 state(script: script)
               )

      assert_received {:request, %Request{method: :put, path: "/_api/cursor/c%201"}}
    end

    test "the cursor identifier is encoded on the deallocate path too" do
      assert {:ok, %Response{}, %Connection{}} =
               Connection.handle_deallocate(%Query{query: "RETURN 1"}, "c 1", [], state())

      assert_received {:request, %Request{method: :delete, path: "/_api/cursor/c%201"}}
    end

    test "a cursor identifier and a per-request database both reach the path encoded" do
      assert {:ok, %Response{}, %Connection{}} =
               Connection.handle_deallocate(
                 %Query{query: "RETURN 1"},
                 "c 1",
                 [database: "my db"],
                 state()
               )

      assert_received {:request, %Request{path: "/_db/my%20db/_api/cursor/c%201"}}
    end
  end

  ## Every internal call site crosses the extracted function

  describe "the internal call sites still reach their own requests" do
    test "declare posts the cursor body to the cursor collection" do
      script = %{{:post, "/_api/cursor"} => {201, ~s({"id":"c1","hasMore":false,"result":[1]})}}

      assert {:ok, %Query{}, "c1", %Connection{}} =
               Connection.handle_declare(
                 %Query{query: "RETURN 1"},
                 %{},
                 [],
                 state(script: script)
               )

      assert_received {:request, %Request{method: :post, path: "/_api/cursor"}}
    end

    test "fetch puts to the cursor it was handed" do
      script = %{{:put, "/_api/cursor/c1"} => {200, ~s({"hasMore":true,"result":[2]})}}

      assert {:cont, %Response{}, %Connection{}} =
               Connection.handle_fetch(%Query{query: "RETURN 1"}, "c1", [], state(script: script))

      assert_received {:request, %Request{method: :put, path: "/_api/cursor/c1"}}
    end

    test "deallocate deletes the cursor it was handed" do
      assert {:ok, %Response{}, %Connection{}} =
               Connection.handle_deallocate(%Query{query: "RETURN 1"}, "c1", [], state())

      assert_received {:request, %Request{method: :delete, path: "/_api/cursor/c1"}}
    end

    # `ping/1` runs in the connection process with no caller deadline, so its
    # budget is the pool's `:request_timeout` alone. `socket_timeout/3` spends
    # `Client.timeout_margin/0` and refuses to start below
    # `Client.min_socket_timeout/0`, so a `:request_timeout` under their sum
    # must not make every idle ping elapse before reaching the wire — that
    # disconnects a healthy pool once per idle interval, forever.
    test "ping survives a :request_timeout below the socket-timeout floor" do
      assert {:ok, %Connection{}} = Connection.ping(state(request_timeout: 50))
      assert_received {:request, %Request{path: @availability}}
    end

    test "ping still probes availability" do
      assert {:ok, %Connection{}} = Connection.ping(state())

      assert_received {:request, %Request{method: :get, path: @availability}}
    end
  end

  ## The VelocyStream carve-out

  # VelocyStream carries the database as a message field, not as a path
  # segment: `Arangox.VelocyClient.request/3` splits the `/_db/` prefix back
  # off and sends what it finds as the database. An encoded name would arrive
  # there percent-encoded and address a database that does not exist, so the
  # prefix stays raw for that client — it is a carrier, not a URL.
  #
  # Asserted against `interpolate_path/3` directly because the assertion is
  # about the path a VelocyStream request would carry, and reaching the wire
  # to observe it would need a VelocyStream server.
  describe "the VelocyStream client's database prefix is a carrier, not a URL" do
    test "the per-request database is not encoded for it" do
      assert {:ok, %Request{path: "/_db/my db/_api/version"}} =
               Connection.interpolate_path(
                 get_request(),
                 [database: "my db"],
                 state(client: Arangox.VelocyClient)
               )
    end

    test "it is validated for that client all the same" do
      assert {:error, %Error{}} =
               Connection.interpolate_path(
                 get_request(),
                 [database: "a/b"],
                 state(client: Arangox.VelocyClient)
               )
    end
  end
end
