defmodule Arangox.Api.Monitoring do
  @moduledoc """
  ArangoDB's Monitoring operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

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
  """
  @spec log(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def log(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "log"],
      query: [
        upto: "upto",
        level: "level",
        start: "start",
        size: "size",
        offset: "offset",
        search: "search",
        sort: "sort",
        server_id: "serverId"
      ],
      opts: opts
    )
  end

  @doc """
  Get the global server logs (deprecated). Raises on error.

  See `log/1`.
  """
  @spec log!(Arangox.conn(), keyword) :: term
  def log!(conn, opts \\ []) do
    case log(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec log_entries(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def log_entries(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "log", "entries"],
      query: [
        upto: "upto",
        level: "level",
        start: "start",
        size: "size",
        offset: "offset",
        search: "search",
        sort: "sort",
        server_id: "serverId"
      ],
      opts: opts
    )
  end

  @doc """
  Get the global server logs. Raises on error.

  See `log_entries/1`.
  """
  @spec log_entries!(Arangox.conn(), keyword) :: term
  def log_entries!(conn, opts \\ []) do
    case log_entries(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec log_level(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def log_level(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "log", "level"],
      query: [server_id: "serverId", with_appenders: "withAppenders"],
      opts: opts
    )
  end

  @doc """
  Get the server log levels. Raises on error.

  See `log_level/1`.
  """
  @spec log_level!(Arangox.conn(), keyword) :: term
  def log_level!(conn, opts \\ []) do
    case log_level(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec metrics(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def metrics(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "metrics"],
      query: [server_id: "serverId"],
      opts: opts
    )
  end

  @doc """
  Get the metrics. Raises on error.

  See `metrics/1`.
  """
  @spec metrics!(Arangox.conn(), keyword) :: term
  def metrics!(conn, opts \\ []) do
    case metrics(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec metrics_v2(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def metrics_v2(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "metrics", "v2"],
      query: [server_id: "serverId"],
      opts: opts
    )
  end

  @doc """
  Get the metrics (deprecated). Raises on error.

  See `metrics_v2/1`.
  """
  @spec metrics_v2!(Arangox.conn(), keyword) :: term
  def metrics_v2!(conn, opts \\ []) do
    case metrics_v2(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec recent_api_calls(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def recent_api_calls(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "api-calls"],
      opts: opts
    )
  end

  @doc """
  Get recent API calls. Raises on error.

  See `recent_api_calls/1`.
  """
  @spec recent_api_calls!(Arangox.conn(), keyword) :: term
  def recent_api_calls!(conn, opts \\ []) do
    case recent_api_calls(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec recent_aql_queries(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def recent_aql_queries(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "aql-queries"],
      opts: opts
    )
  end

  @doc """
  Get recent AQL queries. Raises on error.

  See `recent_aql_queries/1`.
  """
  @spec recent_aql_queries!(Arangox.conn(), keyword) :: term
  def recent_aql_queries!(conn, opts \\ []) do
    case recent_aql_queries(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec reset_log_level(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def reset_log_level(conn, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_admin", "log", "level"],
      query: [server_id: "serverId"],
      opts: opts
    )
  end

  @doc """
  Reset the server log levels. Raises on error.

  See `reset_log_level/1`.
  """
  @spec reset_log_level!(Arangox.conn(), keyword) :: term
  def reset_log_level!(conn, opts \\ []) do
    case reset_log_level(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec set_log_level(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def set_log_level(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "log", "level"],
      body: body,
      query: [server_id: "serverId", with_appenders: "withAppenders"],
      opts: opts
    )
  end

  @doc """
  Set the server log levels. Raises on error.

  See `set_log_level/2`.
  """
  @spec set_log_level!(Arangox.conn(), term, keyword) :: term
  def set_log_level!(conn, body, opts \\ []) do
    case set_log_level(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec set_structured_log(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def set_structured_log(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "log", "structured"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set the structured log settings. Raises on error.

  See `set_structured_log/2`.
  """
  @spec set_structured_log!(Arangox.conn(), term, keyword) :: term
  def set_structured_log!(conn, body, opts \\ []) do
    case set_structured_log(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec statistics(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def statistics(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "statistics"],
      opts: opts
    )
  end

  @doc """
  Get the statistics. Raises on error.

  See `statistics/1`.
  """
  @spec statistics!(Arangox.conn(), keyword) :: term
  def statistics!(conn, opts \\ []) do
    case statistics(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec statistics_description(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def statistics_description(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "statistics-description"],
      opts: opts
    )
  end

  @doc """
  Get the statistics description. Raises on error.

  See `statistics_description/1`.
  """
  @spec statistics_description!(Arangox.conn(), keyword) :: term
  def statistics_description!(conn, opts \\ []) do
    case statistics_description(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  @spec structured_log(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def structured_log(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "log", "structured"],
      opts: opts
    )
  end

  @doc """
  Get the structured log settings. Raises on error.

  See `structured_log/1`.
  """
  @spec structured_log!(Arangox.conn(), keyword) :: term
  def structured_log!(conn, opts \\ []) do
    case structured_log(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the usage metrics

  Returns detailed shard usage metrics on DB-Servers.

  These metrics can be enabled by setting the
  [`--server.export-shard-usage-metrics` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--serverexport-shard-usage-metrics)
  to `enabled-per-shard` to make DB-Servers collect per-shard
  usage metrics, or to `enabled-per-shard-per-user` to make DB-Servers collect
  usage metrics per shard and per user whenever a shard is accessed.
  """
  @spec usage_metrics(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def usage_metrics(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "usage-metrics"],
      query: [server_id: "serverId"],
      opts: opts
    )
  end

  @doc """
  Get the usage metrics. Raises on error.

  See `usage_metrics/1`.
  """
  @spec usage_metrics!(Arangox.conn(), keyword) :: term
  def usage_metrics!(conn, opts \\ []) do
    case usage_metrics(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
