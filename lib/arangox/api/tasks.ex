defmodule Arangox.Api.Tasks do
  @moduledoc """
  ArangoDB's Tasks operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all tasks

  Fetches all existing tasks on the server.
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "tasks"],
      opts: opts
    )
  end

  @doc """
  List all tasks. Raises on error.

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
  Create a task

  Creates a new task with a generated identifier.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "tasks"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a task. Raises on error.

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
  Create a task with ID

  Registers a new task with the specified ID.

  Not compatible with load balancers.
  """
  @spec create_with_id(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_with_id(conn, id, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "tasks", id],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a task with ID. Raises on error.

  See `create_with_id/3`.
  """
  @spec create_with_id!(Arangox.conn(), binary, term, keyword) :: term
  def create_with_id!(conn, id, body, opts \\ []) do
    case create_with_id(conn, id, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete a task

  Deletes the task identified by `id` on the server.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "tasks", id],
      opts: opts
    )
  end

  @doc """
  Delete a task. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, id, opts \\ []) do
    case delete(conn, id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a task

  fetches one existing task on the server specified by `id`
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "tasks", id],
      opts: opts
    )
  end

  @doc """
  Get a task. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, id, opts \\ []) do
    case get(conn, id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
