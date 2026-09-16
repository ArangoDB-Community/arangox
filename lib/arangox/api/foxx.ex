defmodule Arangox.API.Foxx do
  @moduledoc """
  ArangoDB's Foxx operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

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

  ## Returns

  Recorded against ArangoDB 3.12.10:

      [%{
        "development" => boolean,
        "legacy" => boolean,
        "mount" => string,
        "name" => string,
        "provides" => %{},
        "version" => string
      }]
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx"],
      query: [exclude_system: "excludeSystem"],
      opts: opts
    )
  end

  @doc """
  List the installed services. Raises on error.

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
  List the service scripts

  Fetches a list of the scripts defined by the service.

  Returns an object mapping the raw script names to human-friendly names.
  """
  @spec all_scripts(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_scripts(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "scripts"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  List the service scripts. Raises on error.

  See `all_scripts/2`.
  """
  @spec all_scripts!(Arangox.conn(), binary, keyword) :: term
  def all_scripts!(conn, mount, opts \\ []) do
    case all_scripts(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Commit the local service state

  Commits the local service state of the Coordinator to the database.

  This can be used to resolve service conflicts between Coordinators that cannot be fixed automatically due to missing data.
  """
  @spec commit_state(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def commit_state(conn, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx", "commit"],
      query: [replace: "replace"],
      opts: opts
    )
  end

  @doc """
  Commit the local service state. Raises on error.

  See `commit_state/1`.
  """
  @spec commit_state!(Arangox.conn(), keyword) :: term
  def commit_state!(conn, opts \\ []) do
    case commit_state(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the configuration options

  Fetches the current configuration for the service at the given mount path.

  Returns an object mapping the configuration option names to their definitions
  including a human-friendly `title` and the `current` value (if any).
  """
  @spec configuration(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def configuration(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "configuration"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Get the configuration options. Raises on error.

  See `configuration/2`.
  """
  @spec configuration!(Arangox.conn(), binary, keyword) :: term
  def configuration!(conn, mount, opts \\ []) do
    case configuration(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec create(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx"],
      forced: [{"mount", mount}],
      query: [development: "development", setup: "setup", legacy: "legacy"],
      opts: opts
    )
  end

  @doc """
  Install a new service. Raises on error.

  See `create/2`.
  """
  @spec create!(Arangox.conn(), binary, keyword) :: term
  def create!(conn, mount, opts \\ []) do
    case create(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Uninstall a service

  Removes the service at the given mount path from the database and file system.

  Returns an empty response on success.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "foxx", "service"],
      forced: [{"mount", mount}],
      query: [teardown: "teardown"],
      opts: opts
    )
  end

  @doc """
  Uninstall a service. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, mount, opts \\ []) do
    case delete(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the dependency options

  Fetches the current dependencies for service at the given mount path.

  Returns an object mapping the dependency names to their definitions
  including a human-friendly `title` and the `current` mount path (if any).
  """
  @spec dependencies(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def dependencies(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "dependencies"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Get the dependency options. Raises on error.

  See `dependencies/2`.
  """
  @spec dependencies!(Arangox.conn(), binary, keyword) :: term
  def dependencies!(conn, mount, opts \\ []) do
    case dependencies(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec description(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def description(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "service"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Get the service description. Raises on error.

  See `description/2`.
  """
  @spec description!(Arangox.conn(), binary, keyword) :: term
  def description!(conn, mount, opts \\ []) do
    case description(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Disable the development mode

  Puts the service at the given mount path into production mode.

  When running ArangoDB in a cluster with multiple Coordinators this will
  replace the service on all other Coordinators with the version on this
  Coordinator.
  """
  @spec disable_development_mode(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def disable_development_mode(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "foxx", "development"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Disable the development mode. Raises on error.

  See `disable_development_mode/2`.
  """
  @spec disable_development_mode!(Arangox.conn(), binary, keyword) :: term
  def disable_development_mode!(conn, mount, opts \\ []) do
    case disable_development_mode(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Download a service bundle

  Downloads a zip bundle of the service directory.

  When development mode is enabled, this always creates a new bundle.

  Otherwise the bundle will represent the version of a service that
  is installed on that ArangoDB instance.
  """
  @spec download(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def download(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx", "download"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Download a service bundle. Raises on error.

  See `download/2`.
  """
  @spec download!(Arangox.conn(), binary, keyword) :: term
  def download!(conn, mount, opts \\ []) do
    case download(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec enable_development_mode(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def enable_development_mode(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx", "development"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Enable the development mode. Raises on error.

  See `enable_development_mode/2`.
  """
  @spec enable_development_mode!(Arangox.conn(), binary, keyword) :: term
  def enable_development_mode!(conn, mount, opts \\ []) do
    case enable_development_mode(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the service README

  Fetches the service's README or README.md file's contents if any.
  """
  @spec readme(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def readme(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "readme"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Get the service README. Raises on error.

  See `readme/2`.
  """
  @spec readme!(Arangox.conn(), binary, keyword) :: term
  def readme!(conn, mount, opts \\ []) do
    case readme(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec replace(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def replace(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "foxx", "service"],
      forced: [{"mount", mount}],
      query: [teardown: "teardown", setup: "setup", legacy: "legacy", force: "force"],
      opts: opts
    )
  end

  @doc """
  Replace a service. Raises on error.

  See `replace/2`.
  """
  @spec replace!(Arangox.conn(), binary, keyword) :: term
  def replace!(conn, mount, opts \\ []) do
    case replace(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace the configuration options

  Replaces the given service's configuration completely.

  Returns an object mapping all configuration option names to their new values.
  """
  @spec replace_configuration(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_configuration(conn, mount, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "foxx", "configuration"],
      body: body,
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Replace the configuration options. Raises on error.

  See `replace_configuration/3`.
  """
  @spec replace_configuration!(Arangox.conn(), binary, term, keyword) :: term
  def replace_configuration!(conn, mount, body, opts \\ []) do
    case replace_configuration(conn, mount, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace the dependency options

  Replaces the given service's dependencies completely.

  Returns an object mapping all dependency names to their new mount paths.
  """
  @spec replace_dependencies(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_dependencies(conn, mount, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "foxx", "dependencies"],
      body: body,
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Replace the dependency options. Raises on error.

  See `replace_dependencies/3`.
  """
  @spec replace_dependencies!(Arangox.conn(), binary, term, keyword) :: term
  def replace_dependencies!(conn, mount, body, opts \\ []) do
    case replace_dependencies(conn, mount, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Run a service script

  Runs the given script for the service at the given mount path.

  Returns the exports of the script, if any.
  """
  @spec run_script(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def run_script(conn, name, mount, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx", "scripts", name],
      body: body,
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Run a service script. Raises on error.

  See `run_script/4`.
  """
  @spec run_script!(Arangox.conn(), binary, binary, term, keyword) :: term
  def run_script!(conn, name, mount, body, opts \\ []) do
    case run_script(conn, name, mount, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec run_tests(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def run_tests(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "foxx", "tests"],
      forced: [{"mount", mount}],
      query: [reporter: "reporter", idiomatic: "idiomatic", filter: "filter"],
      opts: opts
    )
  end

  @doc """
  Run the service tests. Raises on error.

  See `run_tests/2`.
  """
  @spec run_tests!(Arangox.conn(), binary, keyword) :: term
  def run_tests!(conn, mount, opts \\ []) do
    case run_tests(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the Swagger description

  Fetches the Swagger API description for the service at the given mount path.

  The response body will be an OpenAPI 2.0 compatible JSON description of the service API.
  """
  @spec swagger_description(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def swagger_description(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "foxx", "swagger"],
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Get the Swagger description. Raises on error.

  See `swagger_description/2`.
  """
  @spec swagger_description!(Arangox.conn(), binary, keyword) :: term
  def swagger_description!(conn, mount, opts \\ []) do
    case swagger_description(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update the configuration options

  Replaces the given service's configuration partially.

  Returns an object mapping all configuration option names to their new values.
  """
  @spec update_configuration(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_configuration(conn, mount, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "foxx", "configuration"],
      body: body,
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Update the configuration options. Raises on error.

  See `update_configuration/3`.
  """
  @spec update_configuration!(Arangox.conn(), binary, term, keyword) :: term
  def update_configuration!(conn, mount, body, opts \\ []) do
    case update_configuration(conn, mount, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update the dependency options

  Replaces the given service's dependencies.

  Returns an object mapping all dependency names to their new mount paths.
  """
  @spec update_dependencies(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_dependencies(conn, mount, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "foxx", "dependencies"],
      body: body,
      forced: [{"mount", mount}],
      opts: opts
    )
  end

  @doc """
  Update the dependency options. Raises on error.

  See `update_dependencies/3`.
  """
  @spec update_dependencies!(Arangox.conn(), binary, term, keyword) :: term
  def update_dependencies!(conn, mount, body, opts \\ []) do
    case update_dependencies(conn, mount, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
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
  """
  @spec upgrade(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def upgrade(conn, mount, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "foxx", "service"],
      forced: [{"mount", mount}],
      query: [teardown: "teardown", setup: "setup", legacy: "legacy", force: "force"],
      opts: opts
    )
  end

  @doc """
  Upgrade a service. Raises on error.

  See `upgrade/2`.
  """
  @spec upgrade!(Arangox.conn(), binary, keyword) :: term
  def upgrade!(conn, mount, opts \\ []) do
    case upgrade(conn, mount, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
