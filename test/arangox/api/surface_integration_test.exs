defmodule Arangox.Api.SurfaceIntegrationTest do
  @moduledoc """
  Spot-verification of the owned `Arangox.Api.*` surface against a live 3.12
  server. `Arangox.Api.ConformanceTest` proves every operation exists and
  speaks the document's addresses; these prove the shape is *correct* on the
  wire — one read, one write, one delete, path parameters including a value
  that needs encoding, query parameters, and an error answer. Neither
  substitutes for the other.
  """

  use ExUnit.Case

  alias Arangox.{Error, Response}

  @moduletag :integration

  setup_all do
    {:ok, conn} = Arangox.start_link(TestHelper.opts(endpoints: TestHelper.default()))
    %{conn: conn}
  end

  # One collection per run; created by the write test's setup, dropped after.
  defp with_collection(conn, fun) do
    name = "surface_spot_#{System.unique_integer([:positive])}"

    {:ok, %Response{status: 200}} =
      Arangox.Api.Collections.create_collection("_system", %{name: name}, conn: conn)

    try do
      fun.(name)
    after
      Arangox.Api.Collections.delete_collection("_system", name, conn: conn)
    end
  end

  test "a surface read returns the server's answer", %{conn: conn} do
    assert {:ok, %Response{status: 200, body: %{"server" => "arango", "version" => version}}} =
             Arangox.Api.Administration.get_version("_system", conn: conn)

    assert version =~ ~r/^3\.12\./
  end

  test "a surface write persists, a surface delete removes", %{conn: conn} do
    with_collection(conn, fn name ->
      assert {:ok, %Response{status: 202, body: %{"_key" => key}}} =
               Arangox.Api.Documents.create_document("_system", name, %{"marker" => 1},
                 conn: conn
               )

      assert {:ok, %Response{status: 200, body: %{"marker" => 1}}} =
               Arangox.Api.Documents.get_document("_system", name, key, conn: conn)

      assert {:ok, %Response{status: 202}} =
               Arangox.Api.Documents.delete_document("_system", name, key, conn: conn)

      assert {:error, %Error{status: 404}} =
               Arangox.Api.Documents.get_document("_system", name, key, conn: conn)
    end)
  end

  # get_documents shares its address with replaceDocuments; only the forced
  # onlyget=true makes it a read, so the proof is that both documents survive.
  test "get_documents/4 reads documents back by key and leaves them intact", %{conn: conn} do
    with_collection(conn, fn name ->
      {:ok, %Response{status: 202, body: %{"_key" => key_a}}} =
        Arangox.Api.Documents.create_document("_system", name, %{"marker" => "a"}, conn: conn)

      {:ok, %Response{status: 202, body: %{"_key" => key_b}}} =
        Arangox.Api.Documents.create_document("_system", name, %{"marker" => "b"}, conn: conn)

      assert {:ok, %Response{status: 200, body: bodies}} =
               Arangox.Api.Documents.get_documents("_system", name, [key_a, key_b], conn: conn)

      assert [%{"_key" => ^key_a, "marker" => "a"}, %{"_key" => ^key_b, "marker" => "b"}] =
               Enum.sort_by(bodies, & &1["marker"])

      assert {:ok, %Response{status: 200, body: %{"marker" => "a"}}} =
               Arangox.Api.Documents.get_document("_system", name, key_a, conn: conn)

      assert {:ok, %Response{status: 200, body: %{"marker" => "b"}}} =
               Arangox.Api.Documents.get_document("_system", name, key_b, conn: conn)
    end)
  end

  test "a path parameter needing encoding round-trips", %{conn: conn} do
    with_collection(conn, fn name ->
      # "@" and "=" are legal in an ArangoDB document key but are not RFC 3986
      # unreserved bytes, so the adapter must percent-encode them in the path.
      key = "spot@check=1"

      assert {:ok, %Response{status: 202}} =
               Arangox.Api.Documents.create_document(
                 "_system",
                 name,
                 %{"_key" => key, "marker" => 2},
                 conn: conn
               )

      assert {:ok, %Response{status: 200, body: %{"_key" => ^key, "marker" => 2}}} =
               Arangox.Api.Documents.get_document("_system", name, key, conn: conn)
    end)
  end

  test "a query parameter reaches the server", %{conn: conn} do
    with_collection(conn, fn name ->
      # returnNew is query-driven: without it the create answer has no "new".
      assert {:ok, %Response{status: 202, body: %{"new" => %{"marker" => 3}}}} =
               Arangox.Api.Documents.create_document("_system", name, %{"marker" => 3},
                 conn: conn,
                 returnNew: true
               )
    end)
  end

  test "a missing resource answers with the driver's structured error", %{conn: conn} do
    assert {:error, %Error{status: 404, error_num: 1203, reason: :arango_data_source_not_found}} =
             Arangox.Api.Collections.get_collection(
               "_system",
               "does_not_exist_#{System.unique_integer([:positive])}",
               conn: conn
             )
  end
end
