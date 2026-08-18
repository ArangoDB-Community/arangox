defmodule Arangox.Api.Databases do
  @moduledoc """
  Provides API endpoints related to databases
  """

  @default_client Arangox.Api.Client

  @doc """
  Create a database

  Creates a new database.

  The response is a JSON object with the attribute `result` set to `true`.

  > **INFO:**
  Creating a new database is only possible from within the `_system` database.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_database(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_database(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Databases, :create_database},
      url: "/_db/_system/_api/database",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{201, :null}, {400, :null}, {403, :null}, {409, :null}],
      opts: opts
    })
  end

  @doc """
  Drop a database

  Drops the database along with all data stored in it.

  > **INFO:**
  Dropping a database is only possible from within the `_system` database.
  The `_system` database itself cannot be dropped.

  """
  @spec delete_database(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_database(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Databases, :delete_database},
      url: "/_db/_system/_api/database/#{database_name}",
      method: :delete,
      response: [{200, :null}, {400, :null}, {403, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Get information about the current database

  Retrieves the properties of the current database

  The response is a JSON object with the following attributes:

  - `name`: the name of the current database
  - `id`: the id of the current database
  - `path`: the filesystem path of the current database
  - `isSystem`: whether or not the current database is the `_system` database
  - `sharding`: the default sharding method for collections created in this database
  - `replicationFactor`: the default replication factor for collections in this database
  - `writeConcern`: the default write concern for collections in this database

  """
  @spec get_current_database(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_current_database(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Databases, :get_current_database},
      url: "/_db/#{database_name}/_api/database/current",
      method: :get,
      response: [{200, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  List all databases

  Retrieves the list of all existing databases

  > **INFO:**
  Retrieving the list of databases is only possible from within the `_system` database.

  """
  @spec list_databases(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_databases(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Databases, :list_databases},
      url: "/_db/_system/_api/database",
      method: :get,
      response: [{200, :null}, {400, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  List the accessible databases

  Retrieves the list of all databases the current user can access without
  specifying a different username or password.

  """
  @spec list_user_accessible_databases(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_user_accessible_databases(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Databases, :list_user_accessible_databases},
      url: "/_db/#{database_name}/_api/database/user",
      method: :get,
      response: [{200, :null}, {400, :null}],
      opts: opts
    })
  end
end
