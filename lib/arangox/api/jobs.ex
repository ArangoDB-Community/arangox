defmodule Arangox.Api.Jobs do
  @moduledoc """
  Provides API endpoints related to jobs
  """

  @default_client Arangox.Api.Client

  @type cancel_job_200_json_resp :: %{result: boolean}

  @type cancel_job_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type cancel_job_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Cancel an async job

  Cancels the currently running job identified by `job-id`. Note that it still
  might take some time to actually cancel the running async job.

  """
  @spec cancel_job(database_name :: String.t(), job_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def cancel_job(database_name, job_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, job_id: job_id],
      call: {Arangox.Api.Jobs, :cancel_job},
      url: "/_db/#{database_name}/_api/job/#{job_id}/cancel",
      method: :put,
      response: [
        {200, {Arangox.Api.Jobs, :cancel_job_200_json_resp}},
        {400, {Arangox.Api.Jobs, :cancel_job_400_json_resp}},
        {404, {Arangox.Api.Jobs, :cancel_job_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_job_200_json_resp :: %{result: boolean}

  @type delete_job_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_job_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Delete async job results

  Deletes either all job results, expired job results, or the result of a
  specific job.
  Clients can use this method to perform an eventual garbage collection of job
  results.

  ## Options

    * `stamp`: A Unix timestamp specifying the expiration threshold for when the `job-id` is
      set to `expired`.
      

  """
  @spec delete_job(database_name :: String.t(), job_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_job(database_name, job_id, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:stamp])

    client.request(%{
      args: [database_name: database_name, job_id: job_id],
      call: {Arangox.Api.Jobs, :delete_job},
      url: "/_db/#{database_name}/_api/job/#{job_id}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Jobs, :delete_job_200_json_resp}},
        {400, {Arangox.Api.Jobs, :delete_job_400_json_resp}},
        {404, {Arangox.Api.Jobs, :delete_job_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_job_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_job_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  List async jobs by status or get the status of specific job

  This endpoint returns either of the following, depending on the specified value
  for the `job-id` parameter:

  - The IDs of async jobs with a specific status
  - The processing status of a specific async job

  ## Options

    * `count`: The maximum number of job IDs to return per call. If not specified, a
      server-defined maximum value is used. Only applicable if you specify `pending`
      or `done` as `job-id` to list jobs.
      

  """
  @spec get_job(database_name :: String.t(), job_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_job(database_name, job_id, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:count])

    client.request(%{
      args: [database_name: database_name, job_id: job_id],
      call: {Arangox.Api.Jobs, :get_job},
      url: "/_db/#{database_name}/_api/job/#{job_id}",
      method: :get,
      query: query,
      response: [
        {200, [:string]},
        {204, :null},
        {400, {Arangox.Api.Jobs, :get_job_400_json_resp}},
        {404, {Arangox.Api.Jobs, :get_job_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_job_result_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_job_result_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the results of an async job

  Returns the result of an async job identified by `job-id` if it's ready.

  If the async job result is available on the server, the endpoint returns
  the original operation's result headers and body, plus the additional
  `x-arango-async-job-id` HTTP header. The result and job are then removed
  which means that you can retrieve the result exactly once.

  If the result is not available yet or if the job is not known (anymore),
  the additional header is not present and you can tell the status from
  the HTTP status code.

  """
  @spec get_job_result(database_name :: String.t(), job_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_job_result(database_name, job_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, job_id: job_id],
      call: {Arangox.Api.Jobs, :get_job_result},
      url: "/_db/#{database_name}/_api/job/#{job_id}",
      method: :put,
      response: [
        {204, :null},
        {400, {Arangox.Api.Jobs, :get_job_result_400_json_resp}},
        {404, {Arangox.Api.Jobs, :get_job_result_404_json_resp}},
        default: :null
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:cancel_job_200_json_resp) do
    [result: :boolean]
  end

  def __fields__(:cancel_job_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:cancel_job_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_job_200_json_resp) do
    [result: :boolean]
  end

  def __fields__(:delete_job_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_job_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_job_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_job_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_job_result_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_job_result_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
