defmodule Arangox.Api.Transactions do
  @moduledoc """
  ArangoDB's Transactions operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  Abort a Stream Transaction

  Abort a running server-side transaction. Aborting is an idempotent operation.
  It is not an error to abort a transaction more than once.

  The server remembers a transaction's final state for a limited time after
  it ends. As a result, the response can vary depending on when you call
  this endpoint:

  - While the transaction is still tracked: aborting an already-aborted
  transaction returns `200` (idempotent), and aborting an already-committed
  transaction returns `400`.
  - The first abort against an unknown identifier returns `404` and records
  it as aborted. Subsequent aborts for the same identifier return `200`
  until the record is garbage-collected, after which the identifier is
  again unknown and the next abort once more returns `404`.
  """
  @spec abort(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def abort(conn, transaction_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "transaction", transaction_id],
      opts: opts
    )
  end

  @doc """
  Abort a Stream Transaction. Raises on error.

  See `abort/2`.
  """
  @spec abort!(Arangox.conn(), binary, keyword) :: term
  def abort!(conn, transaction_id, opts \\ []) do
    case abort(conn, transaction_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List the running Stream Transactions

  List the currently running Stream Transactions.
  In a cluster, the list contains the transactions from all Coordinators.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "transactions" => [%{
          "id" => string,
          "state" => string
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "transaction"],
      opts: opts
    )
  end

  @doc """
  List the running Stream Transactions. Raises on error.

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
  Begin a Stream Transaction

  Begin a Stream Transaction that allows clients to call selected APIs over a
  short period of time, referencing the transaction ID, and have the server
  execute the operations transactionally.

  Committing or aborting a running transaction must be done by the client.
  It is bad practice to not commit or abort a transaction once you are done
  using it. It forces the server to keep resources and collection locks
  until the entire transaction times out.

  The transaction description must be passed in the body of the POST request.
  """
  @spec begin(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def begin(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "transaction", "begin"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Begin a Stream Transaction. Raises on error.

  See `begin/2`.
  """
  @spec begin!(Arangox.conn(), term, keyword) :: term
  def begin!(conn, body, opts \\ []) do
    case begin(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Commit a Stream Transaction

  Commit a running server-side transaction. Committing is an idempotent operation.
  It is not an error to commit a transaction more than once.

  The server remembers a transaction's final state for a limited time after
  it ends. As a result, the response can vary depending on when you call
  this endpoint:

  - While the transaction is still tracked: committing an already-committed
  transaction returns `200` (idempotent), and committing an already-aborted
  transaction returns `400`.
  - Once the server has garbage-collected the transaction's record, the
  identifier is no longer known and the endpoint returns `404`.
  """
  @spec commit(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def commit(conn, transaction_id, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "transaction", transaction_id],
      opts: opts
    )
  end

  @doc """
  Commit a Stream Transaction. Raises on error.

  See `commit/2`.
  """
  @spec commit!(Arangox.conn(), binary, keyword) :: term
  def commit!(conn, transaction_id, opts \\ []) do
    case commit(conn, transaction_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Execute a JavaScript Transaction

  > **WARNING:**
  JavaScript Transactions are deprecated from v3.12.0 onward and are
  removed in v4.0.


  The transaction description must be passed in the body of the POST request.

  If the transaction is fully executed and committed on the server,
  *HTTP 200* will be returned. Additionally, the return value of the
  code defined in `action` will be returned in the `result` attribute.

  For successfully committed transactions, the returned JSON object has the
  following properties:

  - `error`: boolean flag to indicate if an error occurred (`false`
  in this case)

  - `code`: the HTTP status code

  - `result`: the return value of the transaction

  If the transaction specification is either missing or malformed, the server
  will respond with *HTTP 400*.

  The body of the response will then contain a JSON object with additional error
  details. The object has the following attributes:

  - `error`: boolean flag to indicate that an error occurred (`true` in this case)

  - `code`: the HTTP status code

  - `errorNum`: the server error number

  - `errorMessage`: a descriptive error message

  If a transaction fails to commit, either by an exception thrown in the
  `action` code, or by an internal error, the server will respond with
  an error.
  Any other errors will be returned with any of the return codes
  *HTTP 400*, *HTTP 409*, or *HTTP 500*.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => integer
      }
  """
  @spec execute_javascript(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def execute_javascript(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "transaction"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Execute a JavaScript Transaction. Raises on error.

  See `execute_javascript/2`.
  """
  @spec execute_javascript!(Arangox.conn(), term, keyword) :: term
  def execute_javascript!(conn, body, opts \\ []) do
    case execute_javascript(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the status of a Stream Transaction

  Retrieve the status of a Stream Transaction by its identifier.

  After a transaction is committed or aborted, the server remembers its
  final state for a limited time. During this window, querying the
  transaction returns its final status (`committed` or `aborted`). Once
  the server garbage-collects this record, the same identifier becomes
  unknown and the endpoint returns `404`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => %{
          "id" => string,
          "status" => string
        }
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, transaction_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "transaction", transaction_id],
      opts: opts
    )
  end

  @doc """
  Get the status of a Stream Transaction. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, transaction_id, opts \\ []) do
    case get(conn, transaction_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
