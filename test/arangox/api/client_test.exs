defmodule Arangox.Api.ClientTest do
  @moduledoc """
  The `Arangox.Api` adapter: the one module through which every
  `Arangox.Api.*` operation reaches the network.

  An operation hands it a method, a list of path segments and the parameters
  it accepts; the adapter turns that into `Arangox.request/6` and turns the
  answer back into a body. These tests assert on both halves — what crossed
  the wire, and what the caller got back.

  Protocol tier: each test runs a real Mint pool against
  `Arangox.ProtocolServer`.
  """

  use ExUnit.Case, async: true

  alias Arangox.{Error, ProtocolServer, Transaction}
  alias Arangox.Api.Client

  @availability "/_admin/server/availability"
  @version "/_api/version"
  @json [{"content-type", "application/json"}]
  @ok_body ~s({"error":false,"code":200})
  @version_body ~s({"server":"arango","license":"community","version":"3.12.5"})
  @not_found ~s({"error":true,"errorNum":1202,"errorMessage":"document not found","code":404})

  ## Helpers

  defp start_server!(extra) do
    routes =
      Map.merge(
        %{@availability => {200, @json, @ok_body}, @version => {200, @json, @version_body}},
        extra
      )

    {:ok, port, server} = ProtocolServer.start(routes: routes)
    on_exit(fn -> ProtocolServer.stop(server) end)
    {"http://127.0.0.1:#{port}", server}
  end

  defp start_pool!(url, opts) do
    {:ok, pool} =
      Arangox.start_link(
        [endpoints: [url], client: Arangox.MintClient, pool_size: 1, backoff_min: 10] ++ opts
      )

    on_exit(fn ->
      Process.unlink(pool)
      Process.exit(pool, :shutdown)
    end)

    pool
  end

  defp connected!(extra \\ %{}, opts \\ []) do
    {url, server} = start_server!(extra)
    {start_pool!(url, opts), server}
  end

  defp adapter_requests(server) do
    server
    |> ProtocolServer.requests()
    |> Enum.reject(&(&1["path"] in [@availability, @version]))
  end

  defp header(entry, name) do
    Enum.find_value(entry["headers"], fn
      [^name, value] -> value
      _other -> nil
    end)
  end

  ## Translation to the wire

  describe "translation to the wire:" do
    test "method, path, query and body all arrive" do
      {conn, server} = connected!(%{"/_api/document/products" => {200, @json, ~s({"ok":true})}})

      assert {:ok, %{"ok" => true}} =
               Client.request(conn,
                 method: :post,
                 segments: ["_api", "document", "products"],
                 body: %{"a" => 1},
                 query: [wait_for_sync: "waitForSync"],
                 opts: [wait_for_sync: true]
               )

      assert [entry] = adapter_requests(server)
      assert entry["method"] == "POST"
      assert entry["path"] == "/_api/document/products"
      assert entry["query"] == "waitForSync=true"
      assert Jason.decode!(entry["body"]) == %{"a" => 1}
    end

    test "a segment carrying a space or unicode is encoded inside its own segment" do
      {conn, server} = connected!(%{"/_api/collection/a%20b%C3%A9" => {200, @json, "{}"}})

      assert {:ok, _} =
               Client.request(conn, method: :get, segments: ["_api", "collection", "a bé"])

      assert [entry] = adapter_requests(server)
      assert entry["path"] == "/_api/collection/a%20b%C3%A9"
    end

    # The old adapter refused a value carrying a separator, because the url was
    # already interpolated by the time it could be checked. Building the path
    # from segments means the separator can be encoded instead: it stays inside
    # its own segment and cannot reach the server as structure.
    test "a separator inside a segment is encoded, not treated as structure" do
      {conn, server} = connected!(%{"/_api/collection/a%2Fb%3Fc%23d" => {200, @json, "{}"}})

      assert {:ok, _} =
               Client.request(conn, method: :get, segments: ["_api", "collection", "a/b?c#d"])

      assert [entry] = adapter_requests(server)
      assert entry["path"] == "/_api/collection/a%2Fb%3Fc%23d"
      refute entry["query"] in ["c#d", "c"]
    end

    # An ArangoDB index identifier is `collection/number`, so the separator is
    # structure the server parses: percent-encoding it makes every index read
    # and delete answer 400. Only a segment declared `{:path, value}` keeps it,
    # and the parts between the separators are still encoded, so the value
    # cannot open a query or a fragment.
    test "a segment declared as a path keeps its separators and encodes the rest" do
      {conn, server} =
        connected!(%{
          "/_api/index/coll/12345" => {200, @json, "{}"},
          "/_api/index/coll/12%3F34%235" => {200, @json, "{}"}
        })

      assert {:ok, _} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "index", {:path, "coll/12345"}]
               )

      assert {:ok, _} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "index", {:path, "coll/12?34#5"}]
               )

      assert [plain, escaped] = adapter_requests(server)
      assert plain["path"] == "/_api/index/coll/12345"
      assert escaped["path"] == "/_api/index/coll/12%3F34%235"
      assert escaped["query"] == ""
    end

    test "a declared non-JSON media sends the body raw under that content type" do
      {conn, server} = connected!(%{"/_api/import" => {200, @json, "{}"}})
      body = ~s({"a":1}\n{"a":2}\n)

      assert {:ok, _} =
               Client.request(conn,
                 method: :post,
                 segments: ["_api", "import"],
                 body: body,
                 media: "text/plain; charset=utf-8"
               )

      assert [entry] = adapter_requests(server)
      assert entry["body"] == body
      assert header(entry, "content-type") == "text/plain; charset=utf-8"
    end

    test "a caller's own content type is not overridden by the declared media" do
      {conn, server} = connected!(%{"/_api/import" => {200, @json, "{}"}})

      assert {:ok, _} =
               Client.request(conn,
                 method: :post,
                 segments: ["_api", "import"],
                 body: "x",
                 media: "text/plain; charset=utf-8",
                 opts: [headers: [{"content-type", "application/x-ndjson"}]]
               )

      assert [entry] = adapter_requests(server)
      assert header(entry, "content-type") == "application/x-ndjson"
    end
  end

  ## What comes back

  describe "what comes back:" do
    test "a success answers the decoded body, not a response struct" do
      {conn, _} = connected!(%{"/_api/version" => {200, @json, ~s({"version":"3.12.10"})}})

      assert {:ok, %{"version" => "3.12.10"}} =
               Client.request(conn, method: :get, segments: ["_api", "version"])
    end

    # A 404 is an error like any other. Returning `{:ok, nil}` would make a
    # missing document indistinguishable from one that decoded to nothing.
    test "a 404 is an error carrying the status and ArangoDB's errorNum" do
      {conn, _} = connected!(%{"/_api/document/c/gone" => {404, @json, @not_found}})

      assert {:error, %Error{status: 404, error_num: 1202}} =
               Client.request(conn, method: :get, segments: ["_api", "document", "c", "gone"])
    end

    test "the bang form raises on an error and returns the body otherwise" do
      {conn, _} =
        connected!(%{
          "/_api/document/c/gone" => {404, @json, @not_found},
          "/_api/version" => {200, @json, ~s({"version":"3.12.10"})}
        })

      assert %{"version" => "3.12.10"} =
               Client.request!(conn, method: :get, segments: ["_api", "version"])

      assert_raise Error, fn ->
        Client.request!(conn, method: :get, segments: ["_api", "document", "c", "gone"])
      end
    end

    # A HEAD carries no body, so returning one would hand the caller nothing.
    # The revision lives in the etag, quoted, and the quotes are not part of it.
    test "a revision response answers the unquoted etag" do
      {url, _server} =
        start_server!(%{"/_api/document/c/k" => {200, [{"etag", "\"_hAbC123\""}], ""}})

      conn = start_pool!(url, [])

      assert {:ok, "_hAbC123"} =
               Client.request(conn,
                 method: :head,
                 segments: ["_api", "document", "c", "k"],
                 response: :revision
               )
    end
  end

  ## Forced parameters

  describe "forced parameters:" do
    # Omitting onlyget on this address turns a bulk read into a bulk replace,
    # so the adapter fixes it and a caller cannot reach it.
    test "a forced parameter is always sent and a caller cannot displace it" do
      {conn, server} = connected!(%{"/_api/document/products" => {200, @json, "[]"}})

      assert {:ok, _} =
               Client.request(conn,
                 method: :put,
                 segments: ["_api", "document", "products"],
                 body: [],
                 forced: [{"onlyget", "true"}],
                 query: [ignore_revs: "ignoreRevs"],
                 opts: [onlyget: "false", ignore_revs: true]
               )

      assert [entry] = adapter_requests(server)
      assert entry["query"] =~ "onlyget=true"
      assert entry["query"] =~ "ignoreRevs=true"
      refute entry["query"] =~ "onlyget=false"
    end
  end

  ## Bounds

  describe "bounds:" do
    test "a control character in a path segment is refused before anything is sent" do
      {conn, server} = connected!()

      assert {:error, %Error{} = error} =
               Client.request(conn, method: :get, segments: ["_api", "collection", "a\nb"])

      refute Exception.message(error) =~ "a\nb"
      assert adapter_requests(server) == []
    end

    test "a query value carrying CR, LF or NUL is refused before anything is sent" do
      {conn, server} = connected!()

      assert {:error, %Error{}} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 query: [q: "q"],
                 opts: [q: "a\r\nx: y"]
               )

      assert adapter_requests(server) == []
    end

    test "a header value carrying CR, LF or NUL is refused before anything is sent" do
      {conn, server} = connected!()

      assert {:error, %Error{}} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 opts: [headers: [{"x-custom", "a\r\nx: y"}]]
               )

      assert adapter_requests(server) == []
    end

    # The refusal names the offending header, but a name that itself carries
    # the refused bytes cannot be named without repeating them into the
    # message — and from there into whatever logs it.
    test "a header name carrying CR, LF or NUL is refused without echoing the name" do
      {conn, server} = connected!()

      assert {:error, %Error{} = error} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 opts: [headers: [{"x-bad\r\nx-injected", "v"}]]
               )

      refute Exception.message(error) =~ "\r"
      refute Exception.message(error) =~ "\n"
      assert adapter_requests(server) == []
    end

    test "an operation cannot set the authorization or host header" do
      {conn, server} = connected!()

      for name <- ["authorization", "Authorization", "host"] do
        assert {:error, %Error{message: message}} =
                 Client.request(conn,
                   method: :get,
                   segments: ["_api", "version"],
                   opts: [headers: [{name, "Bearer stolen"}]]
                 )

        assert message =~ String.downcase(name)
      end

      assert adapter_requests(server) == []
    end

    test "the :headers option must be a list of tuples" do
      {conn, _} = connected!()

      assert {:error, %Error{message: message}} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 opts: [headers: %{"x" => "1"}]
               )

      assert message =~ "list of {name, value} tuples"
    end
  end

  ## Driver semantics

  describe "driver semantics:" do
    test "the :database option routes through the driver's own prepend" do
      {conn, server} = connected!(%{"/_db/mydb/_api/version" => {200, @json, "{}"}})

      assert {:ok, _} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 opts: [database: "mydb"]
               )

      assert [entry] = adapter_requests(server)
      assert entry["path"] == "/_db/mydb/_api/version"
    end

    test "an invalid :database is refused exactly as the hand-written path refuses it" do
      {conn, server} = connected!()

      assert {:error, %Error{message: message}} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "version"],
                 opts: [database: "a/b"]
               )

      assert message =~ ":database"
      assert adapter_requests(server) == []
    end

    test "a transaction handle applies its header to the adapter's call" do
      {conn, server} = connected!(%{"/_api/collection" => {200, @json, "{}"}})
      trx = %Transaction{id: "456"}

      assert {:ok, _} =
               Client.request(conn,
                 method: :get,
                 segments: ["_api", "collection"],
                 opts: [transaction: trx]
               )

      assert [entry] = adapter_requests(server)
      assert header(entry, "x-arango-trx-id") == "456"
    end

    test "a request timeout applies as it does to a hand-written request" do
      {conn, _} = connected!(%{"/hang" => :hang})

      assert {:error, %Error{reason: :timeout}} =
               Client.request(conn,
                 method: :get,
                 segments: ["hang"],
                 opts: [request_timeout: 200, timeout: 400]
               )
    end

    test "the adapter is only the request function - no state, no lifecycle" do
      exports = Client.__info__(:functions) |> Keyword.keys() |> Enum.uniq() |> Enum.sort()
      assert exports == [:request, :request!]
    end
  end
end
