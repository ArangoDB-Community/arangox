defmodule Arangox.Api.ClientTest do
  @moduledoc """
  The `Arangox.Api` adapter. `Arangox.Api.Client`
  is the one module through which every `Arangox.Api.*` operation reaches the
  network, translating an operation's request map into `Arangox.request/6`.

  Protocol tier: each test runs a real Mint pool against
  `Arangox.ProtocolServer` and asserts on what actually crossed the wire.
  """

  use ExUnit.Case, async: true

  alias Arangox.{Error, ProtocolServer, Response, Transaction}

  @availability "/_admin/server/availability"
  @version "/_api/version"
  @json [{"content-type", "application/json"}]
  @ok_body ~s({"error":false,"code":200})
  @version_body ~s({"server":"arango","license":"community","version":"3.12.5"})

  @not_found ~s({"error":true,"errorNum":1228,"errorMessage":"database not found","code":404})

  ## Helpers

  defp start_server!(extra) do
    routes =
      Map.merge(
        %{
          @availability => {200, @json, @ok_body},
          @version => {200, @json, @version_body}
        },
        extra
      )

    {:ok, port, server} = ProtocolServer.start(routes: routes)
    on_exit(fn -> ProtocolServer.stop(server) end)
    {"http://127.0.0.1:#{port}", server}
  end

  defp start_pool!(url) do
    {:ok, pool} =
      Arangox.start_link(
        endpoints: [url],
        client: Arangox.MintClient,
        pool_size: 1,
        backoff_min: 10,
        backoff_max: 20
      )

    on_exit(fn ->
      Process.unlink(pool)
      Process.exit(pool, :shutdown)
    end)

    pool
  end

  defp connected!(extra \\ %{}) do
    {url, server} = start_server!(extra)
    {start_pool!(url), server}
  end

  # Requests the connect probes made, filtered out so tests assert only on
  # what the adapter produced.
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

  ## The call shape

  describe "translation to the wire" do
    test "an operation's request map produces its method, path, query, and body on the wire" do
      {conn, server} =
        connected!(%{
          "/_db/mydb/_api/collection" => {200, @json, ~s({"error":false,"code":200})}
        })

      assert {:ok, %Response{status: 200, body: %{"error" => false}}} =
               Arangox.Api.Client.request(%{
                 args: [database_name: "mydb", body: %{"name" => "products"}],
                 call: {Arangox.Api.Collections, :create_collection},
                 url: "/_db/mydb/_api/collection",
                 body: %{"name" => "products"},
                 method: :post,
                 query: [waitForSyncReplication: 1],
                 request: [{"application/json", :map}],
                 response: [{200, :map}],
                 opts: [conn: conn]
               })

      assert [entry] = adapter_requests(server)
      assert entry["method"] == "POST"
      assert entry["path"] == "/_db/mydb/_api/collection"
      assert entry["query"] == "waitForSyncReplication=1"
      assert Jason.decode!(entry["body"]) == %{"name" => "products"}
    end

    # `/_api/import` takes JSON lines as `text/plain`, which the operation
    # declares in its request-media metadata. The declared type must reach the
    # wire as the request's content type, and the body must cross
    # byte-for-byte — through the JSON codec, a payload of lines becomes one
    # quoted JSON string the server cannot import.
    test "a declared non-JSON request media type sends the body raw under that content type" do
      {conn, server} =
        connected!(%{
          "/_db/mydb/_api/import" => {200, @json, @ok_body}
        })

      body = ~s({"_key":"a"}\n{"_key":"b"}\n)

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Import.import_data("mydb", body,
                 conn: conn,
                 collection: "products"
               )

      assert [entry] = adapter_requests(server)
      assert entry["body"] == body

      assert Enum.any?(entry["headers"], fn [name, value] ->
               name == "content-type" and value == "text/plain; charset=utf-8"
             end)
    end

    test "a caller's own content type is not overridden by declared media" do
      {conn, server} =
        connected!(%{
          "/_db/mydb/_api/import" => {200, @json, @ok_body}
        })

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Import.import_data("mydb", "raw",
                 conn: conn,
                 headers: [{"content-type", "text/csv"}]
               )

      assert [entry] = adapter_requests(server)

      assert Enum.any?(entry["headers"], fn [name, value] ->
               name == "content-type" and value == "text/csv"
             end)
    end

    test "a path parameter with a space or unicode is percent-encoded within its segment" do
      {conn, server} =
        connected!(%{
          "/_db/mydb/_api/collection/extended%20name/properties" => {200, @json, @ok_body}
        })

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Client.request(%{
                 args: [database_name: "mydb", collection_name: "extended name"],
                 call: {Arangox.Api.Collections, :get_collection_properties},
                 url: "/_db/mydb/_api/collection/extended name/properties",
                 method: :get,
                 response: [{200, :map}],
                 opts: [conn: conn]
               })

      assert [entry] = adapter_requests(server)
      assert entry["path"] == "/_db/mydb/_api/collection/extended%20name/properties"
    end

    test "the adapter is only the request function - no state, no lifecycle" do
      assert Arangox.Api.Client.__info__(:functions) == [request: 1]
    end

    test "a request map without a :conn raises ArgumentError" do
      assert_raise ArgumentError, ~r/:conn/, fn ->
        Arangox.Api.Client.request(%{
          args: [],
          call: {Arangox.Api.Administration, :get_version},
          url: @version,
          method: :get,
          opts: []
        })
      end
    end
  end

  ## The forced read flag

  # `get_documents/4` shares its path and method with `replace_documents/4`;
  # only `onlyget=true` on the wire makes the server read instead of replace.
  describe "get_documents/4" do
    test "sends onlyget=true in the query string" do
      {conn, server} =
        connected!(%{"/_db/mydb/_api/document/products" => {200, @json, @ok_body}})

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Documents.get_documents("mydb", "products", ["1", "2"], conn: conn)

      assert [entry] = adapter_requests(server)
      assert entry["method"] == "PUT"
      assert entry["path"] == "/_db/mydb/_api/document/products"

      # URI.decode_query/1 collapses repeated keys to the last value, so a
      # regression that put onlyget=true after an existing onlyget=false
      # instead of replacing it (e.g. appending instead of Keyword.put) would
      # still decode to %{"onlyget" => "true"} and pass unnoticed. Decoding
      # pairs keeps a duplicate key visible.
      pairs = entry["query"] |> URI.query_decoder() |> Enum.to_list()
      assert Enum.filter(pairs, fn {key, _value} -> key == "onlyget" end) == [{"onlyget", "true"}]

      assert Jason.decode!(entry["body"]) == ["1", "2"]
    end

    test "a caller's onlyget cannot override the flag, and ignoreRevs passes through" do
      {conn, server} =
        connected!(%{"/_db/mydb/_api/document/products" => {200, @json, @ok_body}})

      for override <- [false, "false", 0] do
        assert {:ok, %Response{status: 200}} =
                 Arangox.Api.Documents.get_documents("mydb", "products", ["1"],
                   conn: conn,
                   onlyget: override,
                   ignoreRevs: false
                 )
      end

      entries = adapter_requests(server)
      assert length(entries) == 3

      for entry <- entries do
        pairs = entry["query"] |> URI.query_decoder() |> Enum.to_list()
        # See the discriminating-power comment above: filtering to exactly one
        # {"onlyget", "true"} pair (not a decoded map) also catches the
        # regression this loop exists to exercise, since none of the caller
        # overrides above may add a second onlyget pair.
        assert Enum.filter(pairs, fn {key, _value} -> key == "onlyget" end) == [
                 {"onlyget", "true"}
               ]

        assert Enum.filter(pairs, fn {key, _value} -> key == "ignoreRevs" end) == [
                 {"ignoreRevs", "false"}
               ]
      end
    end
  end

  ## Bounded caller-controlled values

  describe "path parameter bounds" do
    # The operation's url already carries the raw value interpolated, so a value
    # that can alter path structure cannot be re-located and encoded after the
    # fact - it is refused, the same answer `:database` gets at the request seam.
    test "a path parameter that could alter the path is rejected before the request is built" do
      {conn, server} = connected!()

      for hostile <- ["a/b", "a?b", "a#b", "a%2Fb", "a\nb", "\0"] do
        assert {:error, %Error{message: message}} =
                 Arangox.Api.Client.request(%{
                   args: [database_name: "mydb", collection_name: hostile],
                   call: {Arangox.Api.Collections, :get_collection},
                   url: "/_db/mydb/_api/collection/#{hostile}",
                   method: :get,
                   response: [{200, :map}],
                   opts: [conn: conn]
                 })

        assert message =~ "collection_name"
      end

      assert adapter_requests(server) == []
    end
  end

  describe "query and header bounds" do
    test "a query value carrying CR, LF, or NUL is rejected before the request is built" do
      {conn, server} = connected!()

      for hostile <- ["a\rb", "a\nb", "a\0b"] do
        assert {:error, %Error{message: message}} =
                 Arangox.Api.Client.request(%{
                   args: [database_name: "mydb"],
                   call: {Arangox.Api.Queries, :list_queries},
                   url: "/_db/mydb/_api/query",
                   method: :get,
                   query: [filter: hostile],
                   response: [{200, :map}],
                   opts: [conn: conn]
                 })

        assert message =~ "filter"
      end

      assert adapter_requests(server) == []
    end

    test "a header value carrying CR, LF, or NUL is rejected before the request is built" do
      {conn, server} = connected!()

      for hostile <- ["a\rb", "a\nb", "a\0b"] do
        assert {:error, %Error{message: message}} =
                 Arangox.Api.Client.request(%{
                   args: [database_name: "mydb"],
                   call: {Arangox.Api.Documents, :get_document},
                   url: "/_db/mydb/_api/document/products/1",
                   method: :get,
                   response: [{200, :map}],
                   opts: [conn: conn, headers: [{"if-match", hostile}]]
                 })

        assert message =~ "if-match"
      end

      assert adapter_requests(server) == []
    end

    test "an operation cannot override the authorization or host the pool established" do
      {conn, server} = connected!()

      for name <- ["authorization", "Authorization", "host"] do
        assert {:error, %Error{message: message}} =
                 Arangox.Api.Client.request(%{
                   args: [database_name: "mydb"],
                   call: {Arangox.Api.Documents, :get_document},
                   url: "/_db/mydb/_api/document/products/1",
                   method: :get,
                   response: [{200, :map}],
                   opts: [conn: conn, headers: [{name, "Bearer stolen"}]]
                 })

        assert message =~ String.downcase(name)
      end

      assert adapter_requests(server) == []
    end

    test "an absolute url cannot override the pool's scheme and host" do
      {conn, server} = connected!()

      for absolute <- ["http://evil.example/_api/version", "//evil.example/_api/version"] do
        assert {:error, %Error{}} =
                 Arangox.Api.Client.request(%{
                   args: [],
                   call: {Arangox.Api.Administration, :get_version},
                   url: absolute,
                   method: :get,
                   response: [{200, :map}],
                   opts: [conn: conn]
                 })
      end

      assert adapter_requests(server) == []
    end
  end

  ## Driver semantics carried through

  describe "driver semantics" do
    test "a 404 produces the same structured error a hand-written request would" do
      {conn, _server} =
        connected!(%{"/_db/missing/_api/collection/nope" => {404, @json, @not_found}})

      assert {:error, %Error{} = api_error} =
               Arangox.Api.Client.request(%{
                 args: [database_name: "missing", collection_name: "nope"],
                 call: {Arangox.Api.Collections, :get_collection},
                 url: "/_db/missing/_api/collection/nope",
                 method: :get,
                 response: [{200, :map}, {404, {Arangox.Error, :t}}],
                 opts: [conn: conn]
               })

      {:error, %Error{} = handwritten} = Arangox.get(conn, "/_db/missing/_api/collection/nope")

      assert api_error.status == 404
      assert api_error.error_num == 1228
      assert api_error.reason == :arango_database_not_found

      assert {api_error.status, api_error.error_num, api_error.reason, api_error.message} ==
               {handwritten.status, handwritten.error_num, handwritten.reason,
                handwritten.message}
    end

    test "a transaction handle applies its header to the adapter's call" do
      {conn, server} =
        connected!(%{"/_db/mydb/_api/document/products/1" => {200, @json, @ok_body}})

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Client.request(%{
                 args: [database_name: "mydb"],
                 call: {Arangox.Api.Documents, :get_document},
                 url: "/_db/mydb/_api/document/products/1",
                 method: :get,
                 response: [{200, :map}],
                 opts: [conn: conn, transaction: %Transaction{id: "12345"}]
               })

      assert [entry] = adapter_requests(server)
      assert header(entry, "x-arango-trx-id") == "12345"
    end

    test "a per-request :database routes the call through the request seam" do
      {conn, server} = connected!(%{"/_db/mydb/_api/version" => {200, @json, @version_body}})

      assert {:ok, %Response{status: 200}} =
               Arangox.Api.Client.request(%{
                 args: [],
                 call: {Arangox.Api.Administration, :get_version},
                 url: @version,
                 method: :get,
                 response: [{200, :map}],
                 opts: [conn: conn, database: "mydb"]
               })

      assert [entry] = adapter_requests(server)
      assert entry["path"] == "/_db/mydb/_api/version"
    end

    test "a per-request :database that fails validation is rejected like the hand-written path" do
      {conn, server} = connected!()

      assert {:error, %Error{message: api_message}} =
               Arangox.Api.Client.request(%{
                 args: [],
                 call: {Arangox.Api.Administration, :get_version},
                 url: @version,
                 method: :get,
                 response: [{200, :map}],
                 opts: [conn: conn, database: "a/b"]
               })

      {:error, %Error{message: handwritten_message}} =
        Arangox.get(conn, @version, [], database: "a/b")

      assert api_message == handwritten_message
      assert adapter_requests(server) == []
    end

    test "a request timeout applies to an adapter call as it does to a hand-written one" do
      route = %{"/_db/mydb/_api/version" => {:delay, 400, {200, @json, @version_body}}}

      {conn_a, _server_a} = connected!(route)
      {conn_b, _server_b} = connected!(route)

      assert {:error, %struct_a{} = error_a} =
               Arangox.Api.Client.request(%{
                 args: [database_name: "mydb"],
                 call: {Arangox.Api.Administration, :get_version},
                 url: "/_db/mydb/_api/version",
                 method: :get,
                 response: [{200, :map}],
                 opts: [conn: conn_a, timeout: 80]
               })

      {:error, %struct_b{} = error_b} =
        Arangox.get(conn_b, "/_db/mydb/_api/version", [], timeout: 80)

      assert struct_a == struct_b
      assert Map.get(error_a, :reason) == Map.get(error_b, :reason)
    end
  end
end
