defmodule Arangox.Api.SurfaceIntegrationTest do
  @moduledoc """
  Spot-verification of the owned `Arangox.Api.*` surface against a live 3.12
  server. `Arangox.Api.ConformanceTest` proves every operation exists and
  addresses what the server describes; these prove the shape is *correct* on
  the wire — one read, one write, one delete, a path parameter that needs
  encoding, a query parameter, the revision a `HEAD` answers, and an error.
  Neither substitutes for the other.
  """

  use ExUnit.Case

  alias Arangox.Api.{Administration, Collections, Documents}
  alias Arangox.Error

  @moduletag :integration

  setup_all do
    {:ok, conn} = Arangox.start_link(TestHelper.opts(endpoints: TestHelper.default()))
    %{conn: conn}
  end

  defp with_collection(conn, fun) do
    name = "surface_spot_#{System.unique_integer([:positive])}"
    {:ok, _} = Collections.create(conn, %{name: name})

    try do
      fun.(name)
    after
      Collections.delete(conn, name)
    end
  end

  test "a read answers the decoded body, not a response struct", %{conn: conn} do
    assert {:ok, %{"server" => "arango", "version" => version}} = Administration.version(conn)
    assert version =~ ~r/^3\.12\./
  end

  test "a write persists and a delete removes", %{conn: conn} do
    with_collection(conn, fn name ->
      assert {:ok, %{"_key" => key}} = Documents.create(conn, name, %{"marker" => 1})
      assert {:ok, %{"marker" => 1}} = Documents.get(conn, name, key)
      assert {:ok, _} = Documents.delete(conn, name, key)
      assert {:error, %Error{status: 404}} = Documents.get(conn, name, key)
    end)
  end

  test "a missing resource answers the driver's structured error", %{conn: conn} do
    assert {:error, %Error{status: 404, error_num: error_num}} =
             Collections.get(conn, "surface_spot_absent")

    assert is_integer(error_num)
  end

  test "the bang form raises that same error", %{conn: conn} do
    assert_raise Error, fn -> Collections.get!(conn, "surface_spot_absent") end
  end

  # A key ArangoDB accepts but a URL does not carry literally. Encoding it per
  # segment is what lets it round-trip.
  test "a path parameter needing encoding round-trips", %{conn: conn} do
    with_collection(conn, fn name ->
      key = "a:b+c(d)e@f,g=h"
      assert {:ok, %{"_key" => ^key}} = Documents.create(conn, name, %{"_key" => key})
      assert {:ok, %{"_key" => ^key}} = Documents.get(conn, name, key)
    end)
  end

  test "a query parameter written in snake_case reaches the server", %{conn: conn} do
    with_collection(conn, fn name ->
      assert {:ok, %{"new" => %{"marker" => 2}}} =
               Documents.create(conn, name, %{"marker" => 2}, return_new: true)

      assert {:ok, created} = Documents.create(conn, name, %{"marker" => 3})
      refute Map.has_key?(created, "new")
    end)
  end

  # The whole value of a HEAD is the revision, which arrives in the etag.
  test "a HEAD answers the document revision", %{conn: conn} do
    with_collection(conn, fn name ->
      assert {:ok, %{"_key" => key, "_rev" => rev}} =
               Documents.create(conn, name, %{"marker" => 4}, return_new: false)

      assert {:ok, ^rev} = Documents.header(conn, name, key)
    end)
  end

  # Omitting onlyget on this address would replace the collection instead of
  # reading from it. The adapter forces it, so the documents must survive.
  test "get_many reads by key and leaves the documents intact", %{conn: conn} do
    with_collection(conn, fn name ->
      {:ok, _} = Documents.create(conn, name, %{"_key" => "a", "marker" => 1})
      {:ok, _} = Documents.create(conn, name, %{"_key" => "b", "marker" => 2})

      assert {:ok, read} = Documents.get_many(conn, name, [%{"_key" => "a"}, %{"_key" => "b"}])
      assert length(read) == 2

      assert {:ok, %{"marker" => 1}} = Documents.get(conn, name, "a")
      assert {:ok, %{"marker" => 2}} = Documents.get(conn, name, "b")
    end)
  end

  # The database is an option now rather than a positional argument, and it
  # falls back to the pool's own setting when absent.
  test "the :database option selects the database", %{conn: conn} do
    assert {:ok, %{"result" => %{"name" => "_system"}}} =
             Arangox.Api.Databases.current(conn, database: "_system")

    assert {:error, %Error{status: 404}} =
             Arangox.Api.Databases.current(conn, database: "no_such_database")
  end
end
