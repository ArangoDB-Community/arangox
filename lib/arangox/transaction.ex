defmodule Arangox.Transaction do
  @moduledoc """
  A handle to an ArangoDB stream transaction, carried as a value.

  `Arangox.begin_transaction/2` returns one. The handle form's functions
  (`Arangox.commit_transaction/3`, `Arangox.abort_transaction/3`,
  `Arangox.transaction_status/3`) and the `:transaction` per-request option
  accept only this struct, never a bare identifier binary.

  ## Identity travels in the request, never in the connection

  Where `Arangox.transaction/3` binds a transaction to one checked-out
  connection for the span of a closure, a handle carries the transaction's
  identity as a value. A request made with `transaction: handle` sends the
  identifier in its own `x-arango-trx-id` header, for that request only —
  connection state is never written, so a checked-in connection cannot carry
  one caller's transaction to the next.

  Any pooled connection to the same deployment can therefore serve any request
  of the transaction. Verified against an ArangoDB 3.12 cluster (3.12.4, three
  coordinators): a transaction begun through one coordinator accepted writes,
  served isolated reads, reported status, and committed or aborted through the
  other coordinators — the identifier encodes the issuing coordinator and
  foreign coordinators forward to it. That is the measured scope: any
  connection, any coordinator, one deployment. A handle means nothing to a
  different deployment, and this states measured behaviour rather than an
  unconditional promise about future server versions.

  ## The identifier is a bearer capability

  Any code that can reach the deployment with the pool's credentials and holds
  the identifier can read and write inside the transaction, commit it, or
  abort it. Server-assigned identifiers are sequential, so an identifier is
  also a hint about its neighbours. Treat the handle like authentication
  material: do not let it cross a trust boundary, and keep it out of URLs,
  logs and telemetry.

  The driver treats it that way itself: the identifier is redacted from
  `inspect/1` of this struct, from the headers of the request struct that
  `Arangox.request/6` echoes back, and from every error message the driver
  constructs. (The *server's* error messages may name the identifier — they
  are returned verbatim in `Arangox.Error`'s `:message`, as documented there.)

  ## Identifier shape

  A stream-transaction identifier on the wire is a nonempty string of decimal
  digits (`"3298558923352"`). The driver validates that shape before an
  identifier reaches a header or a request path, so a malformed value —
  anything empty, non-digit, or carrying control characters — is rejected
  locally and never goes near the wire. Wrap an identifier obtained outside
  this driver with `new/1`, which applies the same validation.

  A transaction lives in the database it was begun in: pass the same
  `:database` option to the requests, commit, abort and status calls that you
  passed to `Arangox.begin_transaction/2`.
  """

  alias Arangox.{Error, Request}

  @path "/_api/transaction"

  @typedoc "The server-assigned transaction identifier: a nonempty string of decimal digits."
  @type id :: binary

  @typedoc "A stream-transaction handle. Treat it as authentication material."
  @type t :: %__MODULE__{id: id}

  @enforce_keys [:id]
  defstruct [:id]

  @doc """
  Wraps a transaction identifier obtained outside this driver in a handle.

  `Arangox.begin_transaction/2` is the normal way to obtain a handle; this
  exists for identifiers that arrive from elsewhere (another process, another
  driver, an HTTP header). The identifier must be a nonempty string of decimal
  digits — the only shape the server issues — or an `ArgumentError` is raised.
  The error never echoes the value, which may be a live transaction identifier.

      iex> Arangox.Transaction.new("3298558923352")
      #Arangox.Transaction<id: "[redacted]">
  """
  @spec new(id) :: t
  def new(id) do
    case from_id(id) do
      {:ok, trx} -> trx
      {:error, %Error{message: message}} -> raise ArgumentError, message
    end
  end

  @doc false
  # Builds a handle from an identifier, validating shape. `Arangox` uses this
  # for the id the server names in a begin response, so every handle in
  # existence holds a validated identifier.
  @spec from_id(term) :: {:ok, t} | {:error, Error.t()}
  def from_id(id) do
    if valid_id?(id), do: {:ok, %__MODULE__{id: id}}, else: {:error, shape_error()}
  end

  @doc false
  # The validated identifier out of a handle. Every path that puts an
  # identifier into a header (`Arangox.Connection`'s `:transaction` option) or
  # into a request path (the builders below, via `Arangox`'s handle functions)
  # fetches it through here, so a struct built by hand around a malformed
  # value — control characters, path segments — is rejected before it can
  # reach the wire.
  @spec fetch_id(t) :: {:ok, id} | {:error, Error.t()}
  def fetch_id(%__MODULE__{id: id}) do
    if valid_id?(id), do: {:ok, id}, else: {:error, shape_error()}
  end

  @doc """
  Whether `id` has the shape of a stream-transaction identifier: a nonempty
  binary of decimal digits.

      iex> Arangox.Transaction.valid_id?("3298558923352")
      true

      iex> Arangox.Transaction.valid_id?("3298\\n5589")
      false
  """
  @spec valid_id?(term) :: boolean
  def valid_id?(id) when is_binary(id) and id != "", do: digits_only?(id)
  def valid_id?(_id), do: false

  @spec digits_only?(binary) :: boolean
  defp digits_only?(<<byte, rest::binary>>) when byte in ?0..?9, do: digits_only?(rest)
  defp digits_only?(<<>>), do: true
  defp digits_only?(_other), do: false

  # The rejected value is deliberately not echoed: it may be, or contain, a
  # live transaction identifier, and this message ends up in logs.
  @spec shape_error :: Error.t()
  defp shape_error do
    %Error{
      message:
        "invalid transaction identifier: expected a nonempty string of decimal " <>
          "digits. The value is not echoed because a transaction identifier is " <>
          "a bearer capability."
    }
  end

  ## Request builders
  #
  # One builder per server operation against the stream-transaction HTTP API
  # (`/_api/transaction`), returning the `Arangox.Request` and nothing else —
  # no header handling, no connection state; the caller decides what the
  # request executes against.
  #
  # Shared by the `DBConnection` transaction callbacks in `Arangox.Connection`
  # (the closure form) and the handle functions on `Arangox` (the handle form).
  # Keep the request shapes here so the two forms cannot drift apart.

  @doc false
  # The body of a begin request, from `t:Arangox.transaction_option/0`s.
  # `:read`/`:write`/`:exclusive` become the `collections` document, and
  # `:properties` entries are merged in as further top-level attributes. Every
  # other option is left for the request path to interpret.
  @spec begin_body([Arangox.transaction_option()]) :: map
  def begin_body(opts) when is_list(opts) do
    collections =
      opts
      |> Keyword.take([:read, :write, :exclusive])
      |> Enum.into(%{})

    opts
    |> Keyword.get(:properties, [])
    |> Enum.into(%{collections: collections})
  end

  @doc false
  # The request that begins a transaction. Success is a 201.
  @spec begin(map) :: Request.t()
  def begin(%{} = body), do: %Request{method: :post, path: @path <> "/begin", body: body}

  @doc false
  # The request that fetches a transaction's status. Success is a 200.
  @spec status(id) :: Request.t()
  def status(id) when is_binary(id), do: %Request{method: :get, path: path(id)}

  @doc false
  # The request that commits a transaction. Success is a 200.
  @spec commit(id) :: Request.t()
  def commit(id) when is_binary(id), do: %Request{method: :put, path: path(id)}

  @doc false
  # The request that aborts a transaction. Success is a 200.
  @spec abort(id) :: Request.t()
  def abort(id) when is_binary(id), do: %Request{method: :delete, path: path(id)}

  @spec path(id) :: binary
  defp path(id), do: @path <> "/" <> id
end

# The identifier is redacted from struct inspection the same as
# authentication material — it is a bearer capability, and `inspect/1` output
# is what lands in logs, error reports and crash dumps. Every handle inspects
# identically; read `trx.id` deliberately if the value itself is needed.
#
# Rendered as `#Arangox.Transaction<...>` rather than a redacted struct
# literal, which would suggest the output can be pasted back to reconstruct
# the value.
defimpl Inspect, for: Arangox.Transaction do
  def inspect(%Arangox.Transaction{}, _opts) do
    Inspect.Algebra.string(~s(#Arangox.Transaction<id: "[redacted]">))
  end
end
