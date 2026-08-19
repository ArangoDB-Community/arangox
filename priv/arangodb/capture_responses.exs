# Records what the operations in `lib/arangox/api/` actually answer, against a
# live server, and writes the result to `priv/arangodb/response-shapes-<tag>.json`.
#
# The API description the server serves does not describe most success bodies:
# it carries no reusable schemas at all, and over half its responses have no
# content schema. Prose is not a type. So the shapes are taken from the server
# instead of from its documentation — the same source of truth the conformance
# gate already trusts, and one that cannot be out of date with the server it
# was recorded against.
#
# Run with the 3.12 compose service up:
#
#     mix run priv/arangodb/capture_responses.exs
#
# Reads are swept automatically: every GET and HEAD whose arguments the fixture
# below can fill is called. Writes are not swept — each one here is named
# deliberately, because a sweep that guesses at write operations is a sweep
# that eventually calls something irreversible.

alias Arangox.Api
alias Arangox.TestSupport.ApiSurface

endpoint = System.get_env("ARANGOX_ENDPOINT", "http://localhost:8529")
{:ok, conn} = Arangox.start_link(endpoints: endpoint, pool_size: 2)

{:ok, %{"version" => tag}} = Api.Administration.version(conn)
IO.puts("recording against #{endpoint} (#{tag})")

# `System.unique_integer/1` restarts its counter with the VM, so a run that
# died before teardown would collide with the next one. The clock does not
# restart.
suffix = System.os_time(:second)

# A previous run that died before teardown leaves fixtures behind. Clear them
# first so a rerun is not blocked by its own wreckage.
{:ok, %{"result" => existing}} = Api.Collections.all(conn)

for %{"name" => name} <- existing, String.starts_with?(name, "capture_") do
  _ = Api.Collections.delete(conn, name)
end

{:ok, %{"graphs" => graphs}} = Api.Graphs.all(conn)

for %{"_key" => name} <- graphs, String.starts_with?(name, "capture_") do
  _ = Api.Graphs.delete(conn, name)
end

{:ok, %{"result" => views}} = Api.Views.all(conn)

for %{"name" => name} <- views, String.starts_with?(name, "capture_") do
  _ = Api.Views.delete(conn, name)
end

{:ok, %{"result" => users}} = Api.Users.all(conn)

for %{"user" => name} <- users, String.starts_with?(name, "capture_") do
  _ = Api.Users.delete(conn, name)
end
coll = "capture_#{suffix}"
graph = "capture_graph_#{suffix}"
view = "capture_view_#{suffix}"
analyzer = "capture_analyzer_#{suffix}"
user = "capture_user_#{suffix}"

# ---------------------------------------------------------------- fixtures --
{:ok, _} = Api.Collections.create(conn, %{name: coll})
{:ok, %{"_key" => key}} = Api.Documents.create(conn, coll, %{"marker" => 1})
{:ok, %{"id" => index_id}} = Api.Indexes.create(conn, coll, %{type: "persistent", fields: ["marker"]})
{:ok, _} = Api.Views.create(conn, %{name: view, type: "arangosearch"})
{:ok, _} = Api.Analyzers.create(conn, %{name: analyzer, type: "identity"})
{:ok, _} = Api.Users.create(conn, %{user: user, passwd: "capture"})

{:ok, _} =
  Api.Graphs.create(conn, %{
    name: graph,
    edgeDefinitions: [%{collection: "#{coll}_edges", from: [coll], to: [coll]}]
  })

{:ok, %{"vertex" => %{"_key" => vertex}}} =
  Api.Graphs.create_vertex(conn, graph, coll, %{"marker" => 2})

{:ok, _} = Api.Documents.create(conn, "#{coll}_edges", %{"_from" => "#{coll}/#{vertex}", "_to" => "#{coll}/#{key}"})

{:ok, %{"result" => %{"id" => trx_id}}} =
  Api.Transactions.begin(conn, %{collections: %{read: [coll]}})

