defmodule Arangox.ContentTypeIntegrationTest do
  @moduledoc """
  The `:content_type` option against a live 3.12 server.

  `Arangox.ContentTypeTest` pins the wire shape at the protocol tier with a
  scripted client; these prove the negotiation is real — the server accepts
  VelocyPack request bodies over HTTP, answers in VelocyPack when asked, and
  a document reads back identically through either codec.
  """

  use ExUnit.Case

  alias Arangox.Response

  @moduletag :integration

  setup_all do
    {:ok, json} = Arangox.start_link(TestHelper.opts(endpoints: TestHelper.default()))

    {:ok, vpack} =
      Arangox.start_link(
        TestHelper.opts(endpoints: TestHelper.default(), content_type: :velocypack)
      )

    %{json: json, vpack: vpack}
  end

  defp with_collection(conn, fun) do
    name = "content_type_spot_#{System.unique_integer([:positive])}"
    {:ok, %Response{status: 200}} = Arangox.post(conn, "/_api/collection", %{name: name})

    try do
      fun.(name)
    after
      Arangox.delete(conn, "/_api/collection/#{name}")
    end
  end

  test "a VelocyPack pool round-trips a document create and read", %{vpack: vpack} do
    with_collection(vpack, fn name ->
      assert {:ok, %Response{status: 202, body: %{"_key" => key}} = created} =
               Arangox.post(vpack, "/_api/document/#{name}", %{"marker" => "vpack"})

      # The negotiation was real, not silently downgraded: the server named
      # VelocyPack as the response encoding.
      assert {_, created_type} = List.keyfind(created.headers, "content-type", 0)
      assert created_type =~ "velocypack"

      assert {:ok, %Response{status: 200, body: %{"marker" => "vpack"}} = read} =
               Arangox.get(vpack, "/_api/document/#{name}/#{key}")

      assert {_, read_type} = List.keyfind(read.headers, "content-type", 0)
      assert read_type =~ "velocypack"
    end)
  end

  # JSON-representable values only: the codecs differ by design on types JSON
  # cannot carry (`%DateTime{}` is ISO-8601 text under Jason and type 0x1c
  # under velocy), so identity is only promised for the common value space.
  test "a nested document reads back identically through both codecs", %{
    json: json,
    vpack: vpack
  } do
    document = %{
      "text" => "extended näme ✓",
      "int" => -12_345_678,
      "float" => 2.5,
      "flags" => [true, false, nil],
      "nested" => %{
        "list" => Enum.to_list(1..50),
        "deep" => %{"a" => %{"b" => %{"c" => "bottom"}}}
      }
    }

    with_collection(json, fn name ->
      assert {:ok, %Response{status: 202, body: %{"_key" => key}}} =
               Arangox.post(vpack, "/_api/document/#{name}", document)

      assert {:ok, %Response{body: via_vpack}} =
               Arangox.get(vpack, "/_api/document/#{name}/#{key}")

      assert {:ok, %Response{body: via_json}} = Arangox.get(json, "/_api/document/#{name}/#{key}")

      assert Map.take(via_vpack, Map.keys(document)) == document
      assert via_json == via_vpack
    end)
  end

  # Decoding follows the response's content type, so a JSON answer under a
  # VelocyPack pool must still be read — here forced through the documented
  # per-request header override, which wins over the pool default.
  test "a JSON response under a VelocyPack pool is decoded by its own content type", %{
    vpack: vpack
  } do
    assert {:ok, _request, %Response{status: 200, body: %{"server" => "arango"}} = response} =
             Arangox.request(vpack, :get, "/_api/version", "", [{"accept", "application/json"}])

    assert {_, response_type} = List.keyfind(response.headers, "content-type", 0)
    assert response_type =~ "json"
  end
end
