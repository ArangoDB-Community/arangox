defmodule Arangox.Api.Jobs do
  @moduledoc """
  ArangoDB's Jobs operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  Cancel an async job

  Cancels the currently running job identified by `job-id`. Note that it still
  might take some time to actually cancel the running async job.
  """
  @spec cancel(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def cancel(conn, job_id, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "job", job_id, "cancel"],
      opts: opts
    )
  end

  @doc """
  Cancel an async job. Raises on error.

  See `cancel/2`.
  """
  @spec cancel!(Arangox.conn(), binary, keyword) :: term
  def cancel!(conn, job_id, opts \\ []) do
    case cancel(conn, job_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete async job results

  Deletes either all job results, expired job results, or the result of a
  specific job.
  Clients can use this method to perform an eventual garbage collection of job
  results.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, job_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "job", job_id],
      query: [stamp: "stamp"],
      opts: opts
    )
  end

  @doc """
  Delete async job results. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, job_id, opts \\ []) do
    case delete(conn, job_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List async jobs by status or get the status of specific job

  This endpoint returns either of the following, depending on the specified value
  for the `job-id` parameter:

  - The IDs of async jobs with a specific status
  - The processing status of a specific async job
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, job_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "job", job_id],
      query: [count: "count"],
      opts: opts
    )
  end

  @doc """
  List async jobs by status or get the status of specific job. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, job_id, opts \\ []) do
    case get(conn, job_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec result(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def result(conn, job_id, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "job", job_id],
      opts: opts
    )
  end

  @doc """
  Get the results of an async job. Raises on error.

  See `result/2`.
  """
  @spec result!(Arangox.conn(), binary, keyword) :: term
  def result!(conn, job_id, opts \\ []) do
    case result(conn, job_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
