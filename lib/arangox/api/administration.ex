defmodule Arangox.Api.Administration do
  @moduledoc """
  Provides API endpoints related to administration
  """

  @default_client Arangox.Api.Client

  @doc """
  Compact all databases

  > **WARNING:**
  This command can cause a full rewrite of all data in all databases, which may
  take very long for large databases. It should thus only be used with care and
  only when additional I/O load can be tolerated for a prolonged time.

  This endpoint can be used to reclaim disk space after substantial data
  deletions have taken place, by compacting the entire database system data.

  The endpoint requires superuser access.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec compact_all_databases(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def compact_all_databases(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Administration, :compact_all_databases},
      url: "/_admin/compact",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {401, :null}],
      opts: opts
    })
  end

  @type delete_crash_dump_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Administration.delete_crash_dump_200_json_resp_result()
        }

  @type delete_crash_dump_200_json_resp_result :: %{crashId: String.t(), deleted: boolean}

  @type delete_crash_dump_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_crash_dump_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_crash_dump_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_crash_dump_503_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Delete a crash dump

  <small>Introduced in: v3.12.8</small>

  Delete a specific crash dump directory and its contents. Crash dumps are
  stored under `<database-directory>/crashes/<uuid>/`. The server keeps the
  most recent 10 crash dumps. Older ones are removed during startup.

  This endpoint requires *administrate* access to the `_system` database.

  """
  @spec delete_crash_dump(database_name :: String.t(), crashId :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_crash_dump(database_name, crashId, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, crashId: crashId],
      call: {Arangox.Api.Administration, :delete_crash_dump},
      url: "/_db/#{database_name}/_admin/crashes/#{crashId}",
      method: :delete,
      response: [
        {200, {Arangox.Api.Administration, :delete_crash_dump_200_json_resp}},
        {401, {Arangox.Api.Administration, :delete_crash_dump_401_json_resp}},
        {403, {Arangox.Api.Administration, :delete_crash_dump_403_json_resp}},
        {404, {Arangox.Api.Administration, :delete_crash_dump_404_json_resp}},
        {503, {Arangox.Api.Administration, :delete_crash_dump_503_json_resp}}
      ],
      opts: opts
    })
  end

  @type echo_request_200_json_resp :: %{
          authorized: boolean,
          client: Arangox.Api.Administration.echo_request_200_json_resp_client(),
          cookies: map,
          database: String.t(),
          headers: map,
          internals: map,
          isAdminUser: boolean,
          parameters: map,
          path: String.t(),
          portType: String.t(),
          prefix: map,
          protocol: String.t(),
          rawRequestBody: map,
          rawSuffix: [String.t()],
          requestBody: String.t(),
          requestType: String.t(),
          server: Arangox.Api.Administration.echo_request_200_json_resp_server(),
          suffix: [String.t()],
          url: String.t(),
          user: String.t()
        }

  @type echo_request_200_json_resp_client :: %{address: integer, id: String.t(), port: integer}

  @type echo_request_200_json_resp_server :: %{
          address: String.t(),
          endpoint: String.t(),
          port: integer
        }

  @doc """
  Echo a request

  > **WARNING:**
  The Action feature, including this debug endpoint, is deprecated and
  removed in ArangoDB v4.0.

  The call returns an object with the servers request information

  ## Request Body

  **Content Types**: `application/octet-stream`
  """
  @spec echo_request(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def echo_request(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Administration, :echo_request},
      url: "/_db/#{database_name}/_admin/echo",
      body: body,
      method: :post,
      request: [{"application/octet-stream", :map}],
      response: [{200, {Arangox.Api.Administration, :echo_request_200_json_resp}}],
      opts: opts
    })
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

  ## Request Body

  **Content Types**: `text/javascript`
  """
  @spec execute_code(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def execute_code(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Administration, :execute_code},
      url: "/_db/#{database_name}/_admin/execute",
      body: body,
      method: :post,
      request: [{"text/javascript", :map}],
      response: [{200, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end

  @type get_available_startup_options_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_available_startup_options_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_available_startup_options_405_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  """
  @spec get_available_startup_options(keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_available_startup_options(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :get_available_startup_options},
      url: "/_db/_system/_admin/options-description",
      method: :get,
      response: [
        {200, :map},
        {401, {Arangox.Api.Administration, :get_available_startup_options_401_json_resp}},
        {403, {Arangox.Api.Administration, :get_available_startup_options_403_json_resp}},
        {405, {Arangox.Api.Administration, :get_available_startup_options_405_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_crash_dump_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Administration.get_crash_dump_200_json_resp_result()
        }

  @type get_crash_dump_200_json_resp_result :: %{crashId: String.t(), files: map}

  @type get_crash_dump_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_crash_dump_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_crash_dump_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_crash_dump_503_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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
  @spec get_crash_dump(database_name :: String.t(), crashId :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_crash_dump(database_name, crashId, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, crashId: crashId],
      call: {Arangox.Api.Administration, :get_crash_dump},
      url: "/_db/#{database_name}/_admin/crashes/#{crashId}",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :get_crash_dump_200_json_resp}},
        {401, {Arangox.Api.Administration, :get_crash_dump_401_json_resp}},
        {403, {Arangox.Api.Administration, :get_crash_dump_403_json_resp}},
        {404, {Arangox.Api.Administration, :get_crash_dump_404_json_resp}},
        {503, {Arangox.Api.Administration, :get_crash_dump_503_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Get the required database version (deprecated)

  > **WARNING:**
  This endpoint is deprecated and should no longer be used.
  It is removed in ArangoDB v4.0. Use `GET /_api/version` instead.

  Returns the database version that this server requires.
  The version is returned in the `version` attribute of the result.

  """
  @spec get_database_version(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_database_version(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :get_database_version},
      url: "/_admin/database/target-version",
      method: :get,
      response: [{200, :null}],
      opts: opts
    })
  end

  @type get_deployment_id_200_json_resp :: %{id: String.t()}

  @type get_deployment_id_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the deployment ID

  Get the unique identifier of this ArangoDB deployment.

  """
  @spec get_deployment_id(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_deployment_id(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_deployment_id},
      url: "/_db/#{database_name}/_admin/deployment/id",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :get_deployment_id_200_json_resp}},
        {401, {Arangox.Api.Administration, :get_deployment_id_401_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_effective_startup_options_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_effective_startup_options_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_effective_startup_options_405_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  """
  @spec get_effective_startup_options(keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_effective_startup_options(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :get_effective_startup_options},
      url: "/_db/_system/_admin/options",
      method: :get,
      response: [
        {200, :map},
        {401, {Arangox.Api.Administration, :get_effective_startup_options_401_json_resp}},
        {403, {Arangox.Api.Administration, :get_effective_startup_options_403_json_resp}},
        {405, {Arangox.Api.Administration, :get_effective_startup_options_405_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_engine_200_json_resp :: %{name: String.t()}

  @type get_engine_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the storage engine type

  Returns the storage engine the server is configured to use.

  """
  @spec get_engine(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_engine(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_engine},
      url: "/_db/#{database_name}/_api/engine",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :get_engine_200_json_resp}},
        {401, {Arangox.Api.Administration, :get_engine_401_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_engine_stats_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_engine_stats_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the storage engine statistics

  Returns detailed statistics related to the RocksDB storage engine activity,
  including figures about data size, cache usage, individual column families, etc.

  """
  @spec get_engine_stats(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_engine_stats(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_engine_stats},
      url: "/_db/#{database_name}/_api/engine/stats",
      method: :get,
      response: [
        {200, :map},
        {401, {Arangox.Api.Administration, :get_engine_stats_401_json_resp}},
        {403, {Arangox.Api.Administration, :get_engine_stats_403_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_license_200_json_resp :: %{
          diskUsage: Arangox.Api.Administration.get_license_200_json_resp_disk_usage() | nil,
          features: Arangox.Api.Administration.get_license_200_json_resp_features() | nil,
          hash: String.t() | nil,
          license: String.t() | nil,
          status: String.t() | nil,
          upgrading: boolean | nil,
          version: number | nil
        }

  @type get_license_200_json_resp_disk_usage :: %{
          bytesLimit: integer,
          bytesUsed: integer,
          limitReached: boolean,
          secondsUntilReadOnly: integer,
          secondsUntilShutDown: integer,
          status: String.t()
        }

  @type get_license_200_json_resp_features :: %{expires: number}

  @doc """
  Get information about the current license

  View the license information and status of the ArangoDB deployment.

  Can be called on single servers, Coordinators, and DB-Servers.

  In the Community Edition before v3.12.5, only `{"license":"none"}`
  is returned.

  """
  @spec get_license(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_license(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_license},
      url: "/_db/#{database_name}/_admin/license",
      method: :get,
      response: [{200, {Arangox.Api.Administration, :get_license_200_json_resp}}],
      opts: opts
    })
  end

  @type get_public_startup_options_200_json_resp :: %{
          "cluster.api-jwt-policy": String.t() | nil,
          "cluster.max-number-of-shards": integer | nil,
          "cluster.max-replication-factor": integer | nil,
          "cluster.min-replication-factor": integer | nil,
          "database.extended-names": boolean | nil,
          "server.session-timeout": number | nil
        }

  @type get_public_startup_options_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_public_startup_options_405_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  """
  @spec get_public_startup_options(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_public_startup_options(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_public_startup_options},
      url: "/_db/#{database_name}/_admin/options-public",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :get_public_startup_options_200_json_resp}},
        {401, {Arangox.Api.Administration, :get_public_startup_options_401_json_resp}},
        {405, {Arangox.Api.Administration, :get_public_startup_options_405_json_resp}}
      ],
      opts: opts
    })
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

  """
  @spec get_server_availability(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_availability(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :get_server_availability},
      url: "/_admin/server/availability",
      method: :get,
      response: [{200, :null}, {503, :null}],
      opts: opts
    })
  end

  @doc """
  Return whether or not a server is in read-only mode

  Return mode information about a server. The json response will contain
  a field `mode` with the value `readonly` or `default`. In a read-only server
  all write operations will fail with an error code of `1004` (_ERROR_READ_ONLY_).
  Creating or dropping of databases and collections will also fail with error code `11` (_ERROR_FORBIDDEN_).

  This API requires authentication.

  """
  @spec get_server_mode(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_mode(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_server_mode},
      url: "/_db/#{database_name}/_admin/server/mode",
      method: :get,
      response: [{200, :null}],
      opts: opts
    })
  end

  @type get_shutdown_progress_200_json_resp :: %{
          AQLcursors: number,
          allClear: boolean,
          doneJobs: number,
          lowPrioOngoingRequests: number,
          lowPrioQueuedRequests: number,
          pendingJobs: number,
          softShutdownOngoing: boolean,
          transactions: number
        }

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
  @spec get_shutdown_progress(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_shutdown_progress(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_shutdown_progress},
      url: "/_db/#{database_name}/_admin/shutdown",
      method: :get,
      response: [{200, {Arangox.Api.Administration, :get_shutdown_progress_200_json_resp}}],
      opts: opts
    })
  end

  @type get_status_200_json_resp :: %{
          agency: Arangox.Api.Administration.get_status_200_json_resp_agency() | nil,
          agent: Arangox.Api.Administration.get_status_200_json_resp_agent() | nil,
          coordinator: Arangox.Api.Administration.get_status_200_json_resp_coordinator() | nil,
          foxxApi: boolean,
          host: String.t(),
          hostname: String.t() | nil,
          license: String.t(),
          mode: String.t(),
          operationMode: String.t(),
          pid: number,
          server: String.t(),
          serverInfo: Arangox.Api.Administration.get_status_200_json_resp_server_info(),
          version: String.t()
        }

  @type get_status_200_json_resp_agency :: %{
          agencyComm:
            Arangox.Api.Administration.get_status_200_json_resp_agency_agency_comm() | nil
        }

  @type get_status_200_json_resp_agency_agency_comm :: %{endpoints: [String.t()] | nil}

  @type get_status_200_json_resp_agent :: %{
          endpoint: String.t() | nil,
          id: String.t() | nil,
          leaderId: String.t() | nil,
          leading: boolean | nil,
          term: number | nil
        }

  @type get_status_200_json_resp_coordinator :: %{
          foxxmaster: [String.t()] | nil,
          isFoxxmaster: [String.t()] | nil
        }

  @type get_status_200_json_resp_server_info :: %{
          address: String.t() | nil,
          maintenance: boolean,
          persistedId: String.t() | nil,
          progress: Arangox.Api.Administration.get_status_200_json_resp_server_info_progress(),
          readOnly: boolean,
          rebootId: number | nil,
          role: String.t(),
          serverId: String.t() | nil,
          state: String.t() | nil,
          writeOpsEnabled: boolean
        }

  @type get_status_200_json_resp_server_info_progress :: %{
          feature: String.t(),
          phase: String.t(),
          recoveryTick: number
        }

  @doc """
  Get server status information

  Returns status information about the server.

  """
  @spec get_status(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_status(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_status},
      url: "/_db/#{database_name}/_admin/status",
      method: :get,
      response: [{200, {Arangox.Api.Administration, :get_status_200_json_resp}}],
      opts: opts
    })
  end

  @type get_support_info_200_json_resp :: %{date: String.t(), deployment: map, host: map | nil}

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

  """
  @spec get_support_info(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_support_info(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :get_support_info},
      url: "/_db/_system/_admin/support-info",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :get_support_info_200_json_resp}},
        {404, :null}
      ],
      opts: opts
    })
  end

  @type get_time_200_json_resp :: %{code: integer, error: boolean, time: number}

  @doc """
  Get the system time

  The call returns an object with the `time` attribute. This contains the
  current system time as a Unix timestamp with microsecond precision.

  """
  @spec get_time(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_time(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_time},
      url: "/_db/#{database_name}/_admin/time",
      method: :get,
      response: [{200, {Arangox.Api.Administration, :get_time_200_json_resp}}],
      opts: opts
    })
  end

  @type get_version_200_json_resp :: %{
          apiVersions: [String.t()],
          deprecatedApiVersions: [nil],
          details: Arangox.Api.Administration.get_version_200_json_resp_details() | nil,
          license: String.t(),
          requestedApiVersion: String.t(),
          server: String.t(),
          version: String.t()
        }

  @type get_version_200_json_resp_details :: %{
          architecture: String.t() | nil,
          arm: String.t() | nil,
          asan: String.t() | nil,
          assertions: String.t() | nil,
          avx: String.t() | nil,
          avx2: String.t() | nil,
          "boost-version": String.t() | nil,
          "build-date": String.t() | nil,
          "build-id": String.t() | nil,
          "build-repository": String.t() | nil,
          compiler: String.t() | nil,
          coverage: String.t() | nil,
          cplusplus: String.t() | nil,
          "curl-version": String.t() | nil,
          debug: String.t() | nil,
          endianness: String.t() | nil,
          "enterprise-build-repository": String.t() | nil,
          "enterprise-version": String.t() | nil,
          "failure-tests": String.t() | nil,
          faiss: String.t() | nil,
          "fd-client-event-handler": String.t() | nil,
          "fd-setsize": String.t() | nil,
          "full-version-string": String.t() | nil,
          host: String.t() | nil,
          "icu-version": String.t() | nil,
          ipo: String.t() | nil,
          "iresearch-version": String.t() | nil,
          jemalloc: String.t() | nil,
          libunwind: String.t() | nil,
          license: String.t() | nil,
          "maintainer-mode": String.t() | nil,
          "memory-profiler": String.t() | nil,
          mode: String.t() | nil,
          ndebug: String.t() | nil,
          openmp: String.t() | nil,
          "openssl-version": String.t() | nil,
          "openssl-version-compile-time": String.t() | nil,
          "openssl-version-run-time": String.t() | nil,
          "optimization-flags": String.t() | nil,
          pic: String.t() | nil,
          pie: String.t() | nil,
          platform: String.t() | nil,
          "reactor-type": String.t() | nil,
          "replication2-enabled": String.t() | nil,
          "rocksdb-version": String.t() | nil,
          role: String.t() | nil,
          "server-version": String.t() | nil,
          "sizeof int": String.t() | nil,
          "sizeof long": String.t() | nil,
          "sizeof void*": String.t() | nil,
          sse42: String.t() | nil,
          tsan: String.t() | nil,
          "unaligned-access": String.t() | nil,
          "v8-version": String.t() | nil,
          "vpack-version": String.t() | nil,
          "zlib-version": String.t() | nil
        }

  @doc """
  Get the server version

  Returns the server name and version number.

  ## Options

    * `details`: If set to `true` and if the user account you authenticate with has
      administrate access to the `_system` database, the response contains
      a `details` attribute with additional information about included
      components and their versions. The attribute names and internals of
      the `details` object may vary depending on platform and ArangoDB version.
      

  """
  @spec get_version(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_version(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:details])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :get_version},
      url: "/_db/#{database_name}/_api/version",
      method: :get,
      query: query,
      response: [{200, {Arangox.Api.Administration, :get_version_200_json_resp}}],
      opts: opts
    })
  end

  @type list_crash_dumps_200_json_resp :: %{code: integer, error: boolean, result: [String.t()]}

  @type list_crash_dumps_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_crash_dumps_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_crash_dumps_503_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  """
  @spec list_crash_dumps(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_crash_dumps(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :list_crash_dumps},
      url: "/_db/#{database_name}/_admin/crashes",
      method: :get,
      response: [
        {200, {Arangox.Api.Administration, :list_crash_dumps_200_json_resp}},
        {401, {Arangox.Api.Administration, :list_crash_dumps_401_json_resp}},
        {403, {Arangox.Api.Administration, :list_crash_dumps_403_json_resp}},
        {503, {Arangox.Api.Administration, :list_crash_dumps_503_json_resp}}
      ],
      opts: opts
    })
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

  """
  @spec list_endpoints(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_endpoints(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Administration, :list_endpoints},
      url: "/_db/_system/_api/endpoint",
      method: :get,
      response: [{200, :null}, {400, :null}, {405, :null}],
      opts: opts
    })
  end

  @doc """
  Reload the routing table

  > **WARNING:**
  The Action and Foxx microservice features, including this endpoint for
  route reloading, are deprecated and removed in ArangoDB v4.0.

  Reloads the routing information from the `_routing` system collection if it
  exists, and makes Foxx rebuild its local routing table on the next request.

  """
  @spec reload_routing(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def reload_routing(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :reload_routing},
      url: "/_db/#{database_name}/_admin/routing/reload",
      method: :post,
      response: [{200, :null}],
      opts: opts
    })
  end

  @type set_license_201_json_resp :: %{
          result: Arangox.Api.Administration.set_license_201_json_resp_result()
        }

  @type set_license_201_json_resp_result :: %{code: integer, error: boolean}

  @type set_license_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type set_license_501_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Set a new license

  Set a new license for an Enterprise Edition instance.
  Can be called on single servers, Coordinators, and DB-Servers.

  ## Options

    * `force`: Whether to change the license even if it expires sooner than the current one.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_license(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_license(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:force])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Administration, :set_license},
      url: "/_db/#{database_name}/_admin/license",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :string}],
      response: [
        {201, {Arangox.Api.Administration, :set_license_201_json_resp}},
        {400, {Arangox.Api.Administration, :set_license_400_json_resp}},
        {501, {Arangox.Api.Administration, :set_license_501_json_resp}}
      ],
      opts: opts
    })
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

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_server_mode(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_server_mode(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Administration, :set_server_mode},
      url: "/_db/#{database_name}/_admin/server/mode",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {401, :null}],
      opts: opts
    })
  end

  @doc """
  Start the shutdown sequence

  This call initiates a clean shutdown sequence. Requires administrative privileges.

  ## Options

    * `soft`: <small>Introduced in: v3.7.12, v3.8.1, v3.9.0</small>
      
      If set to `true`, this initiates a soft shutdown. This is only available
      on Coordinators. When issued, the Coordinator tracks a number of ongoing
      operations, waits until all have finished, and then shuts itself down
      normally. It will still accept new operations.
      
      This feature can be used to make restart operations of Coordinators less
      intrusive for clients. It is designed for setups with a load balancer in front
      of Coordinators. Remove the designated Coordinator from the load balancer before
      issuing the soft-shutdown. The remaining Coordinators will internally forward
      requests that need to be handled by the designated Coordinator. All other
      requests will be handled by the remaining Coordinators, reducing the designated
      Coordinator's load.
      
      The following types of operations are tracked:
      
       - AQL cursors (in particular streaming cursors)
       - Transactions (in particular stream transactions)
       - Ongoing asynchronous requests (using the `x-arango-async: store` HTTP header)
       - Finished asynchronous requests, whose result has not yet been
         collected
       - Queued low priority requests (most normal requests)
       - Ongoing low priority requests
      

  """
  @spec start_shutdown(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def start_shutdown(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:soft])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Administration, :start_shutdown},
      url: "/_db/#{database_name}/_admin/shutdown",
      method: :delete,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:delete_crash_dump_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Administration, :delete_crash_dump_200_json_resp_result}
    ]
  end

  def __fields__(:delete_crash_dump_200_json_resp_result) do
    [crashId: {:string, "uuid"}, deleted: :boolean]
  end

  def __fields__(:delete_crash_dump_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_crash_dump_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_crash_dump_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_crash_dump_503_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:echo_request_200_json_resp) do
    [
      authorized: :boolean,
      client: {Arangox.Api.Administration, :echo_request_200_json_resp_client},
      cookies: :map,
      database: :string,
      headers: :map,
      internals: :map,
      isAdminUser: :boolean,
      parameters: :map,
      path: :string,
      portType: :string,
      prefix: :map,
      protocol: :string,
      rawRequestBody: :map,
      rawSuffix: [:string],
      requestBody: :string,
      requestType: :string,
      server: {Arangox.Api.Administration, :echo_request_200_json_resp_server},
      suffix: [:string],
      url: :string,
      user: :string
    ]
  end

  def __fields__(:echo_request_200_json_resp_client) do
    [address: :integer, id: :string, port: :integer]
  end

  def __fields__(:echo_request_200_json_resp_server) do
    [address: :string, endpoint: :string, port: :integer]
  end

  def __fields__(:get_available_startup_options_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_available_startup_options_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_available_startup_options_405_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_crash_dump_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Administration, :get_crash_dump_200_json_resp_result}
    ]
  end

  def __fields__(:get_crash_dump_200_json_resp_result) do
    [crashId: {:string, "uuid"}, files: :map]
  end

  def __fields__(:get_crash_dump_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_crash_dump_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_crash_dump_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_crash_dump_503_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_deployment_id_200_json_resp) do
    [id: {:string, "uuid"}]
  end

  def __fields__(:get_deployment_id_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_effective_startup_options_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_effective_startup_options_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_effective_startup_options_405_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_engine_200_json_resp) do
    [name: :string]
  end

  def __fields__(:get_engine_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_engine_stats_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_engine_stats_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_license_200_json_resp) do
    [
      diskUsage: {Arangox.Api.Administration, :get_license_200_json_resp_disk_usage},
      features: {Arangox.Api.Administration, :get_license_200_json_resp_features},
      hash: :string,
      license: :string,
      status: {:enum, ["good", "expiring", "read-only"]},
      upgrading: :boolean,
      version: :number
    ]
  end

  def __fields__(:get_license_200_json_resp_disk_usage) do
    [
      bytesLimit: :integer,
      bytesUsed: :integer,
      limitReached: :boolean,
      secondsUntilReadOnly: :integer,
      secondsUntilShutDown: :integer,
      status: {:enum, ["good", "limit-reached", "read-only", "shutdown"]}
    ]
  end

  def __fields__(:get_license_200_json_resp_features) do
    [expires: :number]
  end

  def __fields__(:get_public_startup_options_200_json_resp) do
    [
      "cluster.api-jwt-policy": :string,
      "cluster.max-number-of-shards": :integer,
      "cluster.max-replication-factor": :integer,
      "cluster.min-replication-factor": :integer,
      "database.extended-names": :boolean,
      "server.session-timeout": :number
    ]
  end

  def __fields__(:get_public_startup_options_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_public_startup_options_405_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_shutdown_progress_200_json_resp) do
    [
      AQLcursors: :number,
      allClear: :boolean,
      doneJobs: :number,
      lowPrioOngoingRequests: :number,
      lowPrioQueuedRequests: :number,
      pendingJobs: :number,
      softShutdownOngoing: :boolean,
      transactions: :number
    ]
  end

  def __fields__(:get_status_200_json_resp) do
    [
      agency: {Arangox.Api.Administration, :get_status_200_json_resp_agency},
      agent: {Arangox.Api.Administration, :get_status_200_json_resp_agent},
      coordinator: {Arangox.Api.Administration, :get_status_200_json_resp_coordinator},
      foxxApi: :boolean,
      host: :string,
      hostname: :string,
      license: :string,
      mode: :string,
      operationMode: :string,
      pid: :number,
      server: :string,
      serverInfo: {Arangox.Api.Administration, :get_status_200_json_resp_server_info},
      version: :string
    ]
  end

  def __fields__(:get_status_200_json_resp_agency) do
    [agencyComm: {Arangox.Api.Administration, :get_status_200_json_resp_agency_agency_comm}]
  end

  def __fields__(:get_status_200_json_resp_agency_agency_comm) do
    [endpoints: [:string]]
  end

  def __fields__(:get_status_200_json_resp_agent) do
    [endpoint: :string, id: :string, leaderId: :string, leading: :boolean, term: :number]
  end

  def __fields__(:get_status_200_json_resp_coordinator) do
    [foxxmaster: [:string], isFoxxmaster: [:string]]
  end

  def __fields__(:get_status_200_json_resp_server_info) do
    [
      address: :string,
      maintenance: :boolean,
      persistedId: :string,
      progress: {Arangox.Api.Administration, :get_status_200_json_resp_server_info_progress},
      readOnly: :boolean,
      rebootId: :number,
      role: :string,
      serverId: :string,
      state: :string,
      writeOpsEnabled: :boolean
    ]
  end

  def __fields__(:get_status_200_json_resp_server_info_progress) do
    [feature: :string, phase: :string, recoveryTick: :number]
  end

  def __fields__(:get_support_info_200_json_resp) do
    [date: :string, deployment: :map, host: :map]
  end

  def __fields__(:get_time_200_json_resp) do
    [code: :integer, error: :boolean, time: :number]
  end

  def __fields__(:get_version_200_json_resp) do
    [
      apiVersions: [const: "v0"],
      deprecatedApiVersions: [enum: []],
      details: {Arangox.Api.Administration, :get_version_200_json_resp_details},
      license: {:enum, ["community", "enterprise"]},
      requestedApiVersion: {:const, "v0"},
      server: {:const, "arango"},
      version: :string
    ]
  end

  def __fields__(:get_version_200_json_resp_details) do
    [
      architecture: {:const, "64bit"},
      arm: {:enum, ["true", "false"]},
      asan: {:enum, ["true", "false"]},
      assertions: {:enum, ["true", "false"]},
      avx: {:enum, ["true", "false"]},
      avx2: {:enum, ["true", "false"]},
      "boost-version": :string,
      "build-date": :string,
      "build-id": :string,
      "build-repository": :string,
      compiler: :string,
      coverage: {:enum, ["true", "false"]},
      cplusplus: :string,
      "curl-version": :string,
      debug: {:enum, ["true", "false"]},
      endianness: {:const, "little"},
      "enterprise-build-repository": :string,
      "enterprise-version": {:const, "enterprise"},
      "failure-tests": {:enum, ["true", "false"]},
      faiss: :string,
      "fd-client-event-handler": :string,
      "fd-setsize": :string,
      "full-version-string": :string,
      host: :string,
      "icu-version": :string,
      ipo: {:enum, ["true", "false"]},
      "iresearch-version": :string,
      jemalloc: {:enum, ["true", "false"]},
      libunwind: :string,
      license: {:enum, ["community", "enterprise"]},
      "maintainer-mode": {:enum, ["true", "false"]},
      "memory-profiler": {:enum, ["true", "false"]},
      mode: {:enum, ["server", "console", "script"]},
      ndebug: {:enum, ["true", "false"]},
      openmp: :string,
      "openssl-version": :string,
      "openssl-version-compile-time": :string,
      "openssl-version-run-time": :string,
      "optimization-flags": :string,
      pic: :string,
      pie: :string,
      platform: {:const, "linux"},
      "reactor-type": {:const, "epoll"},
      "replication2-enabled": {:enum, ["true", "false"]},
      "rocksdb-version": :string,
      role: {:enum, ["SINGLE", "PRIMARY", "COORDINATOR", "AGENT"]},
      "server-version": :string,
      "sizeof int": :string,
      "sizeof long": :string,
      "sizeof void*": :string,
      sse42: :string,
      tsan: {:enum, ["true", "false"]},
      "unaligned-access": {:enum, ["true", "false"]},
      "v8-version": :string,
      "vpack-version": :string,
      "zlib-version": :string
    ]
  end

  def __fields__(:list_crash_dumps_200_json_resp) do
    [code: :integer, error: :boolean, result: [string: "uuid"]]
  end

  def __fields__(:list_crash_dumps_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_crash_dumps_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_crash_dumps_503_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:set_license_201_json_resp) do
    [result: {Arangox.Api.Administration, :set_license_201_json_resp_result}]
  end

  def __fields__(:set_license_201_json_resp_result) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:set_license_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:set_license_501_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
