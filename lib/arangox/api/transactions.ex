defmodule Arangox.Api.Transactions do
  @moduledoc """
  Provides API endpoints related to transactions
  """

  @default_client Arangox.Api.Client

  @type abort_stream_transaction_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Transactions.abort_stream_transaction_200_json_resp_result()
        }

  @type abort_stream_transaction_200_json_resp_result :: %{id: String.t(), status: String.t()}

  @type abort_stream_transaction_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type abort_stream_transaction_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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
  @spec abort_stream_transaction(
          database_name :: String.t(),
          transaction_id :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def abort_stream_transaction(database_name, transaction_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, transaction_id: transaction_id],
      call: {Arangox.Api.Transactions, :abort_stream_transaction},
      url: "/_db/#{database_name}/_api/transaction/#{transaction_id}",
      method: :delete,
      response: [
        {200, {Arangox.Api.Transactions, :abort_stream_transaction_200_json_resp}},
        {400, {Arangox.Api.Transactions, :abort_stream_transaction_400_json_resp}},
        {404, {Arangox.Api.Transactions, :abort_stream_transaction_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type begin_stream_transaction_201_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Transactions.begin_stream_transaction_201_json_resp_result()
        }

  @type begin_stream_transaction_201_json_resp_result :: %{id: String.t(), status: String.t()}

  @type begin_stream_transaction_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type begin_stream_transaction_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec begin_stream_transaction(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def begin_stream_transaction(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Transactions, :begin_stream_transaction},
      url: "/_db/#{database_name}/_api/transaction/begin",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Transactions, :begin_stream_transaction_201_json_resp}},
        {400, {Arangox.Api.Transactions, :begin_stream_transaction_400_json_resp}},
        {404, {Arangox.Api.Transactions, :begin_stream_transaction_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type commit_stream_transaction_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Transactions.commit_stream_transaction_200_json_resp_result()
        }

  @type commit_stream_transaction_200_json_resp_result :: %{id: String.t(), status: String.t()}

  @type commit_stream_transaction_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type commit_stream_transaction_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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
  @spec commit_stream_transaction(
          database_name :: String.t(),
          transaction_id :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def commit_stream_transaction(database_name, transaction_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, transaction_id: transaction_id],
      call: {Arangox.Api.Transactions, :commit_stream_transaction},
      url: "/_db/#{database_name}/_api/transaction/#{transaction_id}",
      method: :put,
      response: [
        {200, {Arangox.Api.Transactions, :commit_stream_transaction_200_json_resp}},
        {400, {Arangox.Api.Transactions, :commit_stream_transaction_400_json_resp}},
        {404, {Arangox.Api.Transactions, :commit_stream_transaction_404_json_resp}}
      ],
      opts: opts
    })
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

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec execute_java_script_transaction(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def execute_java_script_transaction(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Transactions, :execute_java_script_transaction},
      url: "/_db/#{database_name}/_api/transaction",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {400, :null}, {404, :null}, {500, :null}],
      opts: opts
    })
  end

  @type get_stream_transaction_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Transactions.get_stream_transaction_200_json_resp_result()
        }

  @type get_stream_transaction_200_json_resp_result :: %{id: String.t(), status: String.t()}

  @type get_stream_transaction_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_stream_transaction_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the status of a Stream Transaction

  Retrieve the status of a Stream Transaction by its identifier.

  After a transaction is committed or aborted, the server remembers its
  final state for a limited time. During this window, querying the
  transaction returns its final status (`committed` or `aborted`). Once
  the server garbage-collects this record, the same identifier becomes
  unknown and the endpoint returns `404`.

  """
  @spec get_stream_transaction(database_name :: String.t(), transaction_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_stream_transaction(database_name, transaction_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, transaction_id: transaction_id],
      call: {Arangox.Api.Transactions, :get_stream_transaction},
      url: "/_db/#{database_name}/_api/transaction/#{transaction_id}",
      method: :get,
      response: [
        {200, {Arangox.Api.Transactions, :get_stream_transaction_200_json_resp}},
        {400, {Arangox.Api.Transactions, :get_stream_transaction_400_json_resp}},
        {404, {Arangox.Api.Transactions, :get_stream_transaction_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_stream_transactions_200_json_resp :: %{
          transactions: [
            Arangox.Api.Transactions.list_stream_transactions_200_json_resp_transactions()
          ]
        }

  @type list_stream_transactions_200_json_resp_transactions :: %{
          id: String.t(),
          state: String.t()
        }

  @doc """
  List the running Stream Transactions

  List the currently running Stream Transactions.
  In a cluster, the list contains the transactions from all Coordinators.

  """
  @spec list_stream_transactions(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_stream_transactions(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Transactions, :list_stream_transactions},
      url: "/_db/#{database_name}/_api/transaction",
      method: :get,
      response: [{200, {Arangox.Api.Transactions, :list_stream_transactions_200_json_resp}}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:abort_stream_transaction_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Transactions, :abort_stream_transaction_200_json_resp_result}
    ]
  end

  def __fields__(:abort_stream_transaction_200_json_resp_result) do
    [id: :string, status: {:const, "aborted"}]
  end

  def __fields__(:abort_stream_transaction_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:abort_stream_transaction_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:begin_stream_transaction_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Transactions, :begin_stream_transaction_201_json_resp_result}
    ]
  end

  def __fields__(:begin_stream_transaction_201_json_resp_result) do
    [id: :string, status: {:const, "running"}]
  end

  def __fields__(:begin_stream_transaction_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:begin_stream_transaction_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:commit_stream_transaction_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Transactions, :commit_stream_transaction_200_json_resp_result}
    ]
  end

  def __fields__(:commit_stream_transaction_200_json_resp_result) do
    [id: :string, status: {:const, "committed"}]
  end

  def __fields__(:commit_stream_transaction_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:commit_stream_transaction_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_stream_transaction_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Transactions, :get_stream_transaction_200_json_resp_result}
    ]
  end

  def __fields__(:get_stream_transaction_200_json_resp_result) do
    [id: :string, status: {:enum, ["running", "committed", "aborted"]}]
  end

  def __fields__(:get_stream_transaction_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_stream_transaction_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_stream_transactions_200_json_resp) do
    [
      transactions: [
        {Arangox.Api.Transactions, :list_stream_transactions_200_json_resp_transactions}
      ]
    ]
  end

  def __fields__(:list_stream_transactions_200_json_resp_transactions) do
    [id: :string, state: {:const, "running"}]
  end
end
