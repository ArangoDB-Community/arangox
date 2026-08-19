defmodule Arangox.Api.Databases do
  @moduledoc """
  ArangoDB's Databases operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all databases

  Retrieves the list of all existing databases

  > **INFO:**
  Retrieving the list of databases is only possible from within the `_system` database.
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_db", "_system", "_api", "database"],
      opts: opts
    )
  end

  @doc """
  List all databases. Raises on error.

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
  List the accessible databases

  Retrieves the list of all databases the current user can access without
  specifying a different username or password.
  """
  @spec all_user_accessible(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_user_accessible(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "database", "user"],
      opts: opts
    )
  end

  @doc """
  List the accessible databases. Raises on error.

  See `all_user_accessible/1`.
  """
  @spec all_user_accessible!(Arangox.conn(), keyword) :: term
  def all_user_accessible!(conn, opts \\ []) do
    case all_user_accessible(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a database

  Creates a new database.

  The response is a JSON object with the attribute `result` set to `true`.

  > **INFO:**
  Creating a new database is only possible from within the `_system` database.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_db", "_system", "_api", "database"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a database. Raises on error.

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
  @spec current(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def current(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "database", "current"],
      opts: opts
    )
  end

  @doc """
  Get information about the current database. Raises on error.

  See `current/1`.
  """
  @spec current!(Arangox.conn(), keyword) :: term
  def current!(conn, opts \\ []) do
    case current(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Drop a database

  Drops the database along with all data stored in it.

  > **INFO:**
  Dropping a database is only possible from within the `_system` database.
  The `_system` database itself cannot be dropped.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, database_name, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_db", "_system", "_api", "database", database_name],
      opts: opts
    )
  end

  @doc """
  Drop a database. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, database_name, opts \\ []) do
    case delete(conn, database_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
