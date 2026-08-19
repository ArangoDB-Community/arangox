defmodule Arangox.Api.HotBackups do
  @moduledoc """
  ArangoDB's HotBackups operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all backups

  Lists all locally found backups.
  """
  @spec all(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "list"],
      body: body,
      opts: opts
    )
  end

  @doc """
  List all backups. Raises on error.

  See `all/2`.
  """
  @spec all!(Arangox.conn(), term, keyword) :: term
  def all!(conn, body, opts \\ []) do
    case all(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a backup

  Creates a consistent local backup "as soon as possible", very much
  like a snapshot in time, with a given label. The ambiguity in the
  phrase "as soon as possible" refers to the next window during which a
  global write lock across all databases can be obtained in order to
  guarantee consistency. Note that the backup at first resides on the
  same machine and hard drive as the original data. Make sure to upload
  it to a remote site for an actual backup.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "create"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a backup. Raises on error.

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
  Delete a backup

  Delete a specific local backup identified by the given `id`.
  """
  @spec delete(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "delete"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Delete a backup. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), term, keyword) :: term
  def delete!(conn, body, opts \\ []) do
    case delete(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Download a backup from a remote repository

  Download a specific local backup from a remote repository, or query
  progress on a previously scheduled download operation, or abort
  a running download operation.
  """
  @spec download(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def download(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "download"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Download a backup from a remote repository. Raises on error.

  See `download/2`.
  """
  @spec download!(Arangox.conn(), term, keyword) :: term
  def download!(conn, body, opts \\ []) do
    case download(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Restore a backup

  Restores a consistent local backup from a
  snapshot in time, with a given id. The backup snapshot must reside on
  the ArangoDB service locally.
  """
  @spec restore(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def restore(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "restore"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Restore a backup. Raises on error.

  See `restore/2`.
  """
  @spec restore!(Arangox.conn(), term, keyword) :: term
  def restore!(conn, body, opts \\ []) do
    case restore(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Upload a backup to a remote repository

  Upload a specific local backup to a remote repository, or query
  progress on a previously scheduled upload operation, or abort
  a running upload operation.
  """
  @spec upload(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def upload(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "backup", "upload"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Upload a backup to a remote repository. Raises on error.

  See `upload/2`.
  """
  @spec upload!(Arangox.conn(), term, keyword) :: term
  def upload!(conn, body, opts \\ []) do
    case upload(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
