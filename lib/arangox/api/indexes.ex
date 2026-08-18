defmodule Arangox.Api.Indexes do
  @moduledoc """
  Provides API endpoints related to indexes
  """

  @default_client Arangox.Api.Client

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

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create a full-text index

  > **WARNING:**
  The fulltext index type is deprecated from version 3.10 onwards.

  Creates a fulltext index for the collection `collection-name`, if
  it does not already exist. The call expects an object containing the index
  details.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_fulltext(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_fulltext(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_fulltext},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create a geo-spatial index

  Creates a geo-spatial index in the collection `collection`, if
  it does not already exist.

  Geo indexes are always sparse, meaning that documents that do not contain
  the index attributes or have non-numeric values in the index attributes
  will not be indexed.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_geo(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_geo(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_geo},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create an inverted index

  Creates an inverted index for the collection `collection-name`, if
  it does not already exist. The call expects an object containing the index
  details.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_inverted(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_inverted(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_inverted},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create a multi-dimensional index

  Creates a multi-dimensional index for the collection `collection-name`, if
  it does not already exist.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_mdi(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_mdi(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_mdi},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create a persistent index

  Creates a persistent index for the collection `collection-name`, if
  it does not already exist.

  In a sparse index all documents will be excluded from the index that do not
  contain at least one of the specified index attributes (i.e. `fields`) or that
  have a value of `null` in any of the specified index attributes. Such documents
  will not be indexed, and not be taken into account for uniqueness checks if
  the `unique` flag is set.

  In a non-sparse index, these documents will be indexed (for non-present
  indexed attributes, a value of `null` will be used) and will be taken into
  account for uniqueness checks if the `unique` flag is set.

  > **INFO:**
  Unique indexes on non-shard keys are not supported in cluster deployments.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_persistent(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_persistent(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_persistent},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  Create a TTL index

  Creates a time-to-live (TTL) index for the collection `collection-name` if it
  does not already exist.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_ttl(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_ttl(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_ttl},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @type create_index_vector_200_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t() | nil,
          fields: [String.t()],
          id: String.t(),
          isNewlyCreated: boolean,
          name: String.t(),
          params: Arangox.Api.Indexes.create_index_vector_200_json_resp_params(),
          sparse: boolean,
          storedValues: [String.t()] | nil,
          trainingState: String.t(),
          type: String.t(),
          unique: boolean
        }

  @type create_index_vector_200_json_resp_params :: %{
          defaultNProbe: integer,
          dimension: integer,
          factory: String.t() | nil,
          metric: String.t(),
          nLists: map,
          numberOfDocsPerCentroid: integer,
          trainingIterations: integer
        }

  @type create_index_vector_201_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t() | nil,
          fields: [String.t()],
          id: String.t(),
          isNewlyCreated: boolean,
          name: String.t(),
          params: Arangox.Api.Indexes.create_index_vector_201_json_resp_params(),
          sparse: boolean,
          storedValues: [String.t()] | nil,
          trainingState: String.t(),
          type: String.t(),
          unique: boolean
        }

  @type create_index_vector_201_json_resp_params :: %{
          defaultNProbe: integer,
          dimension: integer,
          factory: String.t() | nil,
          metric: String.t(),
          nLists: map,
          numberOfDocsPerCentroid: integer,
          trainingIterations: integer
        }

  @type create_index_vector_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_index_vector_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a vector index

  Creates a vector index for the collection `collection-name`, if
  it does not already exist.

  ## Options

    * `collection`: The collection name.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_index_vector(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_index_vector(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Indexes, :create_index_vector},
      url: "/_db/#{database_name}/_api/index",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Indexes, :create_index_vector_200_json_resp}},
        {201, {Arangox.Api.Indexes, :create_index_vector_201_json_resp}},
        {400, {Arangox.Api.Indexes, :create_index_vector_400_json_resp}},
        {404, {Arangox.Api.Indexes, :create_index_vector_404_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Delete an index

  Deletes an index with `index-id`.

  """
  @spec delete_index(database_name :: String.t(), index_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_index(database_name, index_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, index_id: index_id],
      call: {Arangox.Api.Indexes, :delete_index},
      url: "/_db/#{database_name}/_api/index/#{index_id}",
      method: :delete,
      response: [{200, :null}, {404, :null}],
      opts: opts
    })
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

  """
  @spec get_index(database_name :: String.t(), index_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_index(database_name, index_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, index_id: index_id],
      call: {Arangox.Api.Indexes, :get_index},
      url: "/_db/#{database_name}/_api/index/#{index_id}",
      method: :get,
      response: [{200, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  List all indexes of a collection

  Returns an object with an `indexes` attribute containing an array of all
  index descriptions for the given collection. The same information is also
  available in the `identifiers` attribute as an object with the index identifiers
  as object keys.

  ## Options

    * `collection`: The collection name.
      
    * `withStats`: Whether to include figures and estimates in the result.
      
    * `withHidden`: Whether to include hidden indexes in the result. Internal indexes
      (such as `arangosearch`) and ones that are currently built in the
      background are hidden.
      
      From v3.12.10 onward, this option additionally makes vector indexes
      report a `shards` attribute with the per-shard `trainingState`,
      `error`, and `resolvedNLists`. See
      [Check the number of centroids of a trained index](https://docs.arango.ai/arangodb/3.12/indexes-and-search/indexing/working-with-indexes/vector-indexes/#check-the-number-of-centroids-of-a-trained-index).
      

  """
  @spec list_indexes(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_indexes(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:collection, :withHidden, :withStats])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Indexes, :list_indexes},
      url: "/_db/#{database_name}/_api/index",
      method: :get,
      query: query,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:create_index_vector_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      errorMessage: :string,
      fields: [:string],
      id: :string,
      isNewlyCreated: :boolean,
      name: :string,
      params: {Arangox.Api.Indexes, :create_index_vector_200_json_resp_params},
      sparse: :boolean,
      storedValues: [:string],
      trainingState: {:enum, ["unusable", "training", "ingesting", "ready"]},
      type: :string,
      unique: :boolean
    ]
  end

  def __fields__(:create_index_vector_200_json_resp_params) do
    [
      defaultNProbe: :integer,
      dimension: :integer,
      factory: :string,
      metric: {:enum, ["cosine", "innerProduct", "l2"]},
      nLists: :map,
      numberOfDocsPerCentroid: :integer,
      trainingIterations: :integer
    ]
  end

  def __fields__(:create_index_vector_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      errorMessage: :string,
      fields: [:string],
      id: :string,
      isNewlyCreated: :boolean,
      name: :string,
      params: {Arangox.Api.Indexes, :create_index_vector_201_json_resp_params},
      sparse: :boolean,
      storedValues: [:string],
      trainingState: {:enum, ["unusable", "training", "ingesting", "ready"]},
      type: :string,
      unique: :boolean
    ]
  end

  def __fields__(:create_index_vector_201_json_resp_params) do
    [
      defaultNProbe: :integer,
      dimension: :integer,
      factory: :string,
      metric: {:enum, ["cosine", "innerProduct", "l2"]},
      nLists: :map,
      numberOfDocsPerCentroid: :integer,
      trainingIterations: :integer
    ]
  end

  def __fields__(:create_index_vector_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_index_vector_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
