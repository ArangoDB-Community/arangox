defmodule Arangox.Api.Foxx do
  @moduledoc """
  Provides API endpoints related to foxx
  """

  @default_client Arangox.Api.Client

  @doc """
  Commit the local service state

  Commits the local service state of the Coordinator to the database.

  This can be used to resolve service conflicts between Coordinators that cannot be fixed automatically due to missing data.

  ## Options

    * `replace`: Overwrite existing service files in database even if they already exist.
      

  """
  @spec commit_foxx_service_state(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def commit_foxx_service_state(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:replace])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :commit_foxx_service_state},
      url: "/_db/#{database_name}/_api/foxx/commit",
      method: :post,
      query: query,
      response: [{204, :null}],
      opts: opts
    })
  end

  @doc """
  Install a new service

  Installs the given new service at the given mount path.

  The request body can be any of the following formats:

  - `application/zip`: a raw zip bundle containing a service
  - `application/javascript`: a standalone JavaScript file
  - `application/json`: a service definition as JSON
  - `multipart/form-data`: a service definition as a multipart form

  A service definition is an object or form with the following properties or fields:

  - `configuration`: a JSON object describing configuration values
  - `dependencies`: a JSON object describing dependency settings
  - `source`: a fully qualified URL or an absolute path on the server's file system

  When using multipart data, the `source` field can also alternatively be a file field
  containing either a zip bundle or a standalone JavaScript file.

  When using a standalone JavaScript file the given file will be executed
  to define our service's HTTP endpoints. It is the same which would be defined
  in the field `main` of the service manifest.

  If `source` is a URL, the URL must be reachable from the server.
  If `source` is a file system path, the path will be resolved on the server.
  In either case the path or URL is expected to resolve to a zip bundle,
  JavaScript file or (in case of a file system path) directory.

  Note that when using file system paths in a cluster with multiple Coordinators
  the file system path must resolve to equivalent files on every Coordinator.

  ## Options

    * `mount`: Mount path the service should be installed at.
      
    * `development`: Set to `true` to enable development mode.
      
    * `setup`: Set to `false` to not run the service's setup script.
      
    * `legacy`: Set to `true` to install the service in 2.8 legacy compatibility mode.
      

  """
  @spec create_foxx_service(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_foxx_service(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:development, :legacy, :mount, :setup])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :create_foxx_service},
      url: "/_db/#{database_name}/_api/foxx",
      method: :post,
      query: query,
      response: [{201, :null}],
      opts: opts
    })
  end

  @doc """
  Uninstall a service

  Removes the service at the given mount path from the database and file system.

  Returns an empty response on success.

  ## Options

    * `mount`: Mount path of the installed service.
      
    * `teardown`: Set to `false` to not run the service's teardown script.
      

  """
  @spec delete_foxx_service(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_foxx_service(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount, :teardown])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :delete_foxx_service},
      url: "/_db/#{database_name}/_api/foxx/service",
      method: :delete,
      query: query,
      response: [{204, :null}],
      opts: opts
    })
  end

  @doc """
  Disable the development mode

  Puts the service at the given mount path into production mode.

  When running ArangoDB in a cluster with multiple Coordinators this will
  replace the service on all other Coordinators with the version on this
  Coordinator.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec disable_foxx_development_mode(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def disable_foxx_development_mode(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :disable_foxx_development_mode},
      url: "/_db/#{database_name}/_api/foxx/development",
      method: :delete,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Download a service bundle

  Downloads a zip bundle of the service directory.

  When development mode is enabled, this always creates a new bundle.

  Otherwise the bundle will represent the version of a service that
  is installed on that ArangoDB instance.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec download_foxx_service(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def download_foxx_service(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :download_foxx_service},
      url: "/_db/#{database_name}/_api/foxx/download",
      method: :post,
      query: query,
      response: [{200, :null}, {400, :null}],
      opts: opts
    })
  end

  @doc """
  Enable the development mode

  Puts the service into development mode.

  While the service is running in development mode the service will be reloaded
  from the filesystem and its setup script (if any) will be re-executed every
  time the service handles a request.

  When running ArangoDB in a cluster with multiple Coordinators note that changes
  to the filesystem on one Coordinator will not be reflected across the other
  Coordinators. This means you should treat your Coordinators as inconsistent
  as long as any service is running in development mode.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec enable_foxx_development_mode(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def enable_foxx_development_mode(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :enable_foxx_development_mode},
      url: "/_db/#{database_name}/_api/foxx/development",
      method: :post,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Get the configuration options

  Fetches the current configuration for the service at the given mount path.

  Returns an object mapping the configuration option names to their definitions
  including a human-friendly `title` and the `current` value (if any).

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec get_foxx_configuration(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_foxx_configuration(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :get_foxx_configuration},
      url: "/_db/#{database_name}/_api/foxx/configuration",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Get the dependency options

  Fetches the current dependencies for service at the given mount path.

  Returns an object mapping the dependency names to their definitions
  including a human-friendly `title` and the `current` mount path (if any).

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec get_foxx_dependencies(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_foxx_dependencies(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :get_foxx_dependencies},
      url: "/_db/#{database_name}/_api/foxx/dependencies",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Get the service README

  Fetches the service's README or README.md file's contents if any.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec get_foxx_readme(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_foxx_readme(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :get_foxx_readme},
      url: "/_db/#{database_name}/_api/foxx/readme",
      method: :get,
      query: query,
      response: [{200, :null}, {204, :null}],
      opts: opts
    })
  end

  @doc """
  Get the service description

  Fetches detailed information for the service at the given mount path.

  Returns an object with the following attributes:

  - `mount`: the mount path of the service
  - `path`: the local file system path of the service
  - `development`: `true` if the service is running in development mode
  - `legacy`: `true` if the service is running in 2.8 legacy compatibility mode
  - `manifest`: the normalized JSON manifest of the service

  Additionally the object may contain the following attributes if they have been set on the manifest:

  - `name`: a string identifying the service type
  - `version`: a semver-compatible version string

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec get_foxx_service_description(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_foxx_service_description(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :get_foxx_service_description},
      url: "/_db/#{database_name}/_api/foxx/service",
      method: :get,
      query: query,
      response: [{200, :null}, {400, :null}],
      opts: opts
    })
  end

  @doc """
  Get the Swagger description

  Fetches the Swagger API description for the service at the given mount path.

  The response body will be an OpenAPI 2.0 compatible JSON description of the service API.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec get_foxx_swagger_description(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_foxx_swagger_description(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :get_foxx_swagger_description},
      url: "/_db/#{database_name}/_api/foxx/swagger",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  List the service scripts

  Fetches a list of the scripts defined by the service.

  Returns an object mapping the raw script names to human-friendly names.

  ## Options

    * `mount`: Mount path of the installed service.
      

  """
  @spec list_foxx_scripts(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_foxx_scripts(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :list_foxx_scripts},
      url: "/_db/#{database_name}/_api/foxx/scripts",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  List the installed services

  Fetches a list of services installed in the current database.

  Returns a list of objects with the following attributes:

  - `mount`: the mount path of the service
  - `development`: `true` if the service is running in development mode
  - `legacy`: `true` if the service is running in 2.8 legacy compatibility mode
  - `provides`: the service manifest's `provides` value or an empty object

  Additionally the object may contain the following attributes if they have been set on the manifest:

  - `name`: a string identifying the service type
  - `version`: a semver-compatible version string

  ## Options

    * `excludeSystem`: Whether or not system services should be excluded from the result.
      

  """
  @spec list_foxx_services(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_foxx_services(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:excludeSystem])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :list_foxx_services},
      url: "/_db/#{database_name}/_api/foxx",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Replace the configuration options

  Replaces the given service's configuration completely.

  Returns an object mapping all configuration option names to their new values.

  ## Options

    * `mount`: Mount path of the installed service.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_foxx_configuration(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_foxx_configuration(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Foxx, :replace_foxx_configuration},
      url: "/_db/#{database_name}/_api/foxx/configuration",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Replace the dependency options

  Replaces the given service's dependencies completely.

  Returns an object mapping all dependency names to their new mount paths.

  ## Options

    * `mount`: Mount path of the installed service.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_foxx_dependencies(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_foxx_dependencies(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Foxx, :replace_foxx_dependencies},
      url: "/_db/#{database_name}/_api/foxx/dependencies",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Replace a service

  Removes the service at the given mount path from the database and file system.
  Then installs the given new service at the same mount path.

  This is a slightly safer equivalent to performing an uninstall of the old service
  followed by installing the new service. The new service's main and script files
  (if any) will be checked for basic syntax errors before the old service is removed.

  The request body can be any of the following formats:

  - `application/zip`: a raw zip bundle containing a service
  - `application/javascript`: a standalone JavaScript file
  - `application/json`: a service definition as JSON
  - `multipart/form-data`: a service definition as a multipart form

  A service definition is an object or form with the following properties or fields:

  - `configuration`: a JSON object describing configuration values
  - `dependencies`: a JSON object describing dependency settings
  - `source`: a fully qualified URL or an absolute path on the server's file system

  When using multipart data, the `source` field can also alternatively be a file field
  containing either a zip bundle or a standalone JavaScript file.

  When using a standalone JavaScript file the given file will be executed
  to define our service's HTTP endpoints. It is the same which would be defined
  in the field `main` of the service manifest.

  If `source` is a URL, the URL must be reachable from the server.
  If `source` is a file system path, the path will be resolved on the server.
  In either case the path or URL is expected to resolve to a zip bundle,
  JavaScript file or (in case of a file system path) directory.

  Note that when using file system paths in a cluster with multiple Coordinators
  the file system path must resolve to equivalent files on every Coordinator.

  ## Options

    * `mount`: Mount path of the installed service.
      
    * `teardown`: Set to `false` to not run the old service's teardown script.
      
    * `setup`: Set to `false` to not run the new service's setup script.
      
    * `legacy`: Set to `true` to install the new service in 2.8 legacy compatibility mode.
      
    * `force`: Set to `true` to force service install even if no service is installed under given mount.
      

  """
  @spec replace_foxx_service(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_foxx_service(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:force, :legacy, :mount, :setup, :teardown])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :replace_foxx_service},
      url: "/_db/#{database_name}/_api/foxx/service",
      method: :put,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Run a service script

  Runs the given script for the service at the given mount path.

  Returns the exports of the script, if any.

  ## Options

    * `mount`: Mount path of the installed service.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec run_foxx_script(database_name :: String.t(), name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def run_foxx_script(database_name, name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name, name: name, body: body],
      call: {Arangox.Api.Foxx, :run_foxx_script},
      url: "/_db/#{database_name}/_api/foxx/scripts/#{name}",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Run the service tests

  Runs the tests for the service at the given mount path and returns the results.

  Supported test reporters are:

  - `default`: a simple list of test cases
  - `suite`: an object of test cases nested in suites
  - `stream`: a raw stream of test results
  - `xunit`: an XUnit/JUnit compatible structure
  - `tap`: a raw TAP compatible stream

  The `Accept` request header can be used to further control the response format:

  When using the `stream` reporter `application/x-ldjson` will result
  in the response body being formatted as a newline-delimited JSON stream.

  When using the `tap` reporter `text/plain` or `text/*` will result
  in the response body being formatted as a plain text TAP report.

  When using the `xunit` reporter `application/xml` or `text/xml` will result
  in the response body being formatted as XML instead of JSONML.

  Otherwise the response body will be formatted as non-prettyprinted JSON.

  ## Options

    * `mount`: Mount path of the installed service.
      
    * `reporter`: Test reporter to use.
      
    * `idiomatic`: Use the matching format for the reporter, regardless of the `Accept` header.
      
    * `filter`: Only run tests where the full name (including full test suites and test case)
      matches this string.
      

  """
  @spec run_foxx_tests(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def run_foxx_tests(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:filter, :idiomatic, :mount, :reporter])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :run_foxx_tests},
      url: "/_db/#{database_name}/_api/foxx/tests",
      method: :post,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Update the configuration options

  Replaces the given service's configuration partially.

  Returns an object mapping all configuration option names to their new values.

  ## Options

    * `mount`: Mount path of the installed service.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_foxx_configuration(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_foxx_configuration(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Foxx, :update_foxx_configuration},
      url: "/_db/#{database_name}/_api/foxx/configuration",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Update the dependency options

  Replaces the given service's dependencies.

  Returns an object mapping all dependency names to their new mount paths.

  ## Options

    * `mount`: Mount path of the installed service.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_foxx_dependencies(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_foxx_dependencies(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:mount])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Foxx, :update_foxx_dependencies},
      url: "/_db/#{database_name}/_api/foxx/dependencies",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Upgrade a service

  Installs the given new service on top of the service currently installed at the given mount path.
  This is only recommended for switching between different versions of the same service.

  Unlike replacing a service, upgrading a service retains the old service's configuration
  and dependencies (if any) and should therefore only be used to migrate an existing service
  to a newer or equivalent service.

  The request body can be any of the following formats:

  - `application/zip`: a raw zip bundle containing a service
  - `application/javascript`: a standalone JavaScript file
  - `application/json`: a service definition as JSON
  - `multipart/form-data`: a service definition as a multipart form

  A service definition is an object or form with the following properties or fields:

  - `configuration`: a JSON object describing configuration values
  - `dependencies`: a JSON object describing dependency settings
  - `source`: a fully qualified URL or an absolute path on the server's file system

  When using multipart data, the `source` field can also alternatively be a file field
  containing either a zip bundle or a standalone JavaScript file.

  When using a standalone JavaScript file the given file will be executed
  to define our service's HTTP endpoints. It is the same which would be defined
  in the field `main` of the service manifest.

  If `source` is a URL, the URL must be reachable from the server.
  If `source` is a file system path, the path will be resolved on the server.
  In either case the path or URL is expected to resolve to a zip bundle,
  JavaScript file or (in case of a file system path) directory.

  Note that when using file system paths in a cluster with multiple Coordinators
  the file system path must resolve to equivalent files on every Coordinator.

  ## Options

    * `mount`: Mount path of the installed service.
      
    * `teardown`: Set to `true` to run the old service's teardown script.
      
    * `setup`: Set to `false` to not run the new service's setup script.
      
    * `legacy`: Set to `true` to install the new service in 2.8 legacy compatibility mode.
      
    * `force`: Set to `true` to force service install even if no service is installed under given mount.
      

  """
  @spec upgrade_foxx_service(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def upgrade_foxx_service(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:force, :legacy, :mount, :setup, :teardown])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Foxx, :upgrade_foxx_service},
      url: "/_db/#{database_name}/_api/foxx/service",
      method: :patch,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end
end
