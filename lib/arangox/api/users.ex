defmodule Arangox.Api.Users do
  @moduledoc """
  ArangoDB's Users operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List available users

  Fetches data about all users. You need the *Administrate* server access level
  in order to execute this REST call.  Otherwise, you will only get information
  about yourself.

  The call will return a JSON object with at least the following
  attributes on success:

  - `user`: The name of the user as a string.
  - `active`: Whether the user account is able to log in to the database system.
  - `extra`: A JSON object with extra user information. It is used by the web
  interface to store graph viewer settings and saved queries.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => [%{
          "active" => boolean,
          "extra" => %{},
          "user" => string
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "user"],
      opts: opts
    )
  end

  @doc """
  List available users. Raises on error.

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
  List a user&rsquo;s accessible databases

  Fetch the list of databases available to the specified `user`.

  You need *Administrate* permissions for the server access level in order to
  execute this REST call.

  The call will return a JSON object with the per-database access
  privileges for the specified user. The `result` object will contain
  the databases names as object keys, and the associated privileges
  for the database as values.

  In case you specified `full`, the result will contain the permissions
  for the databases as well as the permissions for the collections.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => %{}
      }
  """
  @spec all_databases(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_databases(conn, user, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "user", user, "database"],
      query: [full: "full"],
      opts: opts
    )
  end

  @doc """
  List a user&rsquo;s accessible databases. Raises on error.

  See `all_databases/2`.
  """
  @spec all_databases!(Arangox.conn(), binary, keyword) :: term
  def all_databases!(conn, user, opts \\ []) do
    case all_databases(conn, user, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a user&rsquo;s collection access level

  Returns the collection access level for a specific collection

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => string
      }
  """
  @spec collection_permissions(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def collection_permissions(conn, user, dbname, collection, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "user", user, "database", dbname, collection],
      opts: opts
    )
  end

  @doc """
  Get a user&rsquo;s collection access level. Raises on error.

  See `collection_permissions/4`.
  """
  @spec collection_permissions!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def collection_permissions!(conn, user, dbname, collection, opts \\ []) do
    case collection_permissions(conn, user, dbname, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a user

  Create a new user. You need server access level *Administrate* in order to
  execute this REST call.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "user"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a user. Raises on error.

  See `create/2`.
  """
  @spec create!(Arangox.conn(), term, keyword) :: term
  def create!(conn, body, opts \\ []) do
    case create(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a user&rsquo;s database access level

  Fetch the database access level for a specific database

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => string
      }
  """
  @spec database_permissions(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def database_permissions(conn, user, dbname, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "user", user, "database", dbname],
      opts: opts
    )
  end

  @doc """
  Get a user&rsquo;s database access level. Raises on error.

  See `database_permissions/3`.
  """
  @spec database_permissions!(Arangox.conn(), binary, binary, keyword) :: term
  def database_permissions!(conn, user, dbname, opts \\ []) do
    case database_permissions(conn, user, dbname, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove a user

  Removes an existing user, identified by `user`.

  You need *Administrate* permissions for the server access level in order to
  execute this REST call.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, user, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "user", user],
      opts: opts
    )
  end

  @doc """
  Remove a user. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, user, opts \\ []) do
    case delete(conn, user, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Clear a user&rsquo;s collection access level

  Clears the collection access level for the collection `collection` in the
  database `dbname` of user `user`. As consequence, the default collection
  access level is used. If there is no defined default collection access level,
  it defaults to *No access*.

  You need write permissions (*Administrate* access level) for the `_system`
  database in order to execute this REST call.
  """
  @spec delete_collection_permissions(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_collection_permissions(conn, user, dbname, collection, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "user", user, "database", dbname, collection],
      opts: opts
    )
  end

  @doc """
  Clear a user&rsquo;s collection access level. Raises on error.

  See `delete_collection_permissions/4`.
  """
  @spec delete_collection_permissions!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def delete_collection_permissions!(conn, user, dbname, collection, opts \\ []) do
    case delete_collection_permissions(conn, user, dbname, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Clear a user&rsquo;s database access level

  Clears the database access level for the database `dbname` of user `user`. As
  consequence, the default database access level is used. If there is no defined
  default database access level, it defaults to *No access*.

  You need write permissions (*Administrate* access level) for the `_system`
  database in order to execute this REST call.
  """
  @spec delete_database_permissions(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_database_permissions(conn, user, dbname, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "user", user, "database", dbname],
      opts: opts
    )
  end

  @doc """
  Clear a user&rsquo;s database access level. Raises on error.

  See `delete_database_permissions/3`.
  """
  @spec delete_database_permissions!(Arangox.conn(), binary, binary, keyword) :: term
  def delete_database_permissions!(conn, user, dbname, opts \\ []) do
    case delete_database_permissions(conn, user, dbname, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a user

  Fetches data about the specified user. You can fetch information about
  yourself or you need the *Administrate* server access level in order to
  execute this REST call.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "active" => boolean,
        "code" => integer,
        "error" => boolean,
        "extra" => %{},
        "user" => string
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, user, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "user", user],
      opts: opts
    )
  end

  @doc """
  Get a user. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, user, opts \\ []) do
    case get(conn, user, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace a user

  Replaces the data of an existing user. This resets the user's
  access levels for databases and collections. You need server access level
  *Administrate* in order to execute this REST call. Additionally, users can
  change their own data.
  """
  @spec replace(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def replace(conn, user, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "user", user],
      body: body,
      opts: opts
    )
  end

  @doc """
  Replace a user. Raises on error.

  See `replace/3`.
  """
  @spec replace!(Arangox.conn(), binary, term, keyword) :: term
  def replace!(conn, user, body, opts \\ []) do
    case replace(conn, user, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set a user&rsquo;s collection access level

  Sets the collection access level for the `collection` in the database `dbname`
  for user `user`. You need the *Administrate* server access level in order to
  execute this REST call.
  """
  @spec set_collection_permissions(Arangox.conn(), binary, binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def set_collection_permissions(conn, user, dbname, collection, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "user", user, "database", dbname, collection],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set a user&rsquo;s collection access level. Raises on error.

  See `set_collection_permissions/5`.
  """
  @spec set_collection_permissions!(Arangox.conn(), binary, binary, binary, term, keyword) :: term
  def set_collection_permissions!(conn, user, dbname, collection, body, opts \\ []) do
    case set_collection_permissions(conn, user, dbname, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set a user&rsquo;s database access level

  Sets the database access levels for the database `dbname` of user `user`. You
  need the *Administrate* server access level in order to execute this REST
  call.
  """
  @spec set_database_permissions(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def set_database_permissions(conn, user, dbname, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "user", user, "database", dbname],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set a user&rsquo;s database access level. Raises on error.

  See `set_database_permissions/4`.
  """
  @spec set_database_permissions!(Arangox.conn(), binary, binary, term, keyword) :: term
  def set_database_permissions!(conn, user, dbname, body, opts \\ []) do
    case set_database_permissions(conn, user, dbname, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update a user

  Partially modifies the data of an existing user. You need server access level
  *Administrate* in order to execute this REST call. Additionally, users can
  change their own data.
  """
  @spec update(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def update(conn, user, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "user", user],
      body: body,
      opts: opts
    )
  end

  @doc """
  Update a user. Raises on error.

  See `update/3`.
  """
  @spec update!(Arangox.conn(), binary, term, keyword) :: term
  def update!(conn, user, body, opts \\ []) do
    case update(conn, user, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
