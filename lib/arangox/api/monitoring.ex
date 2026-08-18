defmodule Arangox.Api.Monitoring do
  @moduledoc """
  Provides API endpoints related to monitoring
  """

  @default_client Arangox.Api.Client

  @type get_log_200_json_resp :: %{
          level: String.t(),
          lid: [String.t()],
          text: String.t(),
          timestamp: [String.t()],
          topic: String.t(),
          totalAmount: integer
        }

  @doc """
  Get the global server logs (deprecated)

  > **WARNING:**
  This endpoint should no longer be used. It is deprecated from version
  3.8.0 onward and removed in ArangoDB 4.0.
  Use `/_admin/log/entries` instead, which provides the same data in a more
  intuitive and easier to process format.

  Returns fatal, error, warning or info log messages from the server's global log.
  The result is a JSON object with the attributes described below.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Options

    * `upto`: Returns all log entries up to log level `upto`. Note that `upto` must be:
      - `fatal` or `0`
      - `error` or `1`
      - `warning` or `2`
      - `info` or `3`
      - `debug` or `4`
      - `trace` or `5`
      
    * `level`: Returns all log entries of log level `level`. Note that the query parameters
      `upto` and `level` are mutually exclusive.
      
    * `start`: Returns all log entries such that their log entry identifier (`lid` value)
      is greater or equal to `start`.
      
    * `size`: Restricts the result to at most `size` log entries.
      
    * `offset`: Starts to return log entries skipping the first `offset` log entries. `offset`
      and `size` can be used for pagination.
      
    * `search`: Only return the log entries containing the text specified in `search`.
      
    * `sort`: Sort the log entries either ascending (if `sort` is `asc`) or descending
      (if `sort` is `desc`) according to their `lid` values. Note that the `lid`
      imposes a chronological order.
      
    * `serverId`: Returns all log entries of the specified server. All other query parameters
      remain valid. If no serverId is given, the asked server
      will reply. This parameter is only meaningful on Coordinators.
      

  """
  @spec get_log(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_log(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:level, :offset, :search, :serverId, :size, :sort, :start, :upto])

    client.request(%{
      args: [],
      call: {Arangox.Api.Monitoring, :get_log},
      url: "/_admin/log",
      method: :get,
      query: query,
      response: [
        {200, {Arangox.Api.Monitoring, :get_log_200_json_resp}},
        {400, :null},
        {403, :null}
      ],
      opts: opts
    })
  end

  @doc """
  Get the global server logs

  Returns fatal, error, warning or info log messages from the server's global log.
  The result is a JSON object with the following properties:

  - **total**: the total amount of log entries before pagination
  - **messages**: an array with log messages that matched the criteria

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Options

    * `upto`: Returns all log entries up to log level `upto`. Note that `upto` must be:
      - `fatal` or `0`
      - `error` or `1`
      - `warning` or `2`
      - `info` or `3`
      - `debug` or `4`
      - `trace` or `5`
      
    * `level`: Returns all log entries of log level `level`. Note that the query parameters
      `upto` and `level` are mutually exclusive.
      
    * `start`: Returns all log entries such that their log entry identifier (`id` value)
      is greater or equal to `start`.
      
    * `size`: Restricts the result to at most `size` log entries.
      
    * `offset`: Starts to return log entries skipping the first `offset` log entries. `offset`
      and `size` can be used for pagination.
      
    * `search`: Only return the log entries containing the text specified in `search`.
      
    * `sort`: Sort the log entries either ascending (if `sort` is `asc`) or descending
      (if `sort` is `desc`) according to their `id` values. Note that the `id`
      imposes a chronological order.
      
    * `serverId`: Returns all log entries of the specified server. All other query parameters
      remain valid. If no serverId is given, the asked server
      will reply. This parameter is only meaningful on Coordinators.
      

  """
  @spec get_log_entries(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_log_entries(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:level, :offset, :search, :serverId, :size, :sort, :start, :upto])

    client.request(%{
      args: [],
      call: {Arangox.Api.Monitoring, :get_log_entries},
      url: "/_admin/log/entries",
      method: :get,
      query: query,
      response: [{200, :null}, {400, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Get the server log levels

  Returns the server's current log level settings.
  The result is a JSON object with the log topics being the object keys, and
  the log levels being the object values.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Options

    * `serverId`: Forwards the request to the specified server.
      
    * `withAppenders`: Set this option to `true` to return the individual log level settings
      of all log outputs (`appenders`) as well as the `global` settings.
      
      The response structure is as follows:
      
      ```json
      {
        "global": {
          "agency": "INFO",
          "agencycomm": "INFO",
          "agencystore": "WARNING",
          ...
        },
        "appenders": {
          "-": {
            "agency": "INFO",
            "agencycomm": "INFO",
            "agencystore": "WARNING",
            ...
          },
          "file:///path/to/file": {
            "agency": "INFO",
            "agencycomm": "INFO",
            "agencystore": "WARNING",
            ...
          },
          ...
        }
      }
      ```
      

  """
  @spec get_log_level(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_log_level(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId, :withAppenders])

    client.request(%{
      args: [],
      call: {Arangox.Api.Monitoring, :get_log_level},
      url: "/_admin/log/level",
      method: :get,
      query: query,
      response: [{200, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Get the metrics

  Returns the instance's current metrics in Prometheus format. The
  returned document collects all instance metrics, which are measured
  at any given time and exposes them for collection by Prometheus.

  The document contains different metrics and metrics groups dependent
  on the role of the queried instance. All exported metrics are
  published with a `arangodb_` or `rocksdb_` prefix to distinguish them
  from other collected data.

  The API then needs to be added to the Prometheus configuration file
  for collection.

  ## Options

    * `serverId`: Returns metrics of the specified server. If no serverId is given, the asked
      server will reply. This parameter is only meaningful on Coordinators.
      

  """
  @spec get_metrics(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_metrics(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_metrics},
      url: "/_db/#{database_name}/_admin/metrics",
      method: :get,
      query: query,
      response: [{200, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Get the metrics (deprecated)

  > **WARNING:**
  The `GET /_admin/metrics` and `GET /_admin/metrics/v2` endpoints return
  the same metrics since ArangoDB v3.10.0. The latter is deprecated and
  removed in v4.0.

  Returns the instance's current metrics in Prometheus format. The
  returned document collects all instance metrics, which are measured
  at any given time and exposes them for collection by Prometheus.

  The document contains different metrics and metrics groups dependent
  on the role of the queried instance. All exported metrics are
  published with a `arangodb_` or `rocksdb_` prefix to distinguish
  them from other collected data.

  The API then needs to be added to the Prometheus configuration file
  for collection.

  ## Options

    * `serverId`: Returns metrics of the specified server. If no serverId is given, the asked
      server will reply. This parameter is only meaningful on Coordinators.
      

  """
  @spec get_metrics_v2(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_metrics_v2(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_metrics_v2},
      url: "/_db/#{database_name}/_admin/metrics/v2",
      method: :get,
      query: query,
      response: [{200, :null}, {404, :null}],
      opts: opts
    })
  end

  @type get_recent_api_calls_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Monitoring.get_recent_api_calls_200_json_resp_result()
        }

  @type get_recent_api_calls_200_json_resp_result :: %{
          calls: [Arangox.Api.Monitoring.get_recent_api_calls_200_json_resp_result_calls()]
        }

  @type get_recent_api_calls_200_json_resp_result_calls :: %{
          database: String.t() | nil,
          path: String.t() | nil,
          requestType: String.t() | nil,
          timeStamp: DateTime.t() | nil
        }

  @type get_recent_api_calls_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_recent_api_calls_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_recent_api_calls_501_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get recent API calls

  Get a list of the most recent requests with a timestamp and the endpoint.
  In cluster deployments, the list contains only those requests that were
  submitted to the Coordinator you call this endpoint on.
  This feature is for debugging purposes.

  You can control how much memory is used to record API calls with the
  `--server.api-recording-memory-limit` startup option.

  You can disable this and the `/_admin/server/aql-queries` endpoint
  with the `--log.recording-api-enabled` startup option.

  Whether API calls are recorded is independently controlled by the
  `--server.api-call-recording` startup option.
  The endpoint returns an empty list of calls if turned off.

  """
  @spec get_recent_api_calls(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_recent_api_calls(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_recent_api_calls},
      url: "/_db/#{database_name}/_admin/server/api-calls",
      method: :get,
      response: [
        {200, {Arangox.Api.Monitoring, :get_recent_api_calls_200_json_resp}},
        {401, {Arangox.Api.Monitoring, :get_recent_api_calls_401_json_resp}},
        {403, {Arangox.Api.Monitoring, :get_recent_api_calls_403_json_resp}},
        {501, {Arangox.Api.Monitoring, :get_recent_api_calls_501_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_recent_aql_queries_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Monitoring.get_recent_aql_queries_200_json_resp_result()
        }

  @type get_recent_aql_queries_200_json_resp_result :: %{
          queries: [Arangox.Api.Monitoring.get_recent_aql_queries_200_json_resp_result_queries()]
        }

  @type get_recent_aql_queries_200_json_resp_result_queries :: %{
          bindVars: map | nil,
          database: String.t() | nil,
          query: String.t() | nil,
          timeStamp: DateTime.t() | nil
        }

  @type get_recent_aql_queries_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_recent_aql_queries_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_recent_aql_queries_501_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get recent AQL queries

  Get a list of the most recent AQL queries with a timestamp and
  information about the submitted query. In cluster deployments, the list
  contains only those queries that were submitted to the Coordinator you
  call this endpoint on. This feature is for debugging purposes.

  You can control how much memory is used to record AQL queries with the
  `--server.aql-recording-memory-limit` startup option.

  You can disable this and the `/_admin/server/api-calls` endpoint
  with the `--log.recording-api-enabled` startup option.

  Whether AQL queries are recorded is independently controlled by the
  `--server.aql-query-recording` startup option.
  The endpoint returns an empty list of queries if turned off.

  """
  @spec get_recent_aql_queries(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_recent_aql_queries(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_recent_aql_queries},
      url: "/_db/#{database_name}/_admin/server/aql-queries",
      method: :get,
      response: [
        {200, {Arangox.Api.Monitoring, :get_recent_aql_queries_200_json_resp}},
        {401, {Arangox.Api.Monitoring, :get_recent_aql_queries_401_json_resp}},
        {403, {Arangox.Api.Monitoring, :get_recent_aql_queries_403_json_resp}},
        {501, {Arangox.Api.Monitoring, :get_recent_aql_queries_501_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_statistics_200_json_resp :: %{
          client: Arangox.Api.Monitoring.get_statistics_200_json_resp_client(),
          code: integer,
          enabled: boolean,
          error: boolean,
          errorMessage: String.t(),
          http: Arangox.Api.Monitoring.get_statistics_200_json_resp_http(),
          server: Arangox.Api.Monitoring.get_statistics_200_json_resp_server(),
          system: Arangox.Api.Monitoring.get_statistics_200_json_resp_system(),
          time: integer
        }

  @type get_statistics_200_json_resp_client :: %{
          bytesReceived:
            Arangox.Api.Monitoring.get_statistics_200_json_resp_client_bytes_received(),
          bytesSent: Arangox.Api.Monitoring.get_statistics_200_json_resp_client_bytes_sent(),
          connectionTime:
            Arangox.Api.Monitoring.get_statistics_200_json_resp_client_connection_time(),
          httpConnections: integer,
          ioTime: Arangox.Api.Monitoring.get_statistics_200_json_resp_client_io_time(),
          queueTime: Arangox.Api.Monitoring.get_statistics_200_json_resp_client_queue_time(),
          requestTime: Arangox.Api.Monitoring.get_statistics_200_json_resp_client_request_time(),
          totalTime: Arangox.Api.Monitoring.get_statistics_200_json_resp_client_total_time()
        }

  @type get_statistics_200_json_resp_client_bytes_received :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_bytes_sent :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_connection_time :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_io_time :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_queue_time :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_request_time :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_client_total_time :: %{
          count: integer,
          counts: [integer],
          sum: number
        }

  @type get_statistics_200_json_resp_http :: %{
          requestsAsync: integer,
          requestsDelete: integer,
          requestsGet: integer,
          requestsHead: integer,
          requestsOptions: integer,
          requestsOther: integer,
          requestsPatch: integer,
          requestsPost: integer,
          requestsPut: integer,
          requestsTotal: integer
        }

  @type get_statistics_200_json_resp_server :: %{
          physicalMemory: integer,
          threads: Arangox.Api.Monitoring.get_statistics_200_json_resp_server_threads(),
          transactions: Arangox.Api.Monitoring.get_statistics_200_json_resp_server_transactions(),
          uptime: integer,
          v8Context: Arangox.Api.Monitoring.get_statistics_200_json_resp_server_v8_context()
        }

  @type get_statistics_200_json_resp_server_threads :: %{
          "in-progress": integer,
          queued: integer,
          "scheduler-threads": integer
        }

  @type get_statistics_200_json_resp_server_transactions :: %{
          aborted: integer,
          committed: integer,
          intermediateCommits: integer,
          started: integer
        }

  @type get_statistics_200_json_resp_server_v8_context :: %{
          available: integer,
          busy: integer,
          dirty: integer,
          free: integer,
          max: integer,
          memory: [Arangox.Api.Monitoring.get_statistics_200_json_resp_server_v8_context_memory()],
          min: integer
        }

  @type get_statistics_200_json_resp_server_v8_context_memory :: %{
          contextId: integer,
          countOfTimes: integer,
          heapMax: integer,
          heapMin: integer,
          tMax: number
        }

  @type get_statistics_200_json_resp_system :: %{
          majorPageFaults: integer,
          minorPageFaults: integer,
          numberOfThreads: integer,
          residentSize: integer,
          residentSizePercent: number,
          systemTime: number,
          userTime: number,
          virtualSize: integer
        }

  @doc """
  Get the statistics

  > **WARNING:**
  This endpoint should no longer be used. It is deprecated from
  version 3.8.0 onward and removed in ArangoDB v4.0.
  Use `GET /_admin/metrics` instead, which provides the data exposed by
  this API and a lot more.

  Returns the statistics information. The returned object contains the
  statistics figures grouped together according to the description returned by
  `/_admin/statistics-description`. For instance, to access a figure `userTime`
  from the group `system`, you first select the sub-object describing the
  group stored in `system` and in that sub-object the value for `userTime` is
  stored in the attribute of the same name.

  In case of a distribution, the returned object contains the total count in
  `count` and the distribution list in `counts`. The sum (or total) of the
  individual values is returned in `sum`.

  The transaction statistics show the local started, committed and aborted
  transactions as well as intermediate commits done for the server queried. The
  intermediate commit count will only take non zero values for the RocksDB
  storage engine. Coordinators do almost no local transactions themselves in
  their local databases, therefore cluster transactions (transactions started on a
  Coordinator that require DB-Servers to finish before the transactions is
  committed cluster wide) are just added to their local statistics. This means
  that the statistics you would see for a single server is roughly what you can
  expect in a cluster setup using a single Coordinator querying this Coordinator.
  Just with the difference that cluster transactions have no notion of
  intermediate commits and will not increase the value.

  """
  @spec get_statistics(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_statistics(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_statistics},
      url: "/_db/#{database_name}/_admin/statistics",
      method: :get,
      response: [{200, {Arangox.Api.Monitoring, :get_statistics_200_json_resp}}, {404, :null}],
      opts: opts
    })
  end

  @type get_statistics_description_200_json_resp :: %{
          code: integer,
          error: boolean,
          figures: [Arangox.Api.Monitoring.get_statistics_description_200_json_resp_figures()],
          groups: [Arangox.Api.Monitoring.get_statistics_description_200_json_resp_groups()]
        }

  @type get_statistics_description_200_json_resp_figures :: %{
          cuts: String.t(),
          description: String.t(),
          group: String.t(),
          identifier: String.t(),
          name: String.t(),
          type: String.t(),
          units: String.t()
        }

  @type get_statistics_description_200_json_resp_groups :: %{
          description: String.t(),
          group: String.t(),
          name: String.t()
        }

  @doc """
  Get the statistics description

  > **WARNING:**
  This endpoint should no longer be used. It is deprecated from
  version 3.8.0 onward and removed in ArangoDB v4.0.
  Use `GET /_admin/metrics` instead, which provides the data exposed by the
  statistics API and a lot more.

  Returns a description of the statistics returned by `/_admin/statistics`.
  The returned objects contains an array of statistics groups in the attribute
  `groups` and an array of statistics figures in the attribute `figures`.

  A statistics group is described by

  - `group`: The identifier of the group.
  - `name`: The name of the group.
  - `description`: A description of the group.

  A statistics figure is described by

  - `group`: The identifier of the group to which this figure belongs.
  - `identifier`: The identifier of the figure. It is unique within the group.
  - `name`: The name of the figure.
  - `description`: A description of the figure.
  - `type`: Either `current`, `accumulated`, or `distribution`.
  - `cuts`: The distribution vector.
  - `units`: Units in which the figure is measured.

  """
  @spec get_statistics_description(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_statistics_description(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_statistics_description},
      url: "/_db/#{database_name}/_admin/statistics-description",
      method: :get,
      response: [{200, {Arangox.Api.Monitoring, :get_statistics_description_200_json_resp}}],
      opts: opts
    })
  end

  @doc """
  Get the structured log settings

  Returns the server's current structured log settings.
  The result is a JSON object with the log parameters being the object keys, and
  `true` or `false` being the object values, meaning the parameters are either
  enabled or disabled.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  """
  @spec get_structured_log(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_structured_log(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Monitoring, :get_structured_log},
      url: "/_admin/log/structured",
      method: :get,
      response: [{200, :null}, {403, :null}, {405, :null}],
      opts: opts
    })
  end

  @doc """
  Get the usage metrics

  Returns detailed shard usage metrics on DB-Servers.

  These metrics can be enabled by setting the
  [`--server.export-shard-usage-metrics` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--serverexport-shard-usage-metrics)
  to `enabled-per-shard` to make DB-Servers collect per-shard
  usage metrics, or to `enabled-per-shard-per-user` to make DB-Servers collect
  usage metrics per shard and per user whenever a shard is accessed.

  ## Options

    * `serverId`: Returns the usage metrics of the specified server (`PRMR-...`).
      If no `serverId` is specified, the asked server replies.
      This parameter is only meaningful on Coordinators.
      

  """
  @spec get_usage_metrics(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_usage_metrics(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Monitoring, :get_usage_metrics},
      url: "/_db/#{database_name}/_admin/usage-metrics",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Reset the server log levels

  Revert the server's log level settings to the values they had at startup,
  as determined by the startup options specified on the command-line, a
  configuration file, and the factory defaults.

  The result is a JSON object with the log topics being the object keys, and
  the log levels being the object values.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Options

    * `serverId`: Forwards the request to the specified server.
      

  """
  @spec reset_log_level(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def reset_log_level(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId])

    client.request(%{
      args: [],
      call: {Arangox.Api.Monitoring, :reset_log_level},
      url: "/_admin/log/level",
      method: :delete,
      query: query,
      response: [{200, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Set the server log levels

  Modifies and returns the server's current log level settings.
  The request body must be a JSON string with a log level or a JSON object with the
  log topics being the object keys and the log levels being the object values.

  If only a JSON string is specified as input, the log level is adjusted for the
  "general" log topic only. If a JSON object is specified as input, the log levels will
  be set only for the log topic mentioned in the input object, but preserved for every
  other log topic.
  To set the log level for all log levels to a specific value, it is possible to hand
  in the special pseudo log topic "all".

  The result is a JSON object with all available log topics being the object keys, and
  the adjusted log levels being the object values.

  Possible log levels are:
  - `FATAL` - Only critical errors are logged after which the _arangod_
    process terminates.
  - `ERROR` - Only errors are logged. You should investigate and fix errors
    as they may harm your production.
  - `WARNING` - Errors and warnings are logged. Warnings may be serious
    application-wise and can indicate issues that might lead to errors
    later on.
  - `INFO` - Errors, warnings, and general information is logged.
  - `DEBUG` - Outputs debug messages used in the development of ArangoDB
    in addition to the above.
  - `TRACE` - Logs detailed tracing of operations in addition to the above.
    This can flood the log. Don't use this log level in production.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Options

    * `serverId`: Forwards the request to the specified server.
      
    * `withAppenders`: Set this option to `true` to set individual log level settings
      for log outputs (`appenders`). The request and response structure is
      as follows:
      
      ```json
      {
        "global": {
          "agency": "INFO",
          "agencycomm": "INFO",
          "agencystore": "WARNING",
          ...
        },
        "appenders": {
          "-": {
            "agency": "INFO",
            "agencycomm": "INFO",
            "agencystore": "WARNING",
            ...
          },
          "file:///path/to/file": {
            "agency": "INFO",
            "agencycomm": "INFO",
            "agencystore": "WARNING",
            ...
          },
          ...
        }
      }
      ```
      
      Changing the `global` settings affects all outputs and is the same
      as setting a log level with this option turned off.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_log_level(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_log_level(body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:serverId, :withAppenders])

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Monitoring, :set_log_level},
      url: "/_admin/log/level",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {403, :null}, {405, :null}],
      opts: opts
    })
  end

  @doc """
  Set the structured log settings

  Modifies and returns the server's current structured log settings.
  The request body must be a JSON object with the structured log parameters
  being the object keys and `true` or `false` object values, for either
  enabling or disabling the parameters.

  The result is a JSON object with all available structured log parameters being
  the object keys, and `true` or `false` being the object values, meaning the
  parameter in the object key is either enabled or disabled.

  This API can be turned off via the startup option `--log.api-enabled`. In case
  the API is disabled, all requests will be responded to with HTTP 403. If the
  API is enabled, accessing it requires admin privileges, or even superuser
  privileges, depending on the value of the `--log.api-enabled` startup option.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_structured_log(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_structured_log(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Monitoring, :set_structured_log},
      url: "/_admin/log/structured",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {403, :null}, {405, :null}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:get_log_200_json_resp) do
    [
      level: :string,
      lid: [:string],
      text: :string,
      timestamp: [:string],
      topic: :string,
      totalAmount: :integer
    ]
  end

  def __fields__(:get_recent_api_calls_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Monitoring, :get_recent_api_calls_200_json_resp_result}
    ]
  end

  def __fields__(:get_recent_api_calls_200_json_resp_result) do
    [calls: [{Arangox.Api.Monitoring, :get_recent_api_calls_200_json_resp_result_calls}]]
  end

  def __fields__(:get_recent_api_calls_200_json_resp_result_calls) do
    [
      database: :string,
      path: :string,
      requestType: {:enum, ["GET", "PATCH", "PUT", "DELETE", "HEAD"]},
      timeStamp: {:string, "date-time"}
    ]
  end

  def __fields__(:get_recent_api_calls_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_recent_api_calls_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_recent_api_calls_501_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_recent_aql_queries_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Monitoring, :get_recent_aql_queries_200_json_resp_result}
    ]
  end

  def __fields__(:get_recent_aql_queries_200_json_resp_result) do
    [queries: [{Arangox.Api.Monitoring, :get_recent_aql_queries_200_json_resp_result_queries}]]
  end

  def __fields__(:get_recent_aql_queries_200_json_resp_result_queries) do
    [bindVars: :map, database: :string, query: :string, timeStamp: {:string, "date-time"}]
  end

  def __fields__(:get_recent_aql_queries_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_recent_aql_queries_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_recent_aql_queries_501_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_statistics_200_json_resp) do
    [
      client: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client},
      code: :integer,
      enabled: :boolean,
      error: :boolean,
      errorMessage: :string,
      http: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_http},
      server: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_server},
      system: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_system},
      time: :integer
    ]
  end

  def __fields__(:get_statistics_200_json_resp_client) do
    [
      bytesReceived:
        {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_bytes_received},
      bytesSent: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_bytes_sent},
      connectionTime:
        {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_connection_time},
      httpConnections: :integer,
      ioTime: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_io_time},
      queueTime: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_queue_time},
      requestTime: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_request_time},
      totalTime: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_client_total_time}
    ]
  end

  def __fields__(:get_statistics_200_json_resp_client_bytes_received) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_bytes_sent) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_connection_time) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_io_time) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_queue_time) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_request_time) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_client_total_time) do
    [count: :integer, counts: [:integer], sum: :number]
  end

  def __fields__(:get_statistics_200_json_resp_http) do
    [
      requestsAsync: :integer,
      requestsDelete: :integer,
      requestsGet: :integer,
      requestsHead: :integer,
      requestsOptions: :integer,
      requestsOther: :integer,
      requestsPatch: :integer,
      requestsPost: :integer,
      requestsPut: :integer,
      requestsTotal: :integer
    ]
  end

  def __fields__(:get_statistics_200_json_resp_server) do
    [
      physicalMemory: :integer,
      threads: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_server_threads},
      transactions: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_server_transactions},
      uptime: :integer,
      v8Context: {Arangox.Api.Monitoring, :get_statistics_200_json_resp_server_v8_context}
    ]
  end

  def __fields__(:get_statistics_200_json_resp_server_threads) do
    ["in-progress": :integer, queued: :integer, "scheduler-threads": :integer]
  end

  def __fields__(:get_statistics_200_json_resp_server_transactions) do
    [aborted: :integer, committed: :integer, intermediateCommits: :integer, started: :integer]
  end

  def __fields__(:get_statistics_200_json_resp_server_v8_context) do
    [
      available: :integer,
      busy: :integer,
      dirty: :integer,
      free: :integer,
      max: :integer,
      memory: [{Arangox.Api.Monitoring, :get_statistics_200_json_resp_server_v8_context_memory}],
      min: :integer
    ]
  end

  def __fields__(:get_statistics_200_json_resp_server_v8_context_memory) do
    [
      contextId: :integer,
      countOfTimes: :integer,
      heapMax: :integer,
      heapMin: :integer,
      tMax: :number
    ]
  end

  def __fields__(:get_statistics_200_json_resp_system) do
    [
      majorPageFaults: :integer,
      minorPageFaults: :integer,
      numberOfThreads: :integer,
      residentSize: :integer,
      residentSizePercent: :number,
      systemTime: :number,
      userTime: :number,
      virtualSize: :integer
    ]
  end

  def __fields__(:get_statistics_description_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      figures: [{Arangox.Api.Monitoring, :get_statistics_description_200_json_resp_figures}],
      groups: [{Arangox.Api.Monitoring, :get_statistics_description_200_json_resp_groups}]
    ]
  end

  def __fields__(:get_statistics_description_200_json_resp_figures) do
    [
      cuts: :string,
      description: :string,
      group: :string,
      identifier: :string,
      name: :string,
      type: :string,
      units: :string
    ]
  end

  def __fields__(:get_statistics_description_200_json_resp_groups) do
    [description: :string, group: :string, name: :string]
  end
end