fixture = %{
  collection: coll,
  collection_name: coll,
  key: key,
  index_id: index_id,
  graph: graph,
  vertex: vertex,
  view_name: view,
  analyzer_name: analyzer,
  user: user,
  dbname: "_system",
  transaction_id: trx_id
}

# `vertex_edges` addresses a vertex by its full `collection/key` identifier,
# unlike `get_vertex`, which takes the collection and key as separate
# arguments. Same word, two meanings, so the sweep needs both.
fixture = Map.put(fixture, :vertex_id, "#{coll}/#{vertex}")

# ------------------------------------------------------------------ shapes --
defmodule Shape do
  @max_keys 25

  def of(v) when is_map(v) do
    keys = Map.keys(v)

    if length(keys) > @max_keys do
      %{"__shape__" => "map", "__keys__" => length(keys), "__sample__" => Enum.take(Enum.sort(keys), 8)}
    else
      Map.new(v, fn {k, val} -> {k, of(val)} end)
    end
  end

  def of([]), do: []
  def of([h | _]), do: [of(h)]
  def of(v) when is_boolean(v), do: "boolean"
  def of(v) when is_integer(v), do: "integer"
  def of(v) when is_float(v), do: "float"
  def of(v) when is_binary(v), do: "string"
  def of(nil), do: "null"
  def of(_other), do: "unknown"
end

operations =
  for file <- ApiSurface.surface_files(),
      op <- ApiSurface.operations(file),
      op.spec != nil do
    Map.put(op, :module, Module.concat([Arangox.Api, file |> Path.basename(".ex") |> Macro.camelize()]))
  end

record = fn acc, op, result ->
  entry =
    case result do
      {:ok, body} -> %{"outcome" => "ok", "shape" => Shape.of(body)}
      {:error, %Arangox.Error{status: s, error_num: n}} -> %{"outcome" => "error", "status" => s, "error_num" => n}
      {:error, other} -> %{"outcome" => "error", "detail" => inspect(other)}
    end

  Map.put(acc, "#{inspect(op.module)}.#{op.fun}/#{op.arity}", entry)
end

# ------------------------------------------------------------------- reads --
reads = Enum.filter(operations, &(&1.method in [:get, :head]))

# `get_vertex` addresses a vertex by collection and key, while `vertex_edges`
# wants the single `collection/key` identifier. Both call the argument
# `vertex`, so one of them needs to be told which is meant.
# `/_api/edges/{collection}` names the *edge* collection and takes the start
# vertex as a full `collection/key` identifier.
overrides = %{
  {Api.Graphs, :vertex_edges} => %{collection: "#{coll}_edges", vertex: "#{coll}/#{vertex}"}
}

{captured, skipped} =
  Enum.reduce(reads, {%{}, []}, fn op, {acc, skips} ->
    local = Map.merge(fixture, Map.get(overrides, {op.module, op.fun}, %{}))

    if Enum.all?(op.args, &Map.has_key?(local, &1)) do
      args = Enum.map(op.args, &Map.fetch!(local, &1))

      result =
        try do
          apply(op.module, op.fun, [conn | args] ++ [[]])
        catch
          kind, reason -> {:error, {kind, reason}}
        end

      {record.(acc, op, result), skips}
    else
      missing = Enum.reject(op.args, &Map.has_key?(fixture, &1))
      {acc, [{"#{inspect(op.module)}.#{op.fun}/#{op.arity}", missing} | skips]}
    end
  end)

