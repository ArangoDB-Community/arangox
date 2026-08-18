defmodule Arangox.Api.Tasks do
  @moduledoc """
  Provides API endpoints related to tasks
  """

  @default_client Arangox.Api.Client

  @type create_task_200_json_resp :: %{
          command: String.t(),
          created: number,
          database: String.t(),
          id: String.t(),
          name: String.t(),
          offset: number,
          period: number,
          type: String.t()
        }

  @doc """
  Create a task

  Creates a new task with a generated identifier.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_task(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_task(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Tasks, :create_task},
      url: "/_db/#{database_name}/_api/tasks",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, {Arangox.Api.Tasks, :create_task_200_json_resp}}, {400, :null}],
      opts: opts
    })
  end

  @type create_task_with_id_200_json_resp :: %{
          command: String.t(),
          created: number,
          database: String.t(),
          id: String.t(),
          name: String.t(),
          offset: number,
          period: number,
          type: String.t()
        }

  @doc """
  Create a task with ID

  Registers a new task with the specified ID.

  Not compatible with load balancers.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_task_with_id(database_name :: String.t(), id :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_task_with_id(database_name, id, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, id: id, body: body],
      call: {Arangox.Api.Tasks, :create_task_with_id},
      url: "/_db/#{database_name}/_api/tasks/#{id}",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Tasks, :create_task_with_id_200_json_resp}},
        {400, :null},
        {409, :null}
      ],
      opts: opts
    })
  end

  @type delete_task_200_json_resp :: %{code: integer, error: boolean}

  @type delete_task_404_json_resp :: %{code: integer, error: boolean, errorMessage: String.t()}

  @doc """
  Delete a task

  Deletes the task identified by `id` on the server.

  """
  @spec delete_task(database_name :: String.t(), id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_task(database_name, id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, id: id],
      call: {Arangox.Api.Tasks, :delete_task},
      url: "/_db/#{database_name}/_api/tasks/#{id}",
      method: :delete,
      response: [
        {200, {Arangox.Api.Tasks, :delete_task_200_json_resp}},
        {404, {Arangox.Api.Tasks, :delete_task_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_task_200_json_resp :: %{
          command: String.t(),
          created: number,
          database: String.t(),
          id: String.t(),
          name: String.t(),
          offset: number,
          period: number,
          type: String.t()
        }

  @doc """
  Get a task

  fetches one existing task on the server specified by `id`

  """
  @spec get_task(database_name :: String.t(), id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_task(database_name, id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, id: id],
      call: {Arangox.Api.Tasks, :get_task},
      url: "/_db/#{database_name}/_api/tasks/#{id}",
      method: :get,
      response: [{200, {Arangox.Api.Tasks, :get_task_200_json_resp}}],
      opts: opts
    })
  end

  @type list_tasks_200_json_resp :: %{
          command: String.t(),
          created: number,
          database: String.t(),
          id: String.t(),
          name: String.t(),
          offset: number,
          period: number,
          type: String.t()
        }

  @doc """
  List all tasks

  Fetches all existing tasks on the server.

  """
  @spec list_tasks(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_tasks(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Tasks, :list_tasks},
      url: "/_db/#{database_name}/_api/tasks",
      method: :get,
      response: [{200, [{Arangox.Api.Tasks, :list_tasks_200_json_resp}]}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:create_task_200_json_resp) do
    [
      command: :string,
      created: :number,
      database: :string,
      id: :string,
      name: :string,
      offset: :number,
      period: :number,
      type: {:enum, ["periodic", "timed"]}
    ]
  end

  def __fields__(:create_task_with_id_200_json_resp) do
    [
      command: :string,
      created: :number,
      database: :string,
      id: :string,
      name: :string,
      offset: :number,
      period: :number,
      type: {:enum, ["periodic", "timed"]}
    ]
  end

  def __fields__(:delete_task_200_json_resp) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:delete_task_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string]
  end

  def __fields__(:get_task_200_json_resp) do
    [
      command: :string,
      created: :number,
      database: :string,
      id: :string,
      name: :string,
      offset: :number,
      period: :number,
      type: :string
    ]
  end

  def __fields__(:list_tasks_200_json_resp) do
    [
      command: :string,
      created: :number,
      database: :string,
      id: :string,
      name: :string,
      offset: :number,
      period: :number,
      type: :string
    ]
  end
end
