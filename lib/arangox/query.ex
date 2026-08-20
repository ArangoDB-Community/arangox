defmodule Arangox.Query do
  @moduledoc """
  An AQL query: the statement, and the options the server should run it under.

  A query is what `Arangox.query/4` runs and what `Arangox.cursor/4` streams.

  ## There is no prepare step

  _ArangoDB_ has no prepared statements, and `DBConnection.prepare/3` is refused
  here rather than implemented. What the server offers instead is a **plan
  cache**: a memoisation of parsing and planning, held server-side, keyed by
  statement text, and shared by every caller in the database.

  That shape matters, because it is not the one the word "prepare" implies. The
  first execution populates an entry; the *second* reports the key of the entry
  that served it; changing a bind **value** reuses the same entry, since the
  plan is parameterised over values. The reuse therefore comes from running the
  same text again, and nothing a client holds on to participates in it.

  So the plan cache is asked for per query, and only when asked:

      Arangox.query(conn, "FOR d IN c FILTER d.x == @x RETURN d", %{x: 1},
        use_plan_cache: true)

  It is opt-in rather than defaulted for two reasons. The server refuses to
  cache some statements outright — an UPSERT answers `1584`,
  `:query_not_eligible_for_plan_caching` — and the option has a server-version
  floor of 3.12.4 that this driver gates on. Neither belongs to a caller who
  never asked for the cache.

  Deliberately holds no database. Plans are cached per database, so a query that
  captured one could not be reused against another; the database is a property
  of the request, not of the statement.

  ## Options

  AQL options are given as snake_case atoms and mapped to the names the HTTP API
  uses. The mapping is taken from the server's own published OpenAPI document,
  which is also what decides whether an option belongs at the top level of the
  request body or inside its `options` object — `:batch_size` is top-level,
  `:full_count` is nested, and nothing about the name says which.

      Arangox.cursor(conn, "FOR i IN 1..100 RETURN i", %{}, batch_size: 10)

      %Arangox.Query{query: "FOR i IN 1..100 RETURN i", opts: [full_count: true]}

  An option this module does not know is an error rather than a key invented on
  the wire, because the server ignores unknown body attributes silently and a
  typo would otherwise look like it worked.

  `:properties` remains the escape hatch: a list or map of body attributes
  passed through verbatim under the names the server uses. It is merged **last**,
  so it wins over a mapped option. That ordering is what keeps code written
  against the escape hatch working unchanged when a mapped name for the same
  field arrives later.
  """

  alias __MODULE__
  alias Arangox.Error

  @type t :: %__MODULE__{
          query: binary,
          opts: keyword
        }

  @enforce_keys [:query]

  defstruct [:query, opts: []]

  # Body attributes the server reads at the top level of `POST /_api/cursor`,
  # and those it reads from the nested `options` object. Both tables are
  # transcribed from the server's published OpenAPI document — the one the
  # API conformance gate fetches from the live server — rather than
  # remembered.
  #
  # The mapping is a table and not a snake_case-to-camelCase transform because
  # one name does not survive one: `:max_dnf_condition_members` is
  # `maxDNFConditionMembers`, which a mechanical transform renders as
  # `maxDnfConditionMembers` and the server ignores.
  @top_level %{
    batch_size: :batchSize,
    count: :count,
    memory_limit: :memoryLimit,
    ttl: :ttl
  }

  @nested %{
    allow_dirty_reads: :allowDirtyReads,
    allow_retry: :allowRetry,
    cache: :cache,
    fail_on_warning: :failOnWarning,
    fill_block_cache: :fillBlockCache,
    full_count: :fullCount,
    intermediate_commit_count: :intermediateCommitCount,
    intermediate_commit_size: :intermediateCommitSize,
    max_dnf_condition_members: :maxDNFConditionMembers,
    max_nodes_per_callstack: :maxNodesPerCallstack,
    max_number_of_plans: :maxNumberOfPlans,
    max_runtime: :maxRuntime,
    max_transaction_size: :maxTransactionSize,
    max_warning_count: :maxWarningCount,
    optimizer: :optimizer,
    profile: :profile,
    satellite_sync_wait: :satelliteSyncWait,
    skip_inaccessible_collections: :skipInaccessibleCollections,
    spill_over_threshold_memory_usage: :spillOverThresholdMemoryUsage,
    spill_over_threshold_num_rows: :spillOverThresholdNumRows,
    stream: :stream,
    use_plan_cache: :usePlanCache
  }

  @known Map.keys(@top_level) ++ Map.keys(@nested) ++ [:properties]

  @doc false
  @spec known_options :: [atom]
  def known_options, do: Enum.sort(@known)

  @doc false
  # The one cursor-body builder. `handle_declare/4` and the prepared-execution
  # path both come here, so a body attribute only has to be understood once.
  #
  # Precedence, lowest first: the query's own options, AQL options carried by
  # the call, and `:properties` verbatim over all of it.
  #
  # Only the query's own options are checked for unknown keys. The call's
  # option list also carries `DBConnection`'s keys, `:database` and
  # `:transaction`, so AQL names are picked out of it rather than validated
  # against it; `Arangox.query/4` and `Arangox.cursor/4` warn on near-misses.
  @spec body(t, Arangox.bindvars(), keyword) :: {:ok, map} | {:error, Arangox.Error.t()}
  def body(%Query{query: statement, opts: query_opts}, params, call_opts) do
    with :ok <- validate_opts(query_opts) do
      opts =
        query_opts
        |> Keyword.take(@known)
        |> Keyword.merge(Keyword.take(call_opts, @known))

      {:ok, build(statement, params, opts)}
    end
  end

  defp validate_opts(opts) do
    case Enum.find(opts, fn {key, _value} -> key not in @known end) do
      nil ->
        :ok

      {key, _value} ->
        {:error,
         %Error{
           reason: :options,
           message:
             "unknown AQL query option #{inspect(key)}. Known options are: " <>
               Enum.map_join(known_options(), ", ", &inspect/1) <>
               ". Anything the mapping does not cover can be passed verbatim under :properties"
         }}
    end
  end

  defp build(statement, params, opts) do
    {properties, opts} = Keyword.pop(opts, :properties, [])

    opts
    |> Enum.reduce(%{query: statement, bindVars: Enum.into(params, %{})}, &put_option/2)
    |> then(&Enum.into(properties, &1))
  end

  defp put_option({key, value}, body) when is_map_key(@top_level, key),
    do: Map.put(body, Map.fetch!(@top_level, key), value)

  defp put_option({key, value}, body) do
    name = Map.fetch!(@nested, key)

    Map.update(body, :options, %{name => value}, &Map.put(&1, name, value))
  end

  defimpl DBConnection.Query do
    # `describe/2` runs on every prepare and `parse/2` on every unprepared
    # execute. Both answer with the query unchanged: there is no server-side
    # prepare to describe against, and the options are checked where an invalid
    # one can be reported as an error rather than raised through the callback.
    def parse(%Query{} = query, _opts), do: query

    def describe(%Query{} = query, _opts), do: query

    # Bind variables reach the server under its own key, never interpolated
    # into the statement.
    def encode(%Query{}, params, _opts), do: Enum.into(params, %{})

    # Both a prepared execution and each batch of a streamed cursor arrive as
    # an `%Arangox.Response{}` the client already built, so there is nothing to
    # convert. Keep the clause this wide: a narrower one leaves `DBConnection`
    # without an answer when a callback returns anything else.
    def decode(%Query{}, result, _opts), do: result
  end
end
