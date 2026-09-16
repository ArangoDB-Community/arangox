defmodule Arangox.API.Administration do
  @moduledoc """
  ArangoDB's Administration operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

  @doc """
  List crash dumps

  <small>Introduced in: v3.12.8</small>

  Return the list of crash dump directory identifiers (UUIDs).

  When the server crashes, the crash handler writes diagnostic data into
  a per-crash directory under `<database-directory>/crashes/<uuid>/`.
  Each dump includes information such as recent API calls and AQL queries,
  a backtrace, and system information.

  The server keeps the most recent 10 crash dumps. Older ones are removed
  during startup.

  This endpoint requires *administrate* access to the `_system` database.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => []
      }
  """
  @spec all_crash_dumps(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_crash_dumps(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "crashes"],
      opts: opts
    )
  end

  @doc """
  List crash dumps. Raises on error.

  See `all_crash_dumps/1`.
  """
  @spec all_crash_dumps!(Arangox.conn(), keyword) :: term
  def all_crash_dumps!(conn, opts \\ []) do
    case all_crash_dumps(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the endpoints of a single server (deprecated)

  > **WARNING:**
  This route should no longer be used.
  It is considered as deprecated from version 3.4.0 on.


  Returns an array of all configured endpoints the server is listening on.

  The result is a JSON array of JSON objects, each with `"entrypoint"` as
  the only attribute, and with the value being a string describing the
  endpoint.

  > **INFO:**
  Retrieving the array of all endpoints is allowed in the system database
  only. Calling this action in any other database will make the server return
  an error.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      [%{
        "endpoint" => string
      }]
  """
  @spec all_endpoints(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_endpoints(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_db", "_system", "_api", "endpoint"],
      opts: opts
    )
  end

  @doc """
  List the endpoints of a single server (deprecated). Raises on error.

  See `all_endpoints/1`.
  """
  @spec all_endpoints!(Arangox.conn(), keyword) :: term
  def all_endpoints!(conn, opts \\ []) do
    case all_endpoints(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the available startup options

  Return the startup options available to configure the queried _arangod_
  instance, similar to the `--dump-options` startup option.

  The endpoint can only be accessed via the `_system` database. In addition, the
  [`--server.options-api` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--serveroptions-api)
  controls the required privileges to access the option endpoints and allows
  you to disable them entirely. The option can have the following values:
  - `disabled`: This endpoint is disabled.
  - `jwt`: This endpoint can only be accessed using a superuser JWT (default).
  - `admin`: This endpoint can only be accessed by users with
  write access to the `_system` database.
  - `public`: Every user with read access to the `_system` database can
  access this endpoint.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{...}  # 475 keys, among them "activities.only-superuser-enabled", "activities.registry-cleanup-timeout", "agency.activate", "agency.compaction-keep-size", "agency.compaction-step-size", "agency.disaster-recovery-id", "agency.election-timeout-max", "agency.election-timeout-min"
  """
  @spec available_startup_options(Arangox.conn(), keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def available_startup_options(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_db", "_system", "_admin", "options-description"],
      opts: opts
    )
  end

  @doc """
  Get the available startup options. Raises on error.

  See `available_startup_options/1`.
  """
  @spec available_startup_options!(Arangox.conn(), keyword) :: term
  def available_startup_options!(conn, opts \\ []) do
    case available_startup_options(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Compact all databases

  > **WARNING:**
  This command can cause a full rewrite of all data in all databases, which may
  take very long for large databases. It should thus only be used with care and
  only when additional I/O load can be tolerated for a prolonged time.


  This endpoint can be used to reclaim disk space after substantial data
  deletions have taken place, by compacting the entire database system data.

  The endpoint requires superuser access.
  """
  @spec compact_all_databases(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def compact_all_databases(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "compact"],
      database_scope: :server,
      body: body,
      opts: opts
    )
  end

  @doc """
  Compact all databases. Raises on error.

  See `compact_all_databases/2`.
  """
  @spec compact_all_databases!(Arangox.conn(), term, keyword) :: term
  def compact_all_databases!(conn, body, opts \\ []) do
    case compact_all_databases(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a crash dump

  <small>Introduced in: v3.12.8</small>

  Return the contents of a specific crash dump. The response includes all
  files from the crash directory (e.g. `backtrace.txt`, `system_info.txt`,
  `ApiRecording.json`, `AsyncRegistry.json`) as an object mapping filenames
  to their contents. Crash dumps are stored under
  `<database-directory>/crashes/<uuid>/`.

  This endpoint requires *administrate* access to the `_system` database.
  """
  @spec crash_dump(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def crash_dump(conn, crash_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "crashes", crash_id],
      opts: opts
    )
  end

  @doc """
  Get a crash dump. Raises on error.

  See `crash_dump/2`.
  """
  @spec crash_dump!(Arangox.conn(), binary, keyword) :: term
  def crash_dump!(conn, crash_id, opts \\ []) do
    case crash_dump(conn, crash_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the required database version (deprecated)

  > **WARNING:**
  This endpoint is deprecated and should no longer be used.
  It is removed in ArangoDB v4.0. Use `GET /_api/version` instead.


  Returns the database version that this server requires.
  The version is returned in the `version` attribute of the result.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "version" => string
      }
  """
  @spec database_version(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def database_version(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "database", "target-version"],
      database_scope: :server,
      opts: opts
    )
  end

  @doc """
  Get the required database version (deprecated). Raises on error.

  See `database_version/1`.
  """
  @spec database_version!(Arangox.conn(), keyword) :: term
  def database_version!(conn, opts \\ []) do
    case database_version(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete a crash dump

  <small>Introduced in: v3.12.8</small>

  Delete a specific crash dump directory and its contents. Crash dumps are
  stored under `<database-directory>/crashes/<uuid>/`. The server keeps the
  most recent 10 crash dumps. Older ones are removed during startup.

  This endpoint requires *administrate* access to the `_system` database.
  """
  @spec delete_crash_dump(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_crash_dump(conn, crash_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_admin", "crashes", crash_id],
      opts: opts
    )
  end

  @doc """
  Delete a crash dump. Raises on error.

  See `delete_crash_dump/2`.
  """
  @spec delete_crash_dump!(Arangox.conn(), binary, keyword) :: term
  def delete_crash_dump!(conn, crash_id, opts \\ []) do
    case delete_crash_dump(conn, crash_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the deployment ID

  Get the unique identifier of this ArangoDB deployment.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "id" => string
      }
  """
  @spec deployment_id(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def deployment_id(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "deployment", "id"],
      opts: opts
    )
  end

  @doc """
  Get the deployment ID. Raises on error.

  See `deployment_id/1`.
  """
  @spec deployment_id!(Arangox.conn(), keyword) :: term
  def deployment_id!(conn, opts \\ []) do
    case deployment_id(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Echo a request

  > **WARNING:**
  The Action feature, including this debug endpoint, is deprecated and
  removed in ArangoDB v4.0.


  The call returns an object with the servers request information
  """
  @spec echo_request(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def echo_request(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "echo"],
      body: body,
      media: "application/octet-stream",
      opts: opts
    )
  end

  @doc """
  Echo a request. Raises on error.

  See `echo_request/2`.
  """
  @spec echo_request!(Arangox.conn(), binary, keyword) :: term
  def echo_request!(conn, body, opts \\ []) do
    case echo_request(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the startup option configuration

  Return the effective configuration of the queried _arangod_ instance as
  set by startup options on the command-line and via a configuration file.

  {{< security >}}
  This endpoint may reveal sensitive information about the deployment!
  {{< /security >}}

  The endpoint can only be accessed via the `_system` database. In addition, the
  [`--server.options-api` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--serveroptions-api)
  controls the required privileges to access the option endpoints and allows
  you to disable them entirely. The option can have the following values:
  - `disabled`: This endpoint is disabled.
  - `jwt`: This endpoint can only be accessed using a superuser JWT (default).
  - `admin`: This endpoint can only be accessed by users with
  write access to the `_system` database.
  - `public`: Every user with read access to the `_system` database can
  access this endpoint.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{...}  # 471 keys, among them "activities.only-superuser-enabled", "activities.registry-cleanup-timeout", "agency.activate", "agency.compaction-keep-size", "agency.compaction-step-size", "agency.disaster-recovery-id", "agency.election-timeout-max", "agency.election-timeout-min"
  """
  @spec effective_startup_options(Arangox.conn(), keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def effective_startup_options(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_db", "_system", "_admin", "options"],
      opts: opts
    )
  end

  @doc """
  Get the startup option configuration. Raises on error.

  See `effective_startup_options/1`.
  """
  @spec effective_startup_options!(Arangox.conn(), keyword) :: term
  def effective_startup_options!(conn, opts \\ []) do
    case effective_startup_options(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the storage engine type

  Returns the storage engine the server is configured to use.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "endianness" => string,
        "name" => string,
        "supports" => %{
          "aliases" => %{
            "indexes" => %{
              "hash" => string,
              "skiplist" => string,
              "zkd" => string
            }
          },
          "indexes" => [string]
        }
      }
  """
  @spec engine(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def engine(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "engine"],
      opts: opts
    )
  end

  @doc """
  Get the storage engine type. Raises on error.

  See `engine/1`.
  """
  @spec engine!(Arangox.conn(), keyword) :: term
  def engine!(conn, opts \\ []) do
    case engine(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the storage engine statistics

  Returns detailed statistics related to the RocksDB storage engine activity,
  including figures about data size, cache usage, individual column families, etc.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{...}  # 69 keys, among them "cache.active-tables", "cache.allocated", "cache.edge-compression-ratio", "cache.free-memory-tasks-duration-total", "cache.free-memory-tasks-total", "cache.hit-rate-lifetime", "cache.hit-rate-recent", "cache.limit"
  """
  @spec engine_stats(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def engine_stats(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "engine", "stats"],
      opts: opts
    )
  end

  @doc """
  Get the storage engine statistics. Raises on error.

  See `engine_stats/1`.
  """
  @spec engine_stats!(Arangox.conn(), keyword) :: term
  def engine_stats!(conn, opts \\ []) do
    case engine_stats(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Execute a script

  > **WARNING:**
  The `/_admin/execute` endpoint is deprecated and removed in ArangoDB v4.0.


  Executes the JavaScript code in the body on the server as the body
  of a function with no arguments. If you have a `return` statement
  then the return value you produce will be returned as content type
  `application/json`. If the parameter `returnAsJSON` is set to
  `true`, the result will be a JSON object describing the return value
  directly, otherwise a string produced by JSON.stringify will be
  returned.

  Note that this API endpoint is available if the server has been
  started with the `--javascript.allow-admin-execute` startup options
  enabled.

  The default value of this option is `false`, which disables the execution of
  user-defined code and disables this API endpoint entirely.
  This is also the recommended setting for production.
  """
  @spec execute_code(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def execute_code(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "execute"],
      body: body,
      media: "text/javascript",
      opts: opts
    )
  end

  @doc """
  Execute a script. Raises on error.

  See `execute_code/2`.
  """
  @spec execute_code!(Arangox.conn(), binary, keyword) :: term
  def execute_code!(conn, body, opts \\ []) do
    case execute_code(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get information about the current license

  View the license information and status of the ArangoDB deployment.

  Can be called on single servers, Coordinators, and DB-Servers.

  In the Community Edition before v3.12.5, only `{"license":"none"}`
  is returned.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "diskUsage" => %{
          "bytesLimit" => integer,
          "bytesUsed" => integer,
          "limitReached" => boolean,
          "secondsUntilReadOnly" => integer,
          "secondsUntilShutDown" => integer,
          "status" => string
        },
        "upgrading" => boolean
      }
  """
  @spec license(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def license(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "license"],
      opts: opts
    )
  end

  @doc """
  Get information about the current license. Raises on error.

  See `license/1`.
  """
  @spec license!(Arangox.conn(), keyword) :: term
  def license!(conn, opts \\ []) do
    case license(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the public startup option configuration

  Return a small, curated subset of the configured server startup options
  that are safe to expose to any authenticated user with read access to the
  requested database.

  Administrative tools can use this endpoint to adapt their behavior to the server
  configuration. For example, they can show the valid range for `replicationFactor`
  when creating a collection, or respect `--database.extended-names` when
  validating names on the client-side.

  This endpoint is available regardless of the
  [`--server.options-api` startup option](https://docs.arango.ai/arangodb/3.12/components/arangodb-server/options/#--serveroptions-api)
  setting, so that the Arango Contextual Data Platform web interface for
  instance can always access the public options.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cluster.api-jwt-policy" => string,
        "cluster.max-number-of-shards" => integer,
        "cluster.max-replication-factor" => integer,
        "cluster.min-replication-factor" => integer,
        "database.extended-names" => boolean,
        "server.session-timeout" => integer
      }
  """
  @spec public_startup_options(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def public_startup_options(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "options-public"],
      opts: opts
    )
  end

  @doc """
  Get the public startup option configuration. Raises on error.

  See `public_startup_options/1`.
  """
  @spec public_startup_options!(Arangox.conn(), keyword) :: term
  def public_startup_options!(conn, opts \\ []) do
    case public_startup_options(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Reload the routing table

  > **WARNING:**
  The Action and Foxx microservice features, including this endpoint for
  route reloading, are deprecated and removed in ArangoDB v4.0.


  Reloads the routing information from the `_routing` system collection if it
  exists, and makes Foxx rebuild its local routing table on the next request.
  """
  @spec reload_routing(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def reload_routing(conn, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "routing", "reload"],
      opts: opts
    )
  end

  @doc """
  Reload the routing table. Raises on error.

  See `reload_routing/1`.
  """
  @spec reload_routing!(Arangox.conn(), keyword) :: term
  def reload_routing!(conn, opts \\ []) do
    case reload_routing(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Return whether or not a server is available

  Return availability information about a server.

  The response is a JSON object with an attribute "mode". The "mode" can either
  be "readonly", if the server is in read-only mode, or "default", if it is not.
  Please note that the JSON object with "mode" is only returned in case the server
  does not respond with HTTP response code 503.

  This is a public API so it does *not* require authentication. It is meant to be
  used only in the context of server monitoring.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "mode" => string
      }
  """
  @spec server_availability(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_availability(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "availability"],
      database_scope: :server,
      opts: opts
    )
  end

  @doc """
  Return whether or not a server is available. Raises on error.

  See `server_availability/1`.
  """
  @spec server_availability!(Arangox.conn(), keyword) :: term
  def server_availability!(conn, opts \\ []) do
    case server_availability(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Return whether or not a server is in read-only mode

  Return mode information about a server. The json response will contain
  a field `mode` with the value `readonly` or `default`. In a read-only server
  all write operations will fail with an error code of `1004` (_ERROR_READ_ONLY_).
  Creating or dropping of databases and collections will also fail with error code `11` (_ERROR_FORBIDDEN_).

  This API requires authentication.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "mode" => string
      }
  """
  @spec server_mode(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_mode(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "mode"],
      opts: opts
    )
  end

  @doc """
  Return whether or not a server is in read-only mode. Raises on error.

  See `server_mode/1`.
  """
  @spec server_mode!(Arangox.conn(), keyword) :: term
  def server_mode!(conn, opts \\ []) do
    case server_mode(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set a new license

  Set a new license for an Enterprise Edition instance.
  Can be called on single servers, Coordinators, and DB-Servers.
  """
  @spec set_license(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def set_license(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "license"],
      body: body,
      query: [force: "force"],
      opts: opts
    )
  end

  @doc """
  Set a new license. Raises on error.

  See `set_license/2`.
  """
  @spec set_license!(Arangox.conn(), term, keyword) :: term
  def set_license!(conn, body, opts \\ []) do
    case set_license(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set the server mode to read-only or default

  Update mode information about a server. The JSON response will contain
  a field `mode` with the value `readonly` or `default`. In a read-only server
  all write operations will fail with an error code of `1004` (_ERROR_READ_ONLY_).
  Creating or dropping of databases and collections will also fail with error
  code `11` (_ERROR_FORBIDDEN_).

  This is a protected API. It requires authentication and administrative
  server rights.
  """
  @spec set_server_mode(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def set_server_mode(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "server", "mode"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set the server mode to read-only or default. Raises on error.

  See `set_server_mode/2`.
  """
  @spec set_server_mode!(Arangox.conn(), term, keyword) :: term
  def set_server_mode!(conn, body, opts \\ []) do
    case set_server_mode(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Query the soft shutdown progress

  <small>Introduced in: v3.7.12, v3.8.1, v3.9.0</small>

  This call reports progress about a soft Coordinator shutdown (see
  documentation of `DELETE /_admin/shutdown?soft=true`).
  In this case, the following types of operations are tracked:

  - AQL cursors (in particular streaming cursors)
  - Transactions (in particular stream transactions)
  - Ongoing asynchronous requests (using the `x-arango-async: store` HTTP header)
  - Finished asynchronous requests, whose result has not yet been
   collected
  - Queued low priority requests (most normal requests)
  - Ongoing low priority requests

  This API is only available on Coordinators.
  """
  @spec shutdown_progress(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def shutdown_progress(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "shutdown"],
      opts: opts
    )
  end

  @doc """
  Query the soft shutdown progress. Raises on error.

  See `shutdown_progress/1`.
  """
  @spec shutdown_progress!(Arangox.conn(), keyword) :: term
  def shutdown_progress!(conn, opts \\ []) do
    case shutdown_progress(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Start the shutdown sequence

  This call initiates a clean shutdown sequence. Requires administrative privileges.
  """
  @spec start_shutdown(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def start_shutdown(conn, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_admin", "shutdown"],
      query: [soft: "soft"],
      opts: opts
    )
  end

  @doc """
  Start the shutdown sequence. Raises on error.

  See `start_shutdown/1`.
  """
  @spec start_shutdown!(Arangox.conn(), keyword) :: term
  def start_shutdown!(conn, opts \\ []) do
    case start_shutdown(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get server status information

  Returns status information about the server.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "foxxApi" => boolean,
        "host" => string,
        "hostname" => string,
        "license" => string,
        "mode" => string,
        "operationMode" => string,
        "pid" => integer,
        "server" => string,
        "serverInfo" => %{
          "maintenance" => boolean,
          "progress" => %{
            "feature" => string,
            "phase" => string,
            "recoveryTick" => integer
          },
          "readOnly" => boolean,
          "role" => string,
          "writeOpsEnabled" => boolean
        },
        "version" => string
      }
  """
  @spec status(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def status(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "status"],
      opts: opts
    )
  end

  @doc """
  Get server status information. Raises on error.

  See `status/1`.
  """
  @spec status!(Arangox.conn(), keyword) :: term
  def status!(conn, opts \\ []) do
    case status(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get information about the deployment

  Retrieves deployment information for support purposes. The endpoint returns data
  about the ArangoDB version used, the host (operating system, server ID, CPU and
  storage capacity, current utilization, a few metrics) and the other servers in
  the deployment (in case of cluster deployments).

  As this API may reveal sensitive data about the deployment, it can only be
  accessed from inside the `_system` database. In addition, there is a policy
  control startup option `--server.support-info-api` that controls if and to whom
  the API is made available.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "date" => string,
        "deployment" => %{
          "type" => string
        },
        "host" => %{
          "build" => string,
          "cpuStats" => %{
            "idlePercent" => float,
            "iowaitPercent" => float,
            "systemPercent" => float,
            "userPercent" => float
          },
          "engineStats" => %{
            "cache.allocated" => integer,
            "cache.limit" => integer,
            "rocksdb.block-cache-capacity" => integer,
            "rocksdb.block-cache-usage" => integer,
            "rocksdb.estimate-live-data-size" => integer,
            "rocksdb.estimate-num-keys" => integer,
            "rocksdb.free-disk-space" => integer,
            "rocksdb.live-sst-files-size" => integer,
            "rocksdb.total-disk-space" => integer
          },
          "license" => string,
          "maintenance" => boolean,
          "numberOfCores" => %{
            "overridden" => boolean,
            "value" => integer
          },
          "os" => string,
          "physicalMemory" => %{
            "overridden" => boolean,
            "value" => integer
          },
          "platform" => string,
          "processStats" => %{
            "fileDescrtors" => integer,
            "fileDescrtorsLimit" => integer,
            "numberOfThreads" => integer,
            "processUptime" => float,
            "residentSetSize" => integer,
            "virtualSize" => integer
          },
          "readOnly" => boolean,
          "role" => string,
          "version" => string
        }
      }
  """
  @spec support_info(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def support_info(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_db", "_system", "_admin", "support-info"],
      opts: opts
    )
  end

  @doc """
  Get information about the deployment. Raises on error.

  See `support_info/1`.
  """
  @spec support_info!(Arangox.conn(), keyword) :: term
  def support_info!(conn, opts \\ []) do
    case support_info(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the system time

  The call returns an object with the `time` attribute. This contains the
  current system time as a Unix timestamp with microsecond precision.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "time" => float
      }
  """
  @spec time(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def time(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "time"],
      opts: opts
    )
  end

  @doc """
  Get the system time. Raises on error.

  See `time/1`.
  """
  @spec time!(Arangox.conn(), keyword) :: term
  def time!(conn, opts \\ []) do
    case time(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the server version

  Returns the server name and version number.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "apiVersions" => [string],
        "deprecatedApiVersions" => [],
        "license" => string,
        "requestedApiVersion" => string,
        "server" => string,
        "version" => string
      }
  """
  @spec version(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def version(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "version"],
      query: [details: "details"],
      opts: opts
    )
  end

  @doc """
  Get the server version. Raises on error.

  See `version/1`.
  """
  @spec version!(Arangox.conn(), keyword) :: term
  def version!(conn, opts \\ []) do
    case version(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