# ------------------------------------------------------------------ writes --
# Named one at a time. Each acts on the fixture collection and is reversible.
writes = [
  {Api.Documents, :create, [coll, %{"marker" => 3}]},
  {Api.Documents, :update, [coll, key, %{"marker" => 9}]},
  {Api.Documents, :replace, [coll, key, %{"marker" => 10}]},
  {Api.Documents, :create_many, [coll, [%{"marker" => 4}, %{"marker" => 5}]]},
  {Api.Documents, :get_many, [coll, [%{"_key" => key}]]},
  {Api.Collections, :create, [%{name: "#{coll}_b"}]},
  {Api.Collections, :rename, ["#{coll}_b", %{name: "#{coll}_c"}]},
  {Api.Collections, :truncate, ["#{coll}_c"]},
  {Api.Collections, :delete, ["#{coll}_c"]},
  {Api.Queries, :create_cursor, [%{query: "FOR d IN #{coll} LIMIT 2 RETURN d"}]},
  {Api.Queries, :explain, [%{query: "FOR d IN #{coll} RETURN d"}]},
  {Api.Queries, :parse, [%{query: "FOR d IN #{coll} RETURN d"}]},
  {Api.Import, :data, [coll, ~s({"marker":6}\n), [type: "documents"]]},
  {Api.Transactions, :execute_javascript, [%{collections: %{}, action: "function(){ return 1; }"}]},
  {Api.Databases, :create, [%{name: "capture_db_#{suffix}"}]},
  {Api.Databases, :delete, ["capture_db_#{suffix}"]}
]

captured =
  Enum.reduce(writes, captured, fn {mod, fun, args}, acc ->
    {call_args, opts} =
      case List.last(args) do
        o when is_list(o) and o != [] -> {Enum.drop(args, -1), o}
        _ -> {args, []}
      end

    op = %{module: mod, fun: fun, arity: length(call_args) + 2}

    result =
      try do
        apply(mod, fun, [conn | call_args] ++ [opts])
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    record.(acc, op, result)
  end)

# ----------------------------------------------------------------- cluster --
# A single server answers 501 or 403 for the cluster reads: they are not
# unimplemented here, they are meaningless. Compose runs a real cluster, so
# they are recorded against a coordinator instead of left as errors.
cluster_endpoint = System.get_env("ARANGOX_CLUSTER_ENDPOINT", "http://localhost:8006")

captured =
  case Arangox.start_link(endpoints: cluster_endpoint, pool_size: 1) do
    {:ok, cluster} ->
      # Sharding only exists on a cluster, so the collection this asks about
      # has to live there too.
      cluster_coll = "capture_cluster_#{suffix}"
      {:ok, _} = Api.Collections.create(cluster, %{name: cluster_coll})
      cluster_fixture = %{collection_name: cluster_coll, collection: cluster_coll}

      cluster_reads =
        Enum.filter(reads, fn op ->
          (op.module == Api.Cluster or
             {op.module, op.fun} in [
               {Api.Replication, :cluster_inventory},
               {Api.Collections, :shards}
             ]) and Enum.all?(op.args, &Map.has_key?(cluster_fixture, &1))
        end)

      recorded =
        Enum.reduce(cluster_reads, captured, fn op, acc ->
          args = Enum.map(op.args, &Map.fetch!(cluster_fixture, &1))

          result =
            try do
              apply(op.module, op.fun, [cluster | args] ++ [[]])
            catch
              kind, reason -> {:error, {kind, reason}}
            end

          case result do
            {:ok, _} -> record.(acc, op, result)
            _ -> acc
          end
        end)

      _ = Api.Collections.delete(cluster, cluster_coll)
      recorded

    {:error, _} ->
      IO.puts("no cluster at #{cluster_endpoint}; cluster reads left as recorded")
      captured
  end

# ---------------------------------------------------------------- teardown --
_ = Api.Transactions.abort(conn, trx_id)
_ = Api.Graphs.delete(conn, graph, drop_collections: true)
_ = Api.Views.delete(conn, view)
_ = Api.Analyzers.delete(conn, analyzer)
_ = Api.Users.delete(conn, user)
_ = Api.Collections.delete(conn, coll)
_ = Api.Collections.delete(conn, "#{coll}_edges")

path = "priv/arangodb/response-shapes-#{tag}.json"

File.write!(
  path,
  Jason.encode!(
    %{"tag" => tag, "captured" => captured, "skipped" => Map.new(skipped)},
    pretty: true
  )
)

ok = Enum.count(captured, fn {_k, v} -> v["outcome"] == "ok" end)

IO.puts("""

captured #{map_size(captured)} operations (#{ok} answered, #{map_size(captured) - ok} errored)
skipped #{length(skipped)} reads whose arguments the fixture cannot fill
wrote #{path}
""")
