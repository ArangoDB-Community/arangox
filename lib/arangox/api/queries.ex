defmodule Arangox.Api.Queries do
  @moduledoc """
  ArangoDB's Queries operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List the running AQL queries

  Returns a list of the AQL queries that currently run in the specified
  database.

  Query tracking needs to be enabled by the
  [`--query.tracking` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--querytracking)
  or at runtime with the `enabled` query tracking property of the
  `PUT /_db/{database-name}/_api/query/properties` endpoint.
  If query tracking is disabled for the current database,
  an **empty list** is returned.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      []
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query", "current"],
      query: [all: "all"],
      opts: opts
    )
  end

  @doc """
  List the running AQL queries. Raises on error.

  See `all/1`.
  """
  @spec all!(Arangox.conn(), keyword) :: term
  def all!(conn, opts \\ []) do
    case all(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the registered user-defined AQL functions

  Returns all registered user-defined functions (UDFs) for the use in AQL of the
  current database.

  The call returns a JSON array with status codes and all user functions found under `result`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => []
      }
  """
  @spec all_aql_user_functions(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_aql_user_functions(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "aqlfunction"],
      query: [namespace: "namespace"],
      opts: opts
    )
  end

  @doc """
  List the registered user-defined AQL functions. Raises on error.

  See `all_aql_user_functions/1`.
  """
  @spec all_aql_user_functions!(Arangox.conn(), keyword) :: term
  def all_aql_user_functions!(conn, opts \\ []) do
    case all_aql_user_functions(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the entries of the AQL query plan cache

  Returns an array containing information about each AQL execution plan
  currently stored in the cache of the selected database.

  This requires read privileges for the current database. In addition, only those
  query plans are returned for which the current user has at least read permissions
  on all collections and Views included in the query.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      []
  """
  @spec all_query_cache_plans(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_query_cache_plans(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query-plan-cache"],
      opts: opts
    )
  end

  @doc """
  List the entries of the AQL query plan cache. Raises on error.

  See `all_query_cache_plans/1`.
  """
  @spec all_query_cache_plans!(Arangox.conn(), keyword) :: term
  def all_query_cache_plans!(conn, opts \\ []) do
    case all_query_cache_plans(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the entries of the AQL query results cache

  Returns an array containing the AQL query results currently stored in the query results
  cache of the selected database.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      []
  """
  @spec all_query_cache_results(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_query_cache_results(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query-cache", "entries"],
      opts: opts
    )
  end

  @doc """
  List the entries of the AQL query results cache. Raises on error.

  See `all_query_cache_results/1`.
  """
  @spec all_query_cache_results!(Arangox.conn(), keyword) :: term
  def all_query_cache_results!(conn, opts \\ []) do
    case all_query_cache_results(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the slow AQL queries

  Returns a list of the recently finished AQL queries that exceeded the
  slow query threshold in the specified database.

  Slow query tracking needs to be enabled by the
  [`--query.tracking-slow-queries` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--querytracking-slow-queries)
  or at runtime with the `trackSlowQueries` query tracking property of the
  `PUT /_db/{database-name}/_api/query/properties` endpoint.
  If slow query tracking is disabled for the current database,
  an **empty list** is returned.

  The maximum amount of queries in the list can be controlled by setting
  the `maxSlowQueries` query tracking property via the
  `PUT /_db/{database-name}/_api/query/properties` endpoint at runtime.

  The threshold for treating a query as *slow* can be adjusted separate
  for queries with the `stream` option on or off by setting the
  [`--query.slow-threshold`](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--queryslow-threshold)
  and [`--query.slow-streaming-threshold`](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--queryslow-streaming-threshold)
  startup options or at runtime with the `slowQueryThreshold` and
  `slowStreamingQueryThreshold` query tracking properties of the
  `PUT /_db/{database-name}/_api/query/properties` endpoint.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      []
  """
  @spec all_slow(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_slow(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query", "slow"],
      query: [all: "all"],
      opts: opts
    )
  end

  @doc """
  List the slow AQL queries. Raises on error.

  See `all_slow/1`.
  """
  @spec all_slow!(Arangox.conn(), keyword) :: term
  def all_slow!(conn, opts \\ []) do
    case all_slow(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Clear the list of slow AQL queries

  Clears the list of slow AQL queries for the current database.
  """
  @spec clear_slow_list(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def clear_slow_list(conn, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "query", "slow"],
      query: [all: "all"],
      opts: opts
    )
  end

  @doc """
  Clear the list of slow AQL queries. Raises on error.

  See `clear_slow_list/1`.
  """
  @spec clear_slow_list!(Arangox.conn(), keyword) :: term
  def clear_slow_list!(conn, opts \\ []) do
    case clear_slow_list(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a user-defined AQL function

  Registers a user-defined function (UDF) written in JavaScript for the use in
  AQL queries in the current database.

  In case of success, HTTP 200 is returned.
  If the function isn't valid etc. HTTP 400 including a detailed error message will be returned.
  """
  @spec create_aql_user_function(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_aql_user_function(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "aqlfunction"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a user-defined AQL function. Raises on error.

  See `create_aql_user_function/2`.
  """
  @spec create_aql_user_function!(Arangox.conn(), term, keyword) :: term
  def create_aql_user_function!(conn, body, opts \\ []) do
    case create_aql_user_function(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a cursor

  Submits an AQL query for execution in the current database. The server returns
  a result batch and may indicate that further batches need to be fetched using
  a cursor identifier.

  The query details include the query string plus optional query options and
  bind parameters. These values need to be passed in a JSON representation in
  the body of the POST request.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cached" => boolean,
        "code" => integer,
        "error" => boolean,
        "extra" => %{
          "stats" => %{
            "cacheHits" => integer,
            "cacheMisses" => integer,
            "cursorsCreated" => integer,
            "cursorsRearmed" => integer,
            "documentLookups" => integer,
            "executionTime" => float,
            "filtered" => integer,
            "httpRequests" => integer,
            "intermediateCommits" => integer,
            "peakMemoryUsage" => integer,
            "scannedFull" => integer,
            "scannedIndex" => integer,
            "searchParallelism" => integer,
            "seeks" => integer,
            "writesExecuted" => integer,
            "writesIgnored" => integer
          },
          "warnings" => []
        },
        "hasMore" => boolean,
        "result" => [%{
          "_id" => string,
          "_key" => string,
          "_rev" => string
        }]
      }
  """
  @spec create_cursor(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create_cursor(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "cursor"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a cursor. Raises on error.

  See `create_cursor/2`.
  """
  @spec create_cursor!(Arangox.conn(), term, keyword) :: term
  def create_cursor!(conn, body, opts \\ []) do
    case create_cursor(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Kill a running AQL query

  Kills a running query in the currently selected database. The query will be
  terminated at the next cancellation point.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, query_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "query", query_id],
      query: [all: "all"],
      opts: opts
    )
  end

  @doc """
  Kill a running AQL query. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, query_id, opts \\ []) do
    case delete(conn, query_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove a user-defined AQL function

  Deletes an existing user-defined function (UDF) or function group identified by
  `name` from the current database.
  """
  @spec delete_aql_user_function(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_aql_user_function(conn, name, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "aqlfunction", name],
      query: [group: "group"],
      opts: opts
    )
  end

  @doc """
  Remove a user-defined AQL function. Raises on error.

  See `delete_aql_user_function/2`.
  """
  @spec delete_aql_user_function!(Arangox.conn(), binary, keyword) :: term
  def delete_aql_user_function!(conn, name, opts \\ []) do
    case delete_aql_user_function(conn, name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Clear the AQL query results cache

  Clears all results stored in the AQL query results cache for the current database.
  """
  @spec delete_cache(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete_cache(conn, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "query-cache"],
      opts: opts
    )
  end

  @doc """
  Clear the AQL query results cache. Raises on error.

  See `delete_cache/1`.
  """
  @spec delete_cache!(Arangox.conn(), keyword) :: term
  def delete_cache!(conn, opts \\ []) do
    case delete_cache(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete a cursor

  Deletes the cursor and frees the resources associated with it.

  The cursor will automatically be destroyed on the server when the client has
  retrieved all documents from it. The client can also explicitly destroy the
  cursor at any earlier time using an HTTP DELETE request. The cursor identifier must
  be included as part of the URL.

  Note: the server will also destroy abandoned cursors automatically after a
  certain server-controlled timeout to avoid resource leakage.
  """
  @spec delete_cursor(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete_cursor(conn, cursor_identifier, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "cursor", cursor_identifier],
      opts: opts
    )
  end

  @doc """
  Delete a cursor. Raises on error.

  See `delete_cursor/2`.
  """
  @spec delete_cursor!(Arangox.conn(), binary, keyword) :: term
  def delete_cursor!(conn, cursor_identifier, opts \\ []) do
    case delete_cursor(conn, cursor_identifier, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Clear the AQL query plan cache

  Clears all execution plans stored in the AQL query plan cache for the
  current database.

  This requires write privileges for the current database.
  """
  @spec delete_plan_cache(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete_plan_cache(conn, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "query-plan-cache"],
      opts: opts
    )
  end

  @doc """
  Clear the AQL query plan cache. Raises on error.

  See `delete_plan_cache/1`.
  """
  @spec delete_plan_cache!(Arangox.conn(), keyword) :: term
  def delete_plan_cache!(conn, opts \\ []) do
    case delete_plan_cache(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Explain an AQL query

  To explain how an AQL query would be executed on the server, the query string
  can be sent to the server via an HTTP POST request. The server will then validate
  the query and create an execution plan for it. The execution plan will be
  returned, but the query will not be executed.

  The execution plan that is returned by the server can be used to estimate the
  probable performance of the query. Though the actual performance will depend
  on many different factors, the execution plan normally can provide some rough
  estimates on the amount of work the server needs to do in order to actually run
  the query.

  By default, the explain operation will return the optimal plan as chosen by
  the query optimizer The optimal plan is the plan with the lowest total estimated
  cost. The plan will be returned in the attribute `plan` of the response object.
  If the option `allPlans` is specified in the request, the result will contain
  all plans created by the optimizer. The plans will then be returned in the
  attribute `plans`.

  The result will also contain an attribute `warnings`, which is an array of
  warnings that occurred during optimization or execution plan creation. Additionally,
  a `stats` attribute is contained in the result with some optimizer statistics.
  If `allPlans` is set to `false`, the result will contain an attribute `cacheable`
  that states whether the query results can be cached on the server if the query
  result cache were used. The `cacheable` attribute is not present when `allPlans`
  is set to `true`.

  Each plan in the result is a JSON object with the following attributes:
  - `nodes`: the array of execution nodes of the plan.

  - `estimatedCost`: the total estimated cost for the plan. If there are multiple
  plans, the optimizer will choose the plan with the lowest total cost.

  - `collections`: an array of collections used in the query

  - `rules`: an array of rules the optimizer applied.

  - `variables`: array of variables used in the query (note: this may contain
  internal variables created by the optimizer)

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheable" => boolean,
        "code" => integer,
        "error" => boolean,
        "plan" => %{
          "asyncPrefetchNodes" => integer,
          "collections" => [%{
            "name" => string,
            "type" => string
          }],
          "estimatedCost" => integer,
          "estimatedNrItems" => integer,
          "isModificationQuery" => boolean,
          "nodes" => [%{
            "bindParameterVariables" => %{},
            "dependencies" => [],
            "estimatedCost" => integer,
            "estimatedNrItems" => integer,
            "id" => integer,
            "type" => string
          }],
          "rules" => [string],
          "variables" => [%{
            "id" => integer,
            "isFullDocumentFromCollection" => boolean,
            "name" => string
          }]
        },
        "stats" => %{
          "executionTime" => float,
          "peakMemoryUsage" => integer,
          "plansCreated" => integer,
          "rules" => %{},
          "rulesExecuted" => integer,
          "rulesSkipped" => integer
        },
        "warnings" => []
      }
  """
  @spec explain(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def explain(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "explain"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Explain an AQL query. Raises on error.

  See `explain/2`.
  """
  @spec explain!(Arangox.conn(), term, keyword) :: term
  def explain!(conn, body, opts \\ []) do
    case explain(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Read the next batch from a cursor

  If the cursor is still alive, returns an object with the next query result batch.

  If the cursor is not fully consumed, the time-to-live for the cursor
  is renewed by this API call.
  """
  @spec next_cursor_batch(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def next_cursor_batch(conn, cursor_identifier, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "cursor", cursor_identifier],
      opts: opts
    )
  end

  @doc """
  Read the next batch from a cursor. Raises on error.

  See `next_cursor_batch/2`.
  """
  @spec next_cursor_batch!(Arangox.conn(), binary, keyword) :: term
  def next_cursor_batch!(conn, cursor_identifier, opts \\ []) do
    case next_cursor_batch(conn, cursor_identifier, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Read the next batch from a cursor (deprecated)

  > **WARNING:**
  This endpoint is deprecated in favor its functionally equivalent POST counterpart.


  If the cursor is still alive, returns an object with the following
  attributes:

  - `id`: a `cursor-identifier`
  - `result`: a list of documents for the current batch
  - `hasMore`: `false` if this was the last batch
  - `count`: if present the total number of elements
  - `code`: an HTTP status code
  - `error`: a boolean flag to indicate whether an error occurred
  - `errorNum`: a server error number (if `error` is `true`)
  - `errorMessage`: a descriptive error message (if `error` is `true`)
  - `extra`: an object with additional information about the query result, with
  the nested objects `stats` and `warnings`. Only delivered as part of the last
  batch in case of a cursor with the `stream` option enabled.

  Note that even if `hasMore` returns `true`, the next call might
  still return no documents. If, however, `hasMore` is `false`, then
  the cursor is exhausted.  Once the `hasMore` attribute has a value of
  `false`, the client can stop.

  If the cursor is not fully consumed, the time-to-live for the cursor
  is renewed by this API call.
  """
  @spec next_cursor_batch_put(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def next_cursor_batch_put(conn, cursor_identifier, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "cursor", cursor_identifier],
      opts: opts
    )
  end

  @doc """
  Read the next batch from a cursor (deprecated). Raises on error.

  See `next_cursor_batch_put/2`.
  """
  @spec next_cursor_batch_put!(Arangox.conn(), binary, keyword) :: term
  def next_cursor_batch_put!(conn, cursor_identifier, opts \\ []) do
    case next_cursor_batch_put(conn, cursor_identifier, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List all AQL optimizer rules

  A list of all optimizer rules and their properties.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      [%{
        "description" => string,
        "flags" => %{
          "canBeDisabled" => boolean,
          "canCreateAdditionalPlans" => boolean,
          "clusterOnly" => boolean,
          "disabledByDefault" => boolean,
          "enterpriseOnly" => boolean,
          "hidden" => boolean
        },
        "name" => string
      }]
  """
  @spec optimizer_rules(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def optimizer_rules(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query", "rules"],
      opts: opts
    )
  end

  @doc """
  List all AQL optimizer rules. Raises on error.

  See `optimizer_rules/1`.
  """
  @spec optimizer_rules!(Arangox.conn(), keyword) :: term
  def optimizer_rules!(conn, opts \\ []) do
    case optimizer_rules(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Parse an AQL query

  This endpoint is for query validation only. To actually query the database,
  see `/api/cursor`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "ast" => [%{
          "subNodes" => [%{
            "subNodes" => [%{
              "id" => integer,
              "name" => string,
              "type" => string
            }],
            "type" => string
          }],
          "type" => string
        }],
        "bindVars" => [],
        "code" => integer,
        "collections" => [string],
        "error" => boolean,
        "parsed" => boolean,
        "warnings" => []
      }
  """
  @spec parse(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def parse(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "query"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Parse an AQL query. Raises on error.

  See `parse/2`.
  """
  @spec parse!(Arangox.conn(), term, keyword) :: term
  def parse!(conn, body, opts \\ []) do
    case parse(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Read a batch from the cursor again

  You can use this endpoint to retry fetching the latest batch from a cursor.
  The endpoint requires the `allowRetry` query option to be enabled for the cursor.

  Calling this endpoint with the last returned batch identifier returns the
  query results for that same batch again. This does not advance the cursor.
  Client applications can use this to re-transfer a batch once more in case of
  transfer errors.

  You can also call this endpoint with the next batch identifier, i.e. the value
  returned in the `nextBatchId` attribute of a previous request. This advances the
  cursor and returns the results of the next batch.

  From v3.11.1 onward, you may use this endpoint even if the `allowRetry`
  attribute is `false` to fetch the next batch, but you cannot request a batch
  again unless you set it to `true`.

  Note that it is only supported to query the last returned batch identifier or
  the directly following batch identifier. The latter is only supported if there
  are more results in the cursor (i.e. `hasMore` is `true` in the latest batch).

  Note that when the last batch has been consumed successfully by a client
  application, it should explicitly delete the cursor to inform the server that it
  successfully received and processed the batch so that the server can free up
  resources.

  The time-to-live for the cursor is renewed by this API call.
  """
  @spec previous_cursor_batch(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def previous_cursor_batch(conn, cursor_identifier, batch_identifier, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "cursor", cursor_identifier, batch_identifier],
      opts: opts
    )
  end

  @doc """
  Read a batch from the cursor again. Raises on error.

  See `previous_cursor_batch/3`.
  """
  @spec previous_cursor_batch!(Arangox.conn(), binary, binary, keyword) :: term
  def previous_cursor_batch!(conn, cursor_identifier, batch_identifier, opts \\ []) do
    case previous_cursor_batch(conn, cursor_identifier, batch_identifier, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the AQL query results cache configuration

  Returns the global AQL query results cache configuration.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "includeSystem" => boolean,
        "maxEntrySize" => integer,
        "maxResults" => integer,
        "maxResultsSize" => integer,
        "mode" => string
      }
  """
  @spec query_cache_properties(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def query_cache_properties(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query-cache", "properties"],
      opts: opts
    )
  end

  @doc """
  Get the AQL query results cache configuration. Raises on error.

  See `query_cache_properties/1`.
  """
  @spec query_cache_properties!(Arangox.conn(), keyword) :: term
  def query_cache_properties!(conn, opts \\ []) do
    case query_cache_properties(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set the AQL query results cache configuration

  Adjusts the global properties for the AQL query results cache.

  Changing the properties may invalidate all results currently in the cache.
  """
  @spec set_query_cache_properties(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def set_query_cache_properties(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "query-cache", "properties"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set the AQL query results cache configuration. Raises on error.

  See `set_query_cache_properties/2`.
  """
  @spec set_query_cache_properties!(Arangox.conn(), term, keyword) :: term
  def set_query_cache_properties!(conn, body, opts \\ []) do
    case set_query_cache_properties(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the AQL query tracking configuration

  Returns the current query tracking properties of the specified database.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "enabled" => boolean,
        "error" => boolean,
        "maxQueryStringLength" => integer,
        "maxSlowQueries" => integer,
        "slowQueryThreshold" => integer,
        "slowStreamingQueryThreshold" => integer,
        "trackBindVars" => boolean,
        "trackSlowQueries" => boolean
      }
  """
  @spec tracking_properties(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def tracking_properties(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "query", "properties"],
      opts: opts
    )
  end

  @doc """
  Get the AQL query tracking configuration. Raises on error.

  See `tracking_properties/1`.
  """
  @spec tracking_properties!(Arangox.conn(), keyword) :: term
  def tracking_properties!(conn, opts \\ []) do
    case tracking_properties(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update the AQL query tracking configuration

  Modify one or more query tracking properties at runtime for the
  specified database.
  """
  @spec update_tracking_properties(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_tracking_properties(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "query", "properties"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Update the AQL query tracking configuration. Raises on error.

  See `update_tracking_properties/2`.
  """
  @spec update_tracking_properties!(Arangox.conn(), term, keyword) :: term
  def update_tracking_properties!(conn, body, opts \\ []) do
    case update_tracking_properties(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
