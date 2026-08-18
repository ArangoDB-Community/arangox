defmodule Arangox.Api.Users do
  @moduledoc """
  Provides API endpoints related to users
  """

  @default_client Arangox.Api.Client

  @doc """
  Create a user

  Create a new user. You need server access level *Administrate* in order to
  execute this REST call.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_user(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_user(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Users, :create_user},
      url: "/_db/#{database_name}/_api/user",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{201, :null}, {400, :null}, {401, :null}, {403, :null}, {409, :null}],
      opts: opts
    })
  end

  @doc """
  Remove a user

  Removes an existing user, identified by `user`.

  You need *Administrate* permissions for the server access level in order to
  execute this REST call.

  """
  @spec delete_user(database_name :: String.t(), user :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_user(database_name, user, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user],
      call: {Arangox.Api.Users, :delete_user},
      url: "/_db/#{database_name}/_api/user/#{user}",
      method: :delete,
      response: [{202, :null}, {401, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
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
  @spec delete_user_collection_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          collection :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_user_collection_permissions(database_name, user, dbname, collection, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, dbname: dbname, collection: collection],
      call: {Arangox.Api.Users, :delete_user_collection_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}/#{collection}",
      method: :delete,
      response: [{202, :null}, {400, :null}],
      opts: opts
    })
  end

  @doc """
  Clear a user&rsquo;s database access level

  Clears the database access level for the database `dbname` of user `user`. As
  consequence, the default database access level is used. If there is no defined
  default database access level, it defaults to *No access*.

  You need write permissions (*Administrate* access level) for the `_system`
  database in order to execute this REST call.

  """
  @spec delete_user_database_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_user_database_permissions(database_name, user, dbname, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, dbname: dbname],
      call: {Arangox.Api.Users, :delete_user_database_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}",
      method: :delete,
      response: [{202, :null}, {400, :null}],
      opts: opts
    })
  end

  @doc """
  Get a user

  Fetches data about the specified user. You can fetch information about
  yourself or you need the *Administrate* server access level in order to
  execute this REST call.

  """
  @spec get_user(database_name :: String.t(), user :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_user(database_name, user, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user],
      call: {Arangox.Api.Users, :get_user},
      url: "/_db/#{database_name}/_api/user/#{user}",
      method: :get,
      response: [{200, :null}, {401, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Get a user&rsquo;s collection access level

  Returns the collection access level for a specific collection

  """
  @spec get_user_collection_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          collection :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_user_collection_permissions(database_name, user, dbname, collection, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, dbname: dbname, collection: collection],
      call: {Arangox.Api.Users, :get_user_collection_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}/#{collection}",
      method: :get,
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Get a user&rsquo;s database access level

  Fetch the database access level for a specific database

  """
  @spec get_user_database_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_user_database_permissions(database_name, user, dbname, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, dbname: dbname],
      call: {Arangox.Api.Users, :get_user_database_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}",
      method: :get,
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
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

  ## Options

    * `full`: Return the full set of access levels for all databases and all collections.
      

  """
  @spec list_user_databases(database_name :: String.t(), user :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_user_databases(database_name, user, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:full])

    client.request(%{
      args: [database_name: database_name, user: user],
      call: {Arangox.Api.Users, :list_user_databases},
      url: "/_db/#{database_name}/_api/user/#{user}/database",
      method: :get,
      query: query,
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
  end

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

  """
  @spec list_users(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_users(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Users, :list_users},
      url: "/_db/#{database_name}/_api/user",
      method: :get,
      response: [{200, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Replace a user

  Replaces the data of an existing user. This resets the user's
  access levels for databases and collections. You need server access level
  *Administrate* in order to execute this REST call. Additionally, users can
  change their own data.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_user_data(database_name :: String.t(), user :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_user_data(database_name, user, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, body: body],
      call: {Arangox.Api.Users, :replace_user_data},
      url: "/_db/#{database_name}/_api/user/#{user}",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Set a user&rsquo;s collection access level

  Sets the collection access level for the `collection` in the database `dbname`
  for user `user`. You need the *Administrate* server access level in order to
  execute this REST call.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_user_collection_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_user_collection_permissions(database_name, user, dbname, collection, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [
        database_name: database_name,
        user: user,
        dbname: dbname,
        collection: collection,
        body: body
      ],
      call: {Arangox.Api.Users, :set_user_collection_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}/#{collection}",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Set a user&rsquo;s database access level

  Sets the database access levels for the database `dbname` of user `user`. You
  need the *Administrate* server access level in order to execute this REST
  call.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_user_database_permissions(
          database_name :: String.t(),
          user :: String.t(),
          dbname :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_user_database_permissions(database_name, user, dbname, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, dbname: dbname, body: body],
      call: {Arangox.Api.Users, :set_user_database_permissions},
      url: "/_db/#{database_name}/_api/user/#{user}/database/#{dbname}",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Update a user

  Partially modifies the data of an existing user. You need server access level
  *Administrate* in order to execute this REST call. Additionally, users can
  change their own data.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_user_data(database_name :: String.t(), user :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_user_data(database_name, user, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, user: user, body: body],
      call: {Arangox.Api.Users, :update_user_data},
      url: "/_db/#{database_name}/_api/user/#{user}",
      body: body,
      method: :patch,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {401, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end
end
