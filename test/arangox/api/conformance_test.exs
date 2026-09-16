defmodule Arangox.API.ConformanceTest do
  @moduledoc """
  The live gate over the owned `Arangox.API.*` surface.

  The operations are hand-maintained source with no generator behind them, so
  nothing re-derives them when the server moves. This gate fetches the API
  description the tested server itself serves and compares the surface against
  it, which is why it is the authority: a vendored copy of that description can
  drift from the server it claims to describe, but the live oracle and the
  system under test cannot disagree about which release they are.

  It asserts the server's version equals the driver's single pinned version
  first, so a mismatch is reported as a pin problem rather than as surface
  drift.

  ## Addresses are compared as sets, not one-to-one

  The description lists several operations at one address, distinguished only
  by a `#fragment`, when the same endpoint accepts more than one body or
  returns more than one shape — eight documented ways to create an index, all
  of them `POST /_api/index`. The surface carries one operation per address,
  so the comparison is a set relation: every documented address is reachable,
  and every address the surface calls is documented. Mirroring the
  description's duplicates would mean shipping eight functions that differ
  only by a field in the body.

  ## The database prefix is not part of an address here

  Most documented paths begin `/_db/{database-name}/`. The surface leaves that
  off and passes the database as an option, which the driver prepends, so the
  prefix is stripped from the document side before comparing.

  Integration tier: needs the 3.12 compose service.
  """

  use ExUnit.Case, async: false

  @moduletag integration: true

  alias Arangox.{Errno, Response}
  alias Arangox.TestSupport.ApiSurface

  @document_path "/_db/_system/_admin/aardvark/api/swagger.json"
  @methods ~w(get post put patch delete head options)

  # The description lists 243 operations at 228 distinct addresses. The
  # surface carries 230 operations: one per address, plus two deliberate
  # extras where one address genuinely does two things —
  # `POST /_api/document/{collection}` takes a document or a list of them, and
  # `PUT /_api/document/{collection}` reads when `onlyget` is set and replaces
  # when it is not. Those are different calls in Elixir even though they share
  # an address. All three numbers are pinned so a server release that adds or
  # removes an endpoint fails here rather than passing quietly.
  @document_operation_count 243
  @address_count 228
  @surface_operation_count 230

  # The document is ~1MB. The driver bounds the socket wait by
  # min(remaining budget, :request_timeout), so both must be raised together.
  @fetch_opts [timeout: 60_000, request_timeout: 60_000]

  setup_all do
    {:ok, conn} = Arangox.start_link(TestHelper.opts(endpoints: TestHelper.default()))

    # Errno.tag/0 is the repo's single version pin, and it must be checked
    # against `/_api/version` — never the document's own info.version, whose
    # format differs ("3.12.10 (API v0)").
    assert {:ok, %Response{status: 200, body: %{"version" => server_version}}} =
             Arangox.get(conn, "/_api/version", [], @fetch_opts)

    assert server_version == Errno.tag(),
           """
           version pin mismatch: Errno.tag() is #{inspect(Errno.tag())} but the server \
           at #{TestHelper.default()} reports #{inspect(server_version)}. The gate only \
           means anything against the pinned server — check ARANGO_VERSION and the \
           docker-compose.yml default, or move the pin (priv/arangodb/gen_errno.exs) \
           and this gate's expectations together.
           """

    assert {:ok, %Response{status: 200, body: document}} =
             Arangox.get(conn, @document_path, [], @fetch_opts)

    assert is_map(document) and is_map(document["paths"]),
           "the server responded to #{@document_path} without a decodable paths map"

    %{document: document, operations: document_operations(document), surface: surface()}
  end

  ## Cardinality

  test "the description holds the pinned number of operations and addresses", ctx do
    assert length(ctx.operations) == @document_operation_count,
           "the server describes #{length(ctx.operations)} operations, expected " <>
             "#{@document_operation_count} at the #{Errno.tag()} pin"

    addresses = ctx.operations |> Enum.map(& &1.address) |> Enum.uniq()

    assert length(addresses) == @address_count,
           "the server describes #{length(addresses)} distinct addresses, expected " <>
             "#{@address_count} at the #{Errno.tag()} pin"

    assert length(ctx.surface) == @surface_operation_count,
           "#{ApiSurface.surface_dir()} holds #{length(ctx.surface)} operations, expected " <>
             "#{@surface_operation_count} — an operation was added or removed"
  end

  ## Address coverage, both ways

  test "every documented address is reachable from the surface", ctx do
    documented = ctx.operations |> Enum.map(& &1.address) |> MapSet.new()
    reachable = ctx.surface |> Enum.map(& &1.address) |> MapSet.new()

    missing = documented |> MapSet.difference(reachable) |> Enum.sort()

    assert missing == [],
           """
           the server describes these addresses and nothing in \
           #{ApiSurface.surface_dir()} calls them:
           #{format(missing)}
           """
  end

  test "every address the surface calls is documented", ctx do
    documented = ctx.operations |> Enum.map(& &1.address) |> MapSet.new()

    surplus =
      for op <- ctx.surface, not MapSet.member?(documented, op.address), do: op.address

    assert Enum.sort(surplus) == [],
           """
           #{ApiSurface.surface_dir()} calls these addresses and the server describes none \
           of them — a typo in a path, or an endpoint the server dropped:
           #{format(Enum.sort(surplus))}
           """
  end

  test "server-global addresses are marked so no database prefix is added", ctx do
    documented =
      for op <- ctx.operations, into: %{}, do: {op.address, op.database_scope}

    wrong =
      for op <- ctx.surface,
          expected = Map.fetch!(documented, op.address),
          actual = Keyword.get(op.spec, :database_scope, :database),
          actual != expected,
          do: "#{op.address}: document says #{expected}, surface declares #{actual}"

    assert Enum.sort(wrong) == [],
           """
           these operations would send a database prefix that disagrees with the server description:
           #{format(Enum.sort(wrong))}
           """
  end

  ## Parameters

  test "every query parameter the surface sends is documented at its address", ctx do
    documented = documented_query_keys(ctx.operations)

    unknown =
      for op <- ctx.surface,
          known = Map.get(documented, op.address, MapSet.new()),
          key <- op.query ++ Enum.map(op.forced, fn {wire, _v} -> wire end),
          not MapSet.member?(known, key),
          do: "#{op.address} sends #{key}"

    assert Enum.sort(unknown) == [],
           """
           these query keys are not documented at their address:
           #{format(Enum.sort(unknown))}
           """
  end

  # A parameter the description marks required must be reachable: either the
  # surface forces it, or it offers it. An operation that can only be called
  # without a required parameter is one that can only fail.
  test "every required query parameter is forced or offered", ctx do
    by_address =
      Enum.reduce(ctx.operations, %{}, fn op, acc ->
        Map.update(acc, op.address, op.required, &MapSet.union(&1, op.required))
      end)

    # Reachability is per address, not per operation: two operations can share
    # an address and differ precisely by the parameter one of them forces.
    # `replace_many` must not force `onlyget` — sending it is what would turn
    # the replace into a read.
    covered =
      Enum.reduce(ctx.surface, %{}, fn op, acc ->
        keys = MapSet.new(op.query ++ Enum.map(op.forced, fn {wire, _v} -> wire end))
        Map.update(acc, op.address, keys, &MapSet.union(&1, keys))
      end)

    unreachable =
      for {address, required} <- by_address,
          offered = Map.get(covered, address, MapSet.new()),
          key <- MapSet.difference(required, offered) |> Enum.sort(),
          do: "#{address} requires #{key}, which no operation there forces or offers"

    assert Enum.sort(unreachable) == [],
           """
           #{format(Enum.sort(unreachable))}
           """
  end

  ## Request media

  test "a declared non-JSON request media is carried by the surface", ctx do
    documented =
      for op <- ctx.operations, op.media != nil, into: %{}, do: {op.address, op.media}

    wrong =
      for op <- ctx.surface,
          expected = Map.get(documented, op.address),
          expected != nil,
          media(op) != expected,
          do:
            "#{op.address}: document says #{inspect(expected)}, surface sends #{inspect(media(op))}"

    assert Enum.sort(wrong) == [],
           """
           a body sent under the wrong media type reaches the server as the wrong thing:
           #{format(Enum.sort(wrong))}
           """
  end

  ## Extraction

  defp document_operations(document) do
    for {path, methods} <- document["paths"],
        {method, op} <- methods,
        method in @methods do
      params = op["parameters"] || []

      %{
        address: address(method, path),
        database_scope: if(String.starts_with?(path, "/_db/"), do: :database, else: :server),
        required:
          for(p <- params, p["in"] == "query", p["required"], into: MapSet.new(), do: p["name"]),
        query: for(p <- params, p["in"] == "query", into: MapSet.new(), do: p["name"]),
        media: non_json_media(op)
      }
    end
  end

  defp non_json_media(op) do
    case Map.keys((op["requestBody"] || %{})["content"] || %{}) do
      [one] ->
        base = one |> String.split(";") |> hd() |> String.trim()
        if base == "application/json" or String.ends_with?(base, "+json"), do: nil, else: one

      _zero_or_many ->
        nil
    end
  end

  # The document's address, normalized to what the surface addresses: the
  # fragment dropped and the database prefix removed, since the driver
  # prepends that from the `:database` option.
  defp address(method, path) do
    path =
      path
      |> String.split("#")
      |> hd()
      |> String.replace_prefix("/_db/{database-name}", "")

    String.upcase(method) <> " " <> normalize(path)
  end

  # Parameter names differ between the document and the surface — the document
  # writes `{collection-name}`, the surface's argument is `collection_name` —
  # so every parameter is compared by position, not by name.
  defp normalize(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      "{" <> _rest = _param -> "{}"
      segment -> segment
    end)
  end

  defp surface do
    for file <- ApiSurface.surface_files(),
        op <- ApiSurface.operations(file),
        op.spec != nil do
      %{
        fun: op.fun,
        address: String.upcase(to_string(op.method)) <> " " <> normalize(ApiSurface.address(op)),
        query: op.query,
        forced: op.forced,
        spec: op.spec
      }
    end
  end

  defp media(op), do: Keyword.get(op.spec, :media)

  defp documented_query_keys(operations) do
    Enum.reduce(operations, %{}, fn op, acc ->
      Map.update(acc, op.address, op.query, &MapSet.union(&1, op.query))
    end)
  end

  defp format([]), do: "  (none)"
  defp format(items), do: Enum.map_join(items, "\n", &("  " <> &1))
end
