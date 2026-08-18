defmodule Arangox.Api.HotBackups do
  @moduledoc """
  Provides API endpoints related to hot backups
  """

  @default_client Arangox.Api.Client

  @doc """
  Create a backup

  Creates a consistent local backup "as soon as possible", very much
  like a snapshot in time, with a given label. The ambiguity in the
  phrase "as soon as possible" refers to the next window during which a
  global write lock across all databases can be obtained in order to
  guarantee consistency. Note that the backup at first resides on the
  same machine and hard drive as the original data. Make sure to upload
  it to a remote site for an actual backup.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_backup(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_backup(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :create_backup},
      url: "/_admin/backup/create",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{201, :null}, {400, :null}, {408, :null}],
      opts: opts
    })
  end

  @doc """
  Delete a backup

  Delete a specific local backup identified by the given `id`.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec delete_backup(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_backup(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :delete_backup},
      url: "/_admin/backup/delete",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Download a backup from a remote repository

  Download a specific local backup from a remote repository, or query
  progress on a previously scheduled download operation, or abort
  a running download operation.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec download_backup(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def download_backup(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :download_backup},
      url: "/_admin/backup/download",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {202, :null}, {400, :null}, {401, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  List all backups

  Lists all locally found backups.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec list_backups(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_backups(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :list_backups},
      url: "/_admin/backup/list",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {404, :null}, {405, :null}],
      opts: opts
    })
  end

  @doc """
  Restore a backup

  Restores a consistent local backup from a
  snapshot in time, with a given id. The backup snapshot must reside on
  the ArangoDB service locally.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec restore_backup(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def restore_backup(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :restore_backup},
      url: "/_admin/backup/restore",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}],
      opts: opts
    })
  end

  @doc """
  Upload a backup to a remote repository

  Upload a specific local backup to a remote repository, or query
  progress on a previously scheduled upload operation, or abort
  a running upload operation.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec upload_backup(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def upload_backup(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.HotBackups, :upload_backup},
      url: "/_admin/backup/upload",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {202, :null}, {400, :null}, {401, :null}, {404, :null}],
      opts: opts
    })
  end
end
