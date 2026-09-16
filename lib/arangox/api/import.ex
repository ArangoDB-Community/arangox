defmodule Arangox.API.Import do
  @moduledoc """
  ArangoDB's Import operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

  @doc """
  Imports documents into a collection.

  The body is sent as given under `text/plain`, so it must already be a binary
  in one of the formats ArangoDB accepts. Say which one with `:type`:

    * `type: "documents"` - one JSON object per line (JSON Lines)
    * `type: "list"` - a single JSON array of objects
    * `type: "auto"` - let the server detect either of the above
    * no `:type` - the first line is a JSON array of attribute names, and every
      line after it is a JSON array of values in that same order

  Importing into an edge collection requires `_from` and `_to` on every
  document.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "created" => integer,
        "empty" => integer,
        "error" => boolean,
        "errors" => integer,
        "ignored" => integer,
        "updated" => integer
      }
  """
  @spec data(Arangox.conn(), binary, binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def data(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "import"],
      body: body,
      media: "text/plain; charset=utf-8",
      forced: [{"collection", collection}],
      query: [
        type: "type",
        ignore_missing: "ignoreMissing",
        from_prefix: "fromPrefix",
        to_prefix: "toPrefix",
        overwrite_collection_prefix: "overwriteCollectionPrefix",
        overwrite: "overwrite",
        wait_for_sync: "waitForSync",
        on_duplicate: "onDuplicate",
        complete: "complete",
        details: "details"
      ],
      opts: opts
    )
  end

  @doc """
  Import JSON data as documents. Raises on error.

  See `data/3`.
  """
  @spec data!(Arangox.conn(), binary, binary, keyword) :: term
  def data!(conn, collection, body, opts \\ []) do
    case data(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
