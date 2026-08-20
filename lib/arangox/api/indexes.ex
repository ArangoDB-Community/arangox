defmodule Arangox.Api.Indexes do
  @moduledoc """
  ArangoDB's Indexes operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all indexes of a collection

  Returns an object with an `indexes` attribute containing an array of all
  index descriptions for the given collection. The same information is also
  available in the `identifiers` attribute as an object with the index identifiers
  as object keys.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "identifiers" => %{
          "capture_1787176566/0" => %{
            "fields" => [string],
            "id" => string,
            "name" => string,
            "selectivityEstimate" => integer,
            "sparse" => boolean,
            "type" => string,
            "unique" => boolean
          },
          "capture_1787176566/284576" => %{
            "cacheEnabled" => boolean,
            "deduplicate" => boolean,
            "estimates" => boolean,
            "fields" => [string],
            "id" => string,
            "name" => string,
            "selectivityEstimate" => integer,
            "sparse" => boolean,
            "type" => string,
            "unique" => boolean
          }
        },
        "indexes" => [%{
          "fields" => [string],
          "id" => string,
          "name" => string,
          "selectivityEstimate" => integer,
          "sparse" => boolean,
          "type" => string,
          "unique" => boolean
        }]
      }
  """
  @spec all(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, collection, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "index"],
      forced: [{"collection", collection}],
      query: [with_stats: "withStats", with_hidden: "withHidden"],
      opts: opts
    )
  end

  @doc """
  List all indexes of a collection. Raises on error.

  See `all/2`.
  """
  @spec all!(Arangox.conn(), binary, keyword) :: term
  def all!(conn, collection, opts \\ []) do
    case all(conn, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create an index

  Creates a new index in the collection `collection`. Expects
  an object containing the index details.

  The type of the index to be created must specified in the **type**
  attribute of the index details. Depending on the index type, additional
  other attributes may need to specified in the request in order to create
  the index.

  Indexes require the to be indexed attribute(s) in the **fields** attribute
  of the index details. Depending on the index type, a single attribute or
  multiple attributes can be indexed. In the latter case, an array of
  strings is expected.

  The `.` character denotes sub-attributes in attribute paths. Attributes with
  literal `.` in their name cannot be indexed. Attributes with the name `_id`
  cannot be indexed either, neither as a top-level attribute nor as a sub-attribute.

  Optionally, an index name may be specified as a string in the **name** attribute.
  Index names have the same restrictions as collection names. If no value is
  specified, one will be auto-generated.

  Persistent indexes (including vertex-centric indexes) can be created as unique
  or non-unique variants. Uniqueness can be controlled by specifying the
  **unique** option for the index definition. Setting it to `true` creates a
  unique index. Setting it to `false` or omitting the `unique` attribute creates a
  non-unique index.

  > **INFO:**
  Unique indexes on non-shard keys are not supported in cluster deployments.


  Persistent indexes can optionally be created in a sparse
  variant. A sparse index will be created if the **sparse** attribute in
  the index details is set to `true`. Sparse indexes do not index documents
  for which any of the index attributes is either not set or is `null`.

  The optional **deduplicate** attribute is supported by persistent array indexes.
  It controls whether inserting duplicate index values
  from the same document into a unique array index will lead to a unique constraint
  error or not. The default value is `true`, so only a single instance of each
  non-unique index value will be inserted into the index per document. Trying to
  insert a value into the index that already exists in the index always fails,
  regardless of the value of this attribute.

  The optional **estimates** attribute is supported by `persistent`, `mdi`, and
  `mdi-prefixed` indexes. This attribute controls whether index selectivity estimates are
  maintained for the index. Not maintaining index selectivity estimates can have
  a slightly positive impact on write performance.
  The downside of turning off index selectivity estimates will be that
  the query optimizer will not be able to determine the usefulness of different
  competing indexes in AQL queries when there are multiple candidate indexes to
  choose from.
  The `estimates` attribute is optional and defaults to `true` if not set. It will
  have no effect on indexes other than persistent indexes.

  The optional attribute **cacheEnabled** is supported by indexes of type
  `persistent`. This attribute controls whether an extra in-memory hash cache is
  created for the index. The hash cache can be used to speed up index lookups.
  The cache can only be used for queries that look up all index attributes via
  an equality lookup (`==`). The hash cache cannot be used for range scans,
  partial lookups or sorting.
  The cache will be populated lazily upon reading data from the index. Writing data
  into the collection or updating existing data will invalidate entries in the
  cache. The cache may have a negative effect on performance in case index values
  are updated more often than they are read.
  The maximum size of cache entries that can be stored is currently 4 MB, i.e.
  the cumulated size of all index entries for any index lookup value must be
  less than 4 MB. This limitation is there to avoid storing the index entries
  of "super nodes" in the cache.
  `cacheEnabled` defaults to `false` and should only be used for indexes that
  are known to benefit from an extra layer of caching.

  The optional attribute **inBackground** can be set to `true` to keep the
  collection/shards available for write operations by not using an exclusive
  write lock for the duration of the index creation.
  """
  @spec create(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "index"],
      body: body,
      forced: [{"collection", collection}],
      opts: opts
    )
  end

  @doc """
  Create an index. Raises on error.

  See `create/3`.
  """
  @spec create!(Arangox.conn(), binary, term, keyword) :: term
  def create!(conn, collection, body, opts \\ []) do
    case create(conn, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete an index

  Deletes an index with `index-id`.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, index_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "index", {:path, index_id}],
      opts: opts
    )
  end

  @doc """
  Delete an index. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, index_id, opts \\ []) do
    case delete(conn, index_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get an index

  The result is an object describing the index. It has at least the following
  attributes:

  - `id`: the identifier of the index

  - `type`: the index type

  All other attributes are type-dependent. For example, some indexes provide
  `unique` or `sparse` flags, whereas others don't. Some indexes also provide
  a selectivity estimate in the `selectivityEstimate` attribute of the result.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "deduplicate" => boolean,
        "error" => boolean,
        "estimates" => boolean,
        "fields" => [string],
        "id" => string,
        "name" => string,
        "selectivityEstimate" => integer,
        "sparse" => boolean,
        "type" => string,
        "unique" => boolean
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, index_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "index", {:path, index_id}],
      opts: opts
    )
  end

  @doc """
  Get an index. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, index_id, opts \\ []) do
    case get(conn, index_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
