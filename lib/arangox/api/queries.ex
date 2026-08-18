defmodule Arangox.Api.Queries do
  @moduledoc """
  Provides API endpoints related to queries
  """

  @default_client Arangox.Api.Client

  @type clear_slow_aql_query_list_200_json_resp :: %{code: integer, error: boolean}

  @type clear_slow_aql_query_list_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Clear the list of slow AQL queries

  Clears the list of slow AQL queries for the current database.

  ## Options

    * `all`: If set to `true`, clears the slow query history in all databases, not just
      the specified one.
      Using the parameter is only allowed in the `_system` database and with superuser
      privileges.
      

  """
  @spec clear_slow_aql_query_list(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def clear_slow_aql_query_list(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:all])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :clear_slow_aql_query_list},
      url: "/_db/#{database_name}/_api/query/slow",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Queries, :clear_slow_aql_query_list_200_json_resp}},
        {400, {Arangox.Api.Queries, :clear_slow_aql_query_list_400_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_aql_query_cursor_201_json_resp :: %{
          cached: boolean,
          code: integer,
          count: integer | nil,
          error: boolean,
          extra: Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra() | nil,
          hasMore: boolean,
          id: String.t() | nil,
          nextBatchId: String.t() | nil,
          planCacheKey: String.t() | nil,
          result: [any] | nil
        }

  @type create_aql_query_cursor_201_json_resp_extra :: %{
          plan: Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_plan() | nil,
          profile:
            Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_profile() | nil,
          stats: Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_stats(),
          warnings: [Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_warnings()]
        }

  @type create_aql_query_cursor_201_json_resp_extra_plan :: %{
          collections: [
            Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_plan_collections()
          ],
          estimatedCost: number,
          estimatedNrItems: integer,
          isModificationQuery: boolean,
          nodes: [map],
          rules: [String.t()],
          variables: [map]
        }

  @type create_aql_query_cursor_201_json_resp_extra_plan_collections :: %{
          name: String.t(),
          type: String.t()
        }

  @type create_aql_query_cursor_201_json_resp_extra_profile :: %{
          executing: number,
          finalizing: number,
          initializing: number,
          "instantiating executors": number,
          "instantiating plan": number,
          "loading collections": number,
          "optimizing ast": number,
          "optimizing plan": number,
          parsing: number
        }

  @type create_aql_query_cursor_201_json_resp_extra_stats :: %{
          cacheHits: integer,
          cacheMisses: integer,
          cursorsCreated: integer,
          cursorsRearmed: integer,
          documentLookups: integer,
          executionTime: number,
          filtered: integer,
          fullCount: integer | nil,
          httpRequests: integer,
          intermediateCommits: integer,
          nodes:
            [Arangox.Api.Queries.create_aql_query_cursor_201_json_resp_extra_stats_nodes()] | nil,
          peakMemoryUsage: integer,
          scannedFull: integer,
          scannedIndex: integer,
          searchParallelism: integer,
          seeks: integer,
          writesExecuted: integer,
          writesIgnored: integer
        }

  @type create_aql_query_cursor_201_json_resp_extra_stats_nodes :: %{
          calls: integer,
          id: integer,
          items: integer,
          runtime: number
        }

  @type create_aql_query_cursor_201_json_resp_extra_warnings :: %{
          code: integer,
          message: String.t()
        }

  @type create_aql_query_cursor_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a cursor

  Submits an AQL query for execution in the current database. The server returns
  a result batch and may indicate that further batches need to be fetched using
  a cursor identifier.

  The query details include the query string plus optional query options and
  bind parameters. These values need to be passed in a JSON representation in
  the body of the POST request.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_aql_query_cursor(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_aql_query_cursor(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :create_aql_query_cursor},
      url: "/_db/#{database_name}/_api/cursor",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp}},
        {400, {Arangox.Api.Queries, :create_aql_query_cursor_400_json_resp}},
        {404, :null},
        {405, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
  end

  @type create_aql_user_function_200_json_resp :: %{
          code: integer,
          error: boolean,
          isNewlyCreated: boolean
        }

  @type create_aql_user_function_201_json_resp :: %{
          code: integer,
          error: boolean,
          isNewlyCreated: boolean
        }

  @type create_aql_user_function_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a user-defined AQL function

  Registers a user-defined function (UDF) written in JavaScript for the use in
  AQL queries in the current database.

  In case of success, HTTP 200 is returned.
  If the function isn't valid etc. HTTP 400 including a detailed error message will be returned.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_aql_user_function(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_aql_user_function(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :create_aql_user_function},
      url: "/_db/#{database_name}/_api/aqlfunction",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Queries, :create_aql_user_function_200_json_resp}},
        {201, {Arangox.Api.Queries, :create_aql_user_function_201_json_resp}},
        {400, {Arangox.Api.Queries, :create_aql_user_function_400_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Kill a running AQL query

  Kills a running query in the currently selected database. The query will be
  terminated at the next cancellation point.

  ## Options

    * `all`: If set to `true`, attempt to kill the specified query in all databases,
      not just the selected one.
      Using the parameter is only allowed in the `_system` database and with superuser
      privileges.
      

  """
  @spec delete_aql_query(database_name :: String.t(), query_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_aql_query(database_name, query_id, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:all])

    client.request(%{
      args: [database_name: database_name, query_id: query_id],
      call: {Arangox.Api.Queries, :delete_aql_query},
      url: "/_db/#{database_name}/_api/query/#{query_id}",
      method: :delete,
      query: query,
      response: [{200, :null}, {400, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end

  @type delete_aql_query_cache_200_json_resp :: %{code: integer, error: boolean}

  @doc """
  Clear the AQL query results cache

  Clears all results stored in the AQL query results cache for the current database.

  """
  @spec delete_aql_query_cache(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_aql_query_cache(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :delete_aql_query_cache},
      url: "/_db/#{database_name}/_api/query-cache",
      method: :delete,
      response: [
        {200, {Arangox.Api.Queries, :delete_aql_query_cache_200_json_resp}},
        {400, :null}
      ],
      opts: opts
    })
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
  @spec delete_aql_query_cursor(
          database_name :: String.t(),
          cursor_identifier :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_aql_query_cursor(database_name, cursor_identifier, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, cursor_identifier: cursor_identifier],
      call: {Arangox.Api.Queries, :delete_aql_query_cursor},
      url: "/_db/#{database_name}/_api/cursor/#{cursor_identifier}",
      method: :delete,
      response: [{202, :null}, {404, :null}],
      opts: opts
    })
  end

  @type delete_aql_query_plan_cache_200_json_resp :: %{code: integer, error: boolean}

  @doc """
  Clear the AQL query plan cache

  Clears all execution plans stored in the AQL query plan cache for the
  current database.

  This requires write privileges for the current database.

  """
  @spec delete_aql_query_plan_cache(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_aql_query_plan_cache(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :delete_aql_query_plan_cache},
      url: "/_db/#{database_name}/_api/query-plan-cache",
      method: :delete,
      response: [{200, {Arangox.Api.Queries, :delete_aql_query_plan_cache_200_json_resp}}],
      opts: opts
    })
  end

  @type delete_aql_user_function_200_json_resp :: %{
          code: integer,
          deletedCount: integer,
          error: boolean
        }

  @type delete_aql_user_function_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_aql_user_function_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Remove a user-defined AQL function

  Deletes an existing user-defined function (UDF) or function group identified by
  `name` from the current database.

  ## Options

    * `group`: Possible values:
      - `true`: The function name provided in `name` is treated as
        a namespace prefix, and all functions in the specified namespace will be deleted.
        The returned number of deleted functions may become 0 if none matches the string.
      - `false`: The function name provided in `name` must be fully
        qualified, including any namespaces. If none matches the `name`, HTTP 404 is returned.
      

  """
  @spec delete_aql_user_function(database_name :: String.t(), name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_aql_user_function(database_name, name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:group])

    client.request(%{
      args: [database_name: database_name, name: name],
      call: {Arangox.Api.Queries, :delete_aql_user_function},
      url: "/_db/#{database_name}/_api/aqlfunction/#{name}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Queries, :delete_aql_user_function_200_json_resp}},
        {400, {Arangox.Api.Queries, :delete_aql_user_function_400_json_resp}},
        {404, {Arangox.Api.Queries, :delete_aql_user_function_404_json_resp}}
      ],
      opts: opts
    })
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

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec explain_aql_query(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def explain_aql_query(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :explain_aql_query},
      url: "/_db/#{database_name}/_api/explain",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @type get_aql_query_optimizer_rules_200_json_resp :: %{
          flags: Arangox.Api.Queries.get_aql_query_optimizer_rules_200_json_resp_flags(),
          name: String.t()
        }

  @type get_aql_query_optimizer_rules_200_json_resp_flags :: %{
          canBeDisabled: boolean,
          canCreateAdditionalPlans: boolean,
          clusterOnly: boolean,
          disabledByDefault: boolean,
          enterpriseOnly: boolean,
          hidden: boolean
        }

  @doc """
  List all AQL optimizer rules

  A list of all optimizer rules and their properties.

  """
  @spec get_aql_query_optimizer_rules(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_aql_query_optimizer_rules(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :get_aql_query_optimizer_rules},
      url: "/_db/#{database_name}/_api/query/rules",
      method: :get,
      response: [{200, [{Arangox.Api.Queries, :get_aql_query_optimizer_rules_200_json_resp}]}],
      opts: opts
    })
  end

  @type get_aql_query_tracking_properties_200_json_resp :: %{
          code: integer,
          enabled: boolean,
          error: boolean,
          maxQueryStringLength: integer,
          maxSlowQueries: integer,
          slowQueryThreshold: number,
          slowStreamingQueryThreshold: number,
          trackBindVars: boolean,
          trackSlowQueries: boolean
        }

  @type get_aql_query_tracking_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the AQL query tracking configuration

  Returns the current query tracking properties of the specified database.

  """
  @spec get_aql_query_tracking_properties(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_aql_query_tracking_properties(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :get_aql_query_tracking_properties},
      url: "/_db/#{database_name}/_api/query/properties",
      method: :get,
      response: [
        {200, {Arangox.Api.Queries, :get_aql_query_tracking_properties_200_json_resp}},
        {400, {Arangox.Api.Queries, :get_aql_query_tracking_properties_400_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_next_aql_query_cursor_batch_200_json_resp :: %{
          cached: boolean,
          code: integer,
          count: integer | nil,
          error: boolean,
          extra: Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra() | nil,
          hasMore: boolean,
          id: String.t() | nil,
          nextBatchId: String.t() | nil,
          planCacheKey: String.t() | nil,
          result: [any] | nil
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra :: %{
          plan:
            Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_plan() | nil,
          profile:
            Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_profile()
            | nil,
          stats: Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_stats(),
          warnings: [
            Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_warnings()
          ]
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_plan :: %{
          collections: [
            Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_plan_collections()
          ],
          estimatedCost: number,
          estimatedNrItems: integer,
          isModificationQuery: boolean,
          nodes: [map],
          rules: [String.t()],
          variables: [map]
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_plan_collections :: %{
          name: String.t(),
          type: String.t()
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_profile :: %{
          executing: number,
          finalizing: number,
          initializing: number,
          "instantiating executors": number,
          "instantiating plan": number,
          "loading collections": number,
          "optimizing ast": number,
          "optimizing plan": number,
          parsing: number
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_stats :: %{
          cacheHits: integer,
          cacheMisses: integer,
          cursorsCreated: integer,
          cursorsRearmed: integer,
          documentLookups: integer,
          executionTime: number,
          filtered: integer,
          fullCount: integer | nil,
          httpRequests: integer,
          intermediateCommits: integer,
          nodes:
            [
              Arangox.Api.Queries.get_next_aql_query_cursor_batch_200_json_resp_extra_stats_nodes()
            ]
            | nil,
          peakMemoryUsage: integer,
          scannedFull: integer,
          scannedIndex: integer,
          searchParallelism: integer,
          seeks: integer,
          writesExecuted: integer,
          writesIgnored: integer
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_stats_nodes :: %{
          calls: integer,
          id: integer,
          items: integer,
          runtime: number
        }

  @type get_next_aql_query_cursor_batch_200_json_resp_extra_warnings :: %{
          code: integer,
          message: String.t()
        }

  @doc """
  Read the next batch from a cursor

  If the cursor is still alive, returns an object with the next query result batch.

  If the cursor is not fully consumed, the time-to-live for the cursor
  is renewed by this API call.

  """
  @spec get_next_aql_query_cursor_batch(
          database_name :: String.t(),
          cursor_identifier :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_next_aql_query_cursor_batch(database_name, cursor_identifier, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, cursor_identifier: cursor_identifier],
      call: {Arangox.Api.Queries, :get_next_aql_query_cursor_batch},
      url: "/_db/#{database_name}/_api/cursor/#{cursor_identifier}",
      method: :post,
      response: [
        {200, {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp}},
        {400, :null},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
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
  @spec get_next_aql_query_cursor_batch_put(
          database_name :: String.t(),
          cursor_identifier :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_next_aql_query_cursor_batch_put(database_name, cursor_identifier, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, cursor_identifier: cursor_identifier],
      call: {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_put},
      url: "/_db/#{database_name}/_api/cursor/#{cursor_identifier}",
      method: :put,
      response: [{200, :null}, {400, :null}, {404, :null}, {410, :null}, {503, :null}],
      opts: opts
    })
  end

  @type get_previous_aql_query_cursor_batch_200_json_resp :: %{
          cached: boolean,
          code: integer,
          count: integer | nil,
          error: boolean,
          extra:
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra() | nil,
          hasMore: boolean,
          id: String.t() | nil,
          nextBatchId: String.t() | nil,
          planCacheKey: String.t() | nil,
          result: [any] | nil
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra :: %{
          plan:
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_plan()
            | nil,
          profile:
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_profile()
            | nil,
          stats:
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_stats(),
          warnings: [
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_warnings()
          ]
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_plan :: %{
          collections: [
            Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_plan_collections()
          ],
          estimatedCost: number,
          estimatedNrItems: integer,
          isModificationQuery: boolean,
          nodes: [map],
          rules: [String.t()],
          variables: [map]
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_plan_collections :: %{
          name: String.t(),
          type: String.t()
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_profile :: %{
          executing: number,
          finalizing: number,
          initializing: number,
          "instantiating executors": number,
          "instantiating plan": number,
          "loading collections": number,
          "optimizing ast": number,
          "optimizing plan": number,
          parsing: number
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_stats :: %{
          cacheHits: integer,
          cacheMisses: integer,
          cursorsCreated: integer,
          cursorsRearmed: integer,
          documentLookups: integer,
          executionTime: number,
          filtered: integer,
          fullCount: integer | nil,
          httpRequests: integer,
          intermediateCommits: integer,
          nodes:
            [
              Arangox.Api.Queries.get_previous_aql_query_cursor_batch_200_json_resp_extra_stats_nodes()
            ]
            | nil,
          peakMemoryUsage: integer,
          scannedFull: integer,
          scannedIndex: integer,
          searchParallelism: integer,
          seeks: integer,
          writesExecuted: integer,
          writesIgnored: integer
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_stats_nodes :: %{
          calls: integer,
          id: integer,
          items: integer,
          runtime: number
        }

  @type get_previous_aql_query_cursor_batch_200_json_resp_extra_warnings :: %{
          code: integer,
          message: String.t()
        }

  @type get_previous_aql_query_cursor_batch_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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
  @spec get_previous_aql_query_cursor_batch(
          database_name :: String.t(),
          cursor_identifier :: String.t(),
          batch_identifier :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_previous_aql_query_cursor_batch(
        database_name,
        cursor_identifier,
        batch_identifier,
        opts \\ []
      ) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [
        database_name: database_name,
        cursor_identifier: cursor_identifier,
        batch_identifier: batch_identifier
      ],
      call: {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch},
      url: "/_db/#{database_name}/_api/cursor/#{cursor_identifier}/#{batch_identifier}",
      method: :post,
      response: [
        {200, {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp}},
        {400, {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_400_json_resp}},
        {404, :null},
        {410, :null},
        {503, :null}
      ],
      opts: opts
    })
  end

  @type get_query_cache_properties_200_json_resp :: %{
          includeSystem: boolean | nil,
          maxEntrySize: map | nil,
          maxResults: integer | nil,
          maxResultsSize: integer | nil,
          mode: String.t() | nil
        }

  @doc """
  Get the AQL query results cache configuration

  Returns the global AQL query results cache configuration.

  """
  @spec get_query_cache_properties(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_query_cache_properties(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :get_query_cache_properties},
      url: "/_db/#{database_name}/_api/query-cache/properties",
      method: :get,
      response: [
        {200, {Arangox.Api.Queries, :get_query_cache_properties_200_json_resp}},
        {400, :null}
      ],
      opts: opts
    })
  end

  @type list_aql_queries_200_json_resp :: %{
          bindVars: map,
          dataSources: [String.t()] | nil,
          database: String.t(),
          id: String.t(),
          modificationQuery: boolean,
          peakMemoryUsage: integer,
          query: String.t(),
          runTime: number,
          started: DateTime.t(),
          state: String.t(),
          stream: boolean,
          user: String.t(),
          warnings: integer
        }

  @type list_aql_queries_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_aql_queries_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  ## Options

    * `all`: If set to `true`, will return the currently running queries in all databases,
      not just the selected one.
      Using the parameter is only allowed in the `_system` database and with superuser
      privileges.
      

  """
  @spec list_aql_queries(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_aql_queries(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:all])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :list_aql_queries},
      url: "/_db/#{database_name}/_api/query/current",
      method: :get,
      query: query,
      response: [
        {200, [{Arangox.Api.Queries, :list_aql_queries_200_json_resp}]},
        {400, {Arangox.Api.Queries, :list_aql_queries_400_json_resp}},
        {403, {Arangox.Api.Queries, :list_aql_queries_403_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_aql_user_functions_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: [Arangox.Api.Queries.list_aql_user_functions_200_json_resp_result()]
        }

  @type list_aql_user_functions_200_json_resp_result :: %{
          code: String.t(),
          isDeterministic: boolean,
          name: String.t()
        }

  @type list_aql_user_functions_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  List the registered user-defined AQL functions

  Returns all registered user-defined functions (UDFs) for the use in AQL of the
  current database.

  The call returns a JSON array with status codes and all user functions found under `result`.

  ## Options

    * `namespace`: Returns all registered AQL user functions from the specified namespace.
      

  """
  @spec list_aql_user_functions(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_aql_user_functions(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:namespace])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :list_aql_user_functions},
      url: "/_db/#{database_name}/_api/aqlfunction",
      method: :get,
      query: query,
      response: [
        {200, {Arangox.Api.Queries, :list_aql_user_functions_200_json_resp}},
        {400, {Arangox.Api.Queries, :list_aql_user_functions_400_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_query_cache_plans_200_json_resp :: %{
          bindVars: map,
          created: DateTime.t(),
          dataSources: [String.t()],
          fullCount: boolean,
          hash: String.t(),
          hits: integer,
          memoryUsage: integer,
          query: String.t(),
          queryHash: integer
        }

  @doc """
  List the entries of the AQL query plan cache

  Returns an array containing information about each AQL execution plan
  currently stored in the cache of the selected database.

  This requires read privileges for the current database. In addition, only those
  query plans are returned for which the current user has at least read permissions
  on all collections and Views included in the query.

  """
  @spec list_query_cache_plans(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_query_cache_plans(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :list_query_cache_plans},
      url: "/_db/#{database_name}/_api/query-plan-cache",
      method: :get,
      response: [{200, [{Arangox.Api.Queries, :list_query_cache_plans_200_json_resp}]}],
      opts: opts
    })
  end

  @type list_query_cache_results_200_json_resp :: %{
          bindVars: map | nil,
          dataSources: [String.t()],
          hash: String.t(),
          hits: integer,
          query: String.t(),
          results: integer,
          runTime: number,
          size: integer,
          started: DateTime.t()
        }

  @doc """
  List the entries of the AQL query results cache

  Returns an array containing the AQL query results currently stored in the query results
  cache of the selected database.

  """
  @spec list_query_cache_results(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_query_cache_results(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :list_query_cache_results},
      url: "/_db/#{database_name}/_api/query-cache/entries",
      method: :get,
      response: [
        {200, [{Arangox.Api.Queries, :list_query_cache_results_200_json_resp}]},
        {400, :null}
      ],
      opts: opts
    })
  end

  @type list_slow_aql_queries_200_json_resp :: %{
          bindVars: map,
          dataSources: [String.t()] | nil,
          database: String.t(),
          exitCode: integer,
          id: String.t(),
          modificationQuery: boolean,
          peakMemoryUsage: integer,
          query: String.t(),
          runTime: number,
          started: DateTime.t(),
          state: String.t(),
          stream: boolean,
          user: String.t(),
          warnings: integer
        }

  @type list_slow_aql_queries_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_slow_aql_queries_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  ## Options

    * `all`: If set to `true`, returns the slow queries from all databases, not just
      the specified one.
      Using the parameter is only allowed in the `_system` database and with superuser
      privileges.
      

  """
  @spec list_slow_aql_queries(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_slow_aql_queries(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:all])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Queries, :list_slow_aql_queries},
      url: "/_db/#{database_name}/_api/query/slow",
      method: :get,
      query: query,
      response: [
        {200, [{Arangox.Api.Queries, :list_slow_aql_queries_200_json_resp}]},
        {400, {Arangox.Api.Queries, :list_slow_aql_queries_400_json_resp}},
        {403, {Arangox.Api.Queries, :list_slow_aql_queries_403_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Parse an AQL query

  This endpoint is for query validation only. To actually query the database,
  see `/api/cursor`.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec parse_aql_query(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def parse_aql_query(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :parse_aql_query},
      url: "/_db/#{database_name}/_api/query",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}],
      opts: opts
    })
  end

  @type set_query_cache_properties_200_json_resp :: %{
          includeSystem: boolean | nil,
          maxEntrySize: map | nil,
          maxResults: integer | nil,
          maxResultsSize: integer | nil,
          mode: String.t() | nil
        }

  @doc """
  Set the AQL query results cache configuration

  Adjusts the global properties for the AQL query results cache.

  Changing the properties may invalidate all results currently in the cache.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_query_cache_properties(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_query_cache_properties(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :set_query_cache_properties},
      url: "/_db/#{database_name}/_api/query-cache/properties",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Queries, :set_query_cache_properties_200_json_resp}},
        {400, :null}
      ],
      opts: opts
    })
  end

  @type update_aql_query_tracking_properties_200_json_resp :: %{
          code: integer,
          enabled: boolean,
          error: boolean,
          maxQueryStringLength: integer,
          maxSlowQueries: integer,
          slowQueryThreshold: number,
          slowStreamingQueryThreshold: number,
          trackBindVars: boolean,
          trackSlowQueries: boolean
        }

  @type update_aql_query_tracking_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Update the AQL query tracking configuration

  Modify one or more query tracking properties at runtime for the
  specified database.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_aql_query_tracking_properties(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_aql_query_tracking_properties(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Queries, :update_aql_query_tracking_properties},
      url: "/_db/#{database_name}/_api/query/properties",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Queries, :update_aql_query_tracking_properties_200_json_resp}},
        {400, {Arangox.Api.Queries, :update_aql_query_tracking_properties_400_json_resp}}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:clear_slow_aql_query_list_200_json_resp) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:clear_slow_aql_query_list_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp) do
    [
      cached: :boolean,
      code: :integer,
      count: :integer,
      error: :boolean,
      extra: {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra},
      hasMore: :boolean,
      id: :string,
      nextBatchId: :string,
      planCacheKey: :string,
      result: [:unknown]
    ]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra) do
    [
      plan: {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_plan},
      profile: {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_profile},
      stats: {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_stats},
      warnings: [{Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_warnings}]
    ]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_plan) do
    [
      collections: [
        {Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_plan_collections}
      ],
      estimatedCost: :number,
      estimatedNrItems: :integer,
      isModificationQuery: :boolean,
      nodes: [:map],
      rules: [:string],
      variables: [:map]
    ]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_plan_collections) do
    [name: :string, type: {:enum, ["read", "write", "exclusive"]}]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_profile) do
    [
      executing: :number,
      finalizing: :number,
      initializing: :number,
      "instantiating executors": :number,
      "instantiating plan": :number,
      "loading collections": :number,
      "optimizing ast": :number,
      "optimizing plan": :number,
      parsing: :number
    ]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_stats) do
    [
      cacheHits: :integer,
      cacheMisses: :integer,
      cursorsCreated: :integer,
      cursorsRearmed: :integer,
      documentLookups: :integer,
      executionTime: :number,
      filtered: :integer,
      fullCount: :integer,
      httpRequests: :integer,
      intermediateCommits: :integer,
      nodes: [{Arangox.Api.Queries, :create_aql_query_cursor_201_json_resp_extra_stats_nodes}],
      peakMemoryUsage: :integer,
      scannedFull: :integer,
      scannedIndex: :integer,
      searchParallelism: :integer,
      seeks: :integer,
      writesExecuted: :integer,
      writesIgnored: :integer
    ]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_stats_nodes) do
    [calls: :integer, id: :integer, items: :integer, runtime: :number]
  end

  def __fields__(:create_aql_query_cursor_201_json_resp_extra_warnings) do
    [code: :integer, message: :string]
  end

  def __fields__(:create_aql_query_cursor_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_aql_user_function_200_json_resp) do
    [code: :integer, error: :boolean, isNewlyCreated: :boolean]
  end

  def __fields__(:create_aql_user_function_201_json_resp) do
    [code: :integer, error: :boolean, isNewlyCreated: :boolean]
  end

  def __fields__(:create_aql_user_function_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_aql_query_cache_200_json_resp) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:delete_aql_query_plan_cache_200_json_resp) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:delete_aql_user_function_200_json_resp) do
    [code: :integer, deletedCount: :integer, error: :boolean]
  end

  def __fields__(:delete_aql_user_function_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_aql_user_function_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_aql_query_optimizer_rules_200_json_resp) do
    [
      flags: {Arangox.Api.Queries, :get_aql_query_optimizer_rules_200_json_resp_flags},
      name: :string
    ]
  end

  def __fields__(:get_aql_query_optimizer_rules_200_json_resp_flags) do
    [
      canBeDisabled: :boolean,
      canCreateAdditionalPlans: :boolean,
      clusterOnly: :boolean,
      disabledByDefault: :boolean,
      enterpriseOnly: :boolean,
      hidden: :boolean
    ]
  end

  def __fields__(:get_aql_query_tracking_properties_200_json_resp) do
    [
      code: :integer,
      enabled: :boolean,
      error: :boolean,
      maxQueryStringLength: :integer,
      maxSlowQueries: :integer,
      slowQueryThreshold: :number,
      slowStreamingQueryThreshold: :number,
      trackBindVars: :boolean,
      trackSlowQueries: :boolean
    ]
  end

  def __fields__(:get_aql_query_tracking_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp) do
    [
      cached: :boolean,
      code: :integer,
      count: :integer,
      error: :boolean,
      extra: {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra},
      hasMore: :boolean,
      id: :string,
      nextBatchId: :string,
      planCacheKey: :string,
      result: [:unknown]
    ]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra) do
    [
      plan: {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra_plan},
      profile:
        {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra_profile},
      stats: {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra_stats},
      warnings: [
        {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra_warnings}
      ]
    ]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_plan) do
    [
      collections: [
        {Arangox.Api.Queries,
         :get_next_aql_query_cursor_batch_200_json_resp_extra_plan_collections}
      ],
      estimatedCost: :number,
      estimatedNrItems: :integer,
      isModificationQuery: :boolean,
      nodes: [:map],
      rules: [:string],
      variables: [:map]
    ]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_plan_collections) do
    [name: :string, type: {:enum, ["read", "write", "exclusive"]}]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_profile) do
    [
      executing: :number,
      finalizing: :number,
      initializing: :number,
      "instantiating executors": :number,
      "instantiating plan": :number,
      "loading collections": :number,
      "optimizing ast": :number,
      "optimizing plan": :number,
      parsing: :number
    ]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_stats) do
    [
      cacheHits: :integer,
      cacheMisses: :integer,
      cursorsCreated: :integer,
      cursorsRearmed: :integer,
      documentLookups: :integer,
      executionTime: :number,
      filtered: :integer,
      fullCount: :integer,
      httpRequests: :integer,
      intermediateCommits: :integer,
      nodes: [
        {Arangox.Api.Queries, :get_next_aql_query_cursor_batch_200_json_resp_extra_stats_nodes}
      ],
      peakMemoryUsage: :integer,
      scannedFull: :integer,
      scannedIndex: :integer,
      searchParallelism: :integer,
      seeks: :integer,
      writesExecuted: :integer,
      writesIgnored: :integer
    ]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_stats_nodes) do
    [calls: :integer, id: :integer, items: :integer, runtime: :number]
  end

  def __fields__(:get_next_aql_query_cursor_batch_200_json_resp_extra_warnings) do
    [code: :integer, message: :string]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp) do
    [
      cached: :boolean,
      code: :integer,
      count: :integer,
      error: :boolean,
      extra: {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp_extra},
      hasMore: :boolean,
      id: :string,
      nextBatchId: :string,
      planCacheKey: :string,
      result: [:unknown]
    ]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra) do
    [
      plan: {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp_extra_plan},
      profile:
        {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp_extra_profile},
      stats:
        {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp_extra_stats},
      warnings: [
        {Arangox.Api.Queries, :get_previous_aql_query_cursor_batch_200_json_resp_extra_warnings}
      ]
    ]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_plan) do
    [
      collections: [
        {Arangox.Api.Queries,
         :get_previous_aql_query_cursor_batch_200_json_resp_extra_plan_collections}
      ],
      estimatedCost: :number,
      estimatedNrItems: :integer,
      isModificationQuery: :boolean,
      nodes: [:map],
      rules: [:string],
      variables: [:map]
    ]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_plan_collections) do
    [name: :string, type: {:enum, ["read", "write", "exclusive"]}]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_profile) do
    [
      executing: :number,
      finalizing: :number,
      initializing: :number,
      "instantiating executors": :number,
      "instantiating plan": :number,
      "loading collections": :number,
      "optimizing ast": :number,
      "optimizing plan": :number,
      parsing: :number
    ]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_stats) do
    [
      cacheHits: :integer,
      cacheMisses: :integer,
      cursorsCreated: :integer,
      cursorsRearmed: :integer,
      documentLookups: :integer,
      executionTime: :number,
      filtered: :integer,
      fullCount: :integer,
      httpRequests: :integer,
      intermediateCommits: :integer,
      nodes: [
        {Arangox.Api.Queries,
         :get_previous_aql_query_cursor_batch_200_json_resp_extra_stats_nodes}
      ],
      peakMemoryUsage: :integer,
      scannedFull: :integer,
      scannedIndex: :integer,
      searchParallelism: :integer,
      seeks: :integer,
      writesExecuted: :integer,
      writesIgnored: :integer
    ]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_stats_nodes) do
    [calls: :integer, id: :integer, items: :integer, runtime: :number]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_200_json_resp_extra_warnings) do
    [code: :integer, message: :string]
  end

  def __fields__(:get_previous_aql_query_cursor_batch_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_query_cache_properties_200_json_resp) do
    [
      includeSystem: :boolean,
      maxEntrySize: :map,
      maxResults: :integer,
      maxResultsSize: :integer,
      mode: {:enum, ["off", "on", "demand"]}
    ]
  end

  def __fields__(:list_aql_queries_200_json_resp) do
    [
      bindVars: :map,
      dataSources: [:string],
      database: :string,
      id: :string,
      modificationQuery: :boolean,
      peakMemoryUsage: :integer,
      query: :string,
      runTime: :number,
      started: {:string, "date-time"},
      state:
        {:enum,
         [
           "initializing",
           "parsing",
           "optimizing ast",
           "loading collections",
           "instantiating plan",
           "optimizing plan",
           "instantiating executors",
           "executing",
           "finalizing",
           "finished",
           "killed",
           "invalid"
         ]},
      stream: :boolean,
      user: :string,
      warnings: :integer
    ]
  end

  def __fields__(:list_aql_queries_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_aql_queries_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_aql_user_functions_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: [{Arangox.Api.Queries, :list_aql_user_functions_200_json_resp_result}]
    ]
  end

  def __fields__(:list_aql_user_functions_200_json_resp_result) do
    [code: :string, isDeterministic: :boolean, name: :string]
  end

  def __fields__(:list_aql_user_functions_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_query_cache_plans_200_json_resp) do
    [
      bindVars: :map,
      created: {:string, "date-time"},
      dataSources: [:string],
      fullCount: :boolean,
      hash: :string,
      hits: :integer,
      memoryUsage: :integer,
      query: :string,
      queryHash: :integer
    ]
  end

  def __fields__(:list_query_cache_results_200_json_resp) do
    [
      bindVars: :map,
      dataSources: [:string],
      hash: :string,
      hits: :integer,
      query: :string,
      results: :integer,
      runTime: :number,
      size: :integer,
      started: {:string, "date-time"}
    ]
  end

  def __fields__(:list_slow_aql_queries_200_json_resp) do
    [
      bindVars: :map,
      dataSources: [:string],
      database: :string,
      exitCode: :integer,
      id: :string,
      modificationQuery: :boolean,
      peakMemoryUsage: :integer,
      query: :string,
      runTime: :number,
      started: {:string, "date-time"},
      state: {:enum, ["finished", "killed", "invalid"]},
      stream: :boolean,
      user: :string,
      warnings: :integer
    ]
  end

  def __fields__(:list_slow_aql_queries_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_slow_aql_queries_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:set_query_cache_properties_200_json_resp) do
    [
      includeSystem: :boolean,
      maxEntrySize: :map,
      maxResults: :integer,
      maxResultsSize: :integer,
      mode: {:enum, ["off", "on", "demand"]}
    ]
  end

  def __fields__(:update_aql_query_tracking_properties_200_json_resp) do
    [
      code: :integer,
      enabled: :boolean,
      error: :boolean,
      maxQueryStringLength: :integer,
      maxSlowQueries: :integer,
      slowQueryThreshold: :number,
      slowStreamingQueryThreshold: :number,
      trackBindVars: :boolean,
      trackSlowQueries: :boolean
    ]
  end

  def __fields__(:update_aql_query_tracking_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
