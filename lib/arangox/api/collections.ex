defmodule Arangox.Api.Collections do
  @moduledoc """
  Provides API endpoints related to collections
  """

  @default_client Arangox.Api.Client

  @type compact_collection_200_json_resp :: %{
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          status: integer,
          type: integer
        }

  @type compact_collection_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Compact a collection

  Compacts the data of a collection in order to reclaim disk space.
  The operation will compact the document and index data by rewriting the
  underlying .sst files and only keeping the relevant entries.

  Under normal circumstances, running a compact operation is not necessary, as
  the collection data will eventually get compacted anyway. However, in some
  situations, e.g. after running lots of update/replace or remove operations,
  the disk data for a collection may contain a lot of outdated data for which the
  space shall be reclaimed. In this case the compaction operation can be used.

  """
  @spec compact_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def compact_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :compact_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/compact",
      method: :put,
      response: [
        {200, {Arangox.Api.Collections, :compact_collection_200_json_resp}},
        {401, {Arangox.Api.Collections, :compact_collection_401_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_collection_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.create_collection_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.create_collection_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.create_collection_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type create_collection_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type create_collection_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type create_collection_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type create_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a collection

  Creates a new collection with a given name. The request must contain an
  object with the following attributes.

  ## Options

    * `waitForSyncReplication`: The default is `true`, which means the server only reports success back to the
      client when all replicas have created the collection. Set it to `false` if you want
      faster server responses and don't care about full replication.
      
    * `enforceReplicationFactor`: The default is `true`, which means the server checks if there are enough replicas
      available at creation time and bail out otherwise. Set it to `false` to disable
      this extra check.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_collection(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_collection(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:enforceReplicationFactor, :waitForSyncReplication])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Collections, :create_collection},
      url: "/_db/#{database_name}/_api/collection",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Collections, :create_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :create_collection_400_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_collection_200_json_resp :: %{code: integer, error: boolean, id: String.t()}

  @type delete_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Drop a collection

  Delete the collection identified by `collection-name` and all its documents.

  ## Options

    * `isSystem`: Whether the collection to drop is a system collection. This parameter
      must be set to `true` in order to drop a system collection.
      

  """
  @spec delete_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:isSystem])

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :delete_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Collections, :delete_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :delete_collection_400_json_resp}},
        {404, {Arangox.Api.Collections, :delete_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_collection_200_json_resp :: %{
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          status: integer,
          type: integer
        }

  @type get_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the collection information

  Returns the basic information about a specific collection.

  """
  @spec get_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}",
      method: :get,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_200_json_resp}},
        {404, {Arangox.Api.Collections, :get_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_collection_checksum_200_json_resp :: %{
          checksum: map,
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          revision: map,
          status: integer,
          type: integer
        }

  @doc """
  Get the collection checksum

  Calculates a checksum of the meta-data (keys and optionally revision ids) and
  optionally the document data in the collection.

  The checksum can be used to compare if two collections on different ArangoDB
  instances contain the same contents. The current revision of the collection is
  returned too so one can make sure the checksums are calculated for the same
  state of data.

  By default, the checksum is only calculated on the `_key` system attribute
  of the documents contained in the collection. For edge collections, the system
  attributes `_from` and `_to` are also included in the calculation.

  By setting the optional query parameter `withRevisions` to `true`, then revision
  IDs (`_rev` system attributes) are included in the checksumming.

  By providing the optional query parameter `withData` with a value of `true`,
  the user-defined document attributes are included in the calculation, too.

  > **INFO:**
  Including user-defined attributes will make the checksumming slower.

  ## Options

    * `withRevisions`: Whether to include document revision ids in the checksum calculation.
      
    * `withData`: Whether to include document body data in the checksum calculation.
      

  """
  @spec get_collection_checksum(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_checksum(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:withData, :withRevisions])

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_checksum},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/checksum",
      method: :get,
      query: query,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_checksum_200_json_resp}},
        {400, :null},
        {404, :null}
      ],
      opts: opts
    })
  end

  @type get_collection_count_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.get_collection_count_200_json_resp_computed_values()
          ],
          count: integer,
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.get_collection_count_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.get_collection_count_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type get_collection_count_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type get_collection_count_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type get_collection_count_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @doc """
  Get the document count of a collection

  Get the number of documents in a collection.

  """
  @spec get_collection_count(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_count(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_count},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/count",
      method: :get,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_count_200_json_resp}},
        {400, :null},
        {404, :null},
        {410, :null}
      ],
      opts: opts
    })
  end

  @type get_collection_figures_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.get_collection_figures_200_json_resp_computed_values()
          ],
          count: integer,
          distributeShardsLike: String.t() | nil,
          error: boolean,
          figures: Arangox.Api.Collections.get_collection_figures_200_json_resp_figures(),
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.get_collection_figures_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.get_collection_figures_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type get_collection_figures_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type get_collection_figures_200_json_resp_figures :: %{
          cacheInUse: boolean | nil,
          cacheLifeTimeHitRate: number | nil,
          cacheSize: integer | nil,
          cacheUsage: integer | nil,
          cacheWindowedHitRate: number | nil,
          documentsSize: integer | nil,
          engine:
            Arangox.Api.Collections.get_collection_figures_200_json_resp_figures_engine() | nil,
          indexes: Arangox.Api.Collections.get_collection_figures_200_json_resp_figures_indexes()
        }

  @type get_collection_figures_200_json_resp_figures_engine :: %{
          documents: integer | nil,
          indexes:
            [
              Arangox.Api.Collections.get_collection_figures_200_json_resp_figures_engine_indexes()
            ]
            | nil
        }

  @type get_collection_figures_200_json_resp_figures_engine_indexes :: %{
          count: integer | nil,
          id: integer | nil,
          type: String.t() | nil
        }

  @type get_collection_figures_200_json_resp_figures_indexes :: %{count: integer, size: integer}

  @type get_collection_figures_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type get_collection_figures_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type get_collection_figures_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_collection_figures_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the collection statistics

  Get the number of documents and additional statistical information
  about the collection.

  ## Options

    * `details`: Setting `details` to `true` will return extended storage engine-specific
      details to the figures. The details are intended for debugging ArangoDB itself
      and their format is subject to change. By default, `details` is set to `false`,
      so no details are returned and the behavior is identical to previous versions
      of ArangoDB.
      Please note that requesting `details` may cause additional load and thus have
      an impact on performance.
      

  """
  @spec get_collection_figures(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_figures(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:details])

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_figures},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/figures",
      method: :get,
      query: query,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_figures_200_json_resp}},
        {400, {Arangox.Api.Collections, :get_collection_figures_400_json_resp}},
        {404, {Arangox.Api.Collections, :get_collection_figures_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_collection_properties_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.get_collection_properties_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions:
            Arangox.Api.Collections.get_collection_properties_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.get_collection_properties_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type get_collection_properties_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type get_collection_properties_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type get_collection_properties_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type get_collection_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_collection_properties_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the properties of a collection

  Returns all properties of the specified collection.

  """
  @spec get_collection_properties(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_properties(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_properties},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/properties",
      method: :get,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_properties_200_json_resp}},
        {400, {Arangox.Api.Collections, :get_collection_properties_400_json_resp}},
        {404, {Arangox.Api.Collections, :get_collection_properties_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_collection_revision_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.get_collection_revision_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.get_collection_revision_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          revision: String.t(),
          schema: Arangox.Api.Collections.get_collection_revision_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type get_collection_revision_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type get_collection_revision_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type get_collection_revision_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type get_collection_revision_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_collection_revision_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the collection revision ID

  The response contains the collection's latest used revision ID.
  The revision ID is a server-generated string that clients can use to
  check whether data in a collection has changed since the last revision check.

  """
  @spec get_collection_revision(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_revision(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_revision},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/revision",
      method: :get,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_revision_200_json_resp}},
        {400, {Arangox.Api.Collections, :get_collection_revision_400_json_resp}},
        {404, {Arangox.Api.Collections, :get_collection_revision_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_collection_shards_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.get_collection_shards_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.get_collection_shards_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.get_collection_shards_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          shards: map,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type get_collection_shards_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type get_collection_shards_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type get_collection_shards_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type get_collection_shards_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_collection_shards_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_collection_shards_501_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the shard IDs of a collection

  The response contains a list of the collection's shard IDs.

  If the `details` parameter is set to `true`, it returns an object instead
  of a list, with the shard IDs as object attribute keys, and an array with
  the responsible servers for each shard mapped to them as attribute values.
  The first element of each array is the leader shard.

  > **INFO:**
  This method is only available in cluster deployments on Coordinators.

  ## Options

    * `details`: If set to true, the return value also contains the responsible servers for the collections' shards.
      

  """
  @spec get_collection_shards(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_collection_shards(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:details])

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :get_collection_shards},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/shards",
      method: :get,
      query: query,
      response: [
        {200, {Arangox.Api.Collections, :get_collection_shards_200_json_resp}},
        {400, {Arangox.Api.Collections, :get_collection_shards_400_json_resp}},
        {404, {Arangox.Api.Collections, :get_collection_shards_404_json_resp}},
        {501, {Arangox.Api.Collections, :get_collection_shards_501_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_key_generators_200_json_resp :: %{keyGenerators: [String.t()]}

  @doc """
  Get the available key generators

  Returns the available key generators for collections.

  """
  @spec get_key_generators(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_key_generators(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Collections, :get_key_generators},
      url: "/_db/#{database_name}/_api/key-generators",
      method: :get,
      response: [{200, {Arangox.Api.Collections, :get_key_generators_200_json_resp}}],
      opts: opts
    })
  end

  @type get_responsible_shard_200_json_resp :: %{
          code: integer,
          error: boolean,
          shardId: String.t()
        }

  @type get_responsible_shard_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_responsible_shard_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_responsible_shard_501_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the responsible shard for a document

  Returns the ID of the shard that is responsible for the given document
  (if the document exists) or that would be responsible if such document
  existed.

  The request must body must contain a JSON document with at least the
  collection's shard key attributes set to some values.

  The response is a JSON object with a `shardId` attribute, which will
  contain the ID of the responsible shard.

  > **INFO:**
  This method is only available in cluster deployments on Coordinators.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec get_responsible_shard(
          database_name :: String.t(),
          collection_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_responsible_shard(database_name, collection_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name, body: body],
      call: {Arangox.Api.Collections, :get_responsible_shard},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/responsibleShard",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Collections, :get_responsible_shard_200_json_resp}},
        {400, {Arangox.Api.Collections, :get_responsible_shard_400_json_resp}},
        {404, {Arangox.Api.Collections, :get_responsible_shard_404_json_resp}},
        {501, {Arangox.Api.Collections, :get_responsible_shard_501_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_collections_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: [Arangox.Api.Collections.list_collections_200_json_resp_result()]
        }

  @type list_collections_200_json_resp_result :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          status: integer,
          type: integer
        }

  @doc """
  List all collections

  Returns basic information for all collections in the current database,
  optionally excluding system collections.

  ## Options

    * `excludeSystem`: Whether system collections should be excluded from the result.
      

  """
  @spec list_collections(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_collections(database_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:excludeSystem])

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Collections, :list_collections},
      url: "/_db/#{database_name}/_api/collection",
      method: :get,
      query: query,
      response: [{200, {Arangox.Api.Collections, :list_collections_200_json_resp}}],
      opts: opts
    })
  end

  @type load_collection_200_json_resp :: %{
          code: integer,
          count: integer | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          status: integer,
          type: integer
        }

  @type load_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type load_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Load a collection

  > **WARNING:**
  The load function is deprecated from version 3.8.0 onwards and is a no-op
  from version 3.9.0 onwards. It should no longer be used and is removed
  in ArangoDB v4.0.

  Since ArangoDB version 3.9.0 this API does nothing. Previously, it used to
  load a collection into memory.

  """
  @spec load_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def load_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :load_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/load",
      method: :put,
      response: [
        {200, {Arangox.Api.Collections, :load_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :load_collection_400_json_resp}},
        {404, {Arangox.Api.Collections, :load_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type load_collection_indexes_200_json_resp :: %{code: integer, error: boolean, result: boolean}

  @type load_collection_indexes_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type load_collection_indexes_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Load collection indexes into memory

  You can call this endpoint to try to cache this collection's index entries in
  the main memory. Index lookups served from the memory cache can be much faster
  than lookups not stored in the cache, resulting in a performance boost.

  The endpoint iterates over suitable indexes of the collection and stores the
  indexed values (not the entire document data) in memory. This is implemented for
  edge indexes only.

  The endpoint returns as soon as the index warmup has been scheduled. The index
  warmup may still be ongoing in the background, even after the return value has
  already been sent. As all suitable indexes are scanned, it may cause significant
  I/O activity and background load.

  This feature honors memory limits. If the indexes you want to load are smaller
  than your memory limit, this feature guarantees that most index values are
  cached. If the index is greater than your memory limit, this feature fills
  up values up to this limit. You cannot control which indexes of the collection
  should have priority over others.

  It is guaranteed that the in-memory cache data is consistent with the stored
  index data at all times.

  """
  @spec load_collection_indexes(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def load_collection_indexes(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :load_collection_indexes},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/loadIndexesIntoMemory",
      method: :put,
      response: [
        {200, {Arangox.Api.Collections, :load_collection_indexes_200_json_resp}},
        {400, {Arangox.Api.Collections, :load_collection_indexes_400_json_resp}},
        {404, {Arangox.Api.Collections, :load_collection_indexes_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type recalculate_collection_count_200_json_resp :: %{
          code: integer,
          count: integer | nil,
          error: boolean,
          result: boolean
        }

  @type recalculate_collection_count_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type recalculate_collection_count_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Recalculate the document count of a collection

  Recalculates the document count of a collection, if it ever becomes inconsistent.

  """
  @spec recalculate_collection_count(
          database_name :: String.t(),
          collection_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def recalculate_collection_count(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :recalculate_collection_count},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/recalculateCount",
      method: :put,
      response: [
        {200, {Arangox.Api.Collections, :recalculate_collection_count_200_json_resp}},
        {400, {Arangox.Api.Collections, :recalculate_collection_count_400_json_resp}},
        {404, {Arangox.Api.Collections, :recalculate_collection_count_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type rename_collection_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.rename_collection_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions: Arangox.Api.Collections.rename_collection_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.rename_collection_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type rename_collection_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type rename_collection_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type rename_collection_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type rename_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type rename_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Rename a collection

  Renames a collection.

  > **INFO:**
  Renaming collections is not supported in cluster deployments.

  If renaming the collection succeeds, then the collection is also renamed in
  all graph definitions inside the `_graphs` collection in the current database.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec rename_collection(
          database_name :: String.t(),
          collection_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def rename_collection(database_name, collection_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name, body: body],
      call: {Arangox.Api.Collections, :rename_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/rename",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Collections, :rename_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :rename_collection_400_json_resp}},
        {404, {Arangox.Api.Collections, :rename_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type truncate_collection_200_json_resp :: %{code: integer, error: boolean, id: String.t()}

  @type truncate_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type truncate_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type truncate_collection_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Truncate a collection

  Removes all documents from the collection, but leaves the indexes intact.

  ## Options

    * `waitForSync`: If set to `true`, the data is synchronized to disk before returning from the
      truncate operation.
      
    * `compact`: If set to `true`, the storage engine is told to start a compaction
      in order to free up disk space. This can be resource intensive. If the only
      intention is to start over with an empty collection, specify `false`.
      

  """
  @spec truncate_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def truncate_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:compact, :waitForSync])

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :truncate_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/truncate",
      method: :put,
      query: query,
      response: [
        {200, {Arangox.Api.Collections, :truncate_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :truncate_collection_400_json_resp}},
        {404, {Arangox.Api.Collections, :truncate_collection_404_json_resp}},
        {410, {Arangox.Api.Collections, :truncate_collection_410_json_resp}}
      ],
      opts: opts
    })
  end

  @type unload_collection_200_json_resp :: %{
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isSystem: boolean,
          name: String.t(),
          status: integer,
          type: integer
        }

  @type unload_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type unload_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Unload a collection

  > **WARNING:**
  The unload function is deprecated from version 3.8.0 onwards and is a no-op
  from version 3.9.0 onwards. It should no longer be used and is removed
  in ArangoDB v4.0.

  Since ArangoDB version 3.9.0 this API does nothing. Previously it used to
  unload a collection from memory, while preserving all documents.

  """
  @spec unload_collection(database_name :: String.t(), collection_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def unload_collection(database_name, collection_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name],
      call: {Arangox.Api.Collections, :unload_collection},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/unload",
      method: :put,
      response: [
        {200, {Arangox.Api.Collections, :unload_collection_200_json_resp}},
        {400, {Arangox.Api.Collections, :unload_collection_400_json_resp}},
        {404, {Arangox.Api.Collections, :unload_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type update_collection_properties_200_json_resp :: %{
          cacheEnabled: boolean,
          code: integer,
          computedValues: [
            Arangox.Api.Collections.update_collection_properties_200_json_resp_computed_values()
          ],
          distributeShardsLike: String.t() | nil,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          isDisjoint: boolean | nil,
          isSmart: boolean | nil,
          isSystem: boolean,
          keyOptions:
            Arangox.Api.Collections.update_collection_properties_200_json_resp_key_options(),
          name: String.t(),
          numberOfShards: integer | nil,
          replicationFactor: integer | nil,
          schema: Arangox.Api.Collections.update_collection_properties_200_json_resp_schema(),
          shardKeys: [String.t()] | nil,
          shardingStrategy: String.t() | nil,
          smartGraphAttribute: String.t() | nil,
          smartJoinAttribute: String.t() | nil,
          status: integer,
          statusString: String.t(),
          syncByRevision: boolean,
          type: integer,
          waitForSync: boolean,
          writeConcern: integer | nil
        }

  @type update_collection_properties_200_json_resp_computed_values :: %{
          computeOn: [String.t()] | nil,
          expression: String.t(),
          failOnWarning: boolean | nil,
          keepNull: boolean | nil,
          name: String.t(),
          overwrite: boolean
        }

  @type update_collection_properties_200_json_resp_key_options :: %{
          allowUserKeys: boolean,
          increment: integer | nil,
          lastValue: integer | nil,
          offset: integer | nil,
          type: String.t()
        }

  @type update_collection_properties_200_json_resp_schema :: %{
          level: String.t(),
          message: String.t(),
          rule: map,
          type: String.t()
        }

  @type update_collection_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_collection_properties_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Change the properties of a collection

  Changes the properties of a collection. Only the provided attributes are
  updated. Collection properties **cannot be changed** once a collection is
  created except for the listed properties, as well as the collection name via
  the rename endpoint (but not in clusters).

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_collection_properties(
          database_name :: String.t(),
          collection_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_collection_properties(database_name, collection_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, collection_name: collection_name, body: body],
      call: {Arangox.Api.Collections, :update_collection_properties},
      url: "/_db/#{database_name}/_api/collection/#{collection_name}/properties",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Collections, :update_collection_properties_200_json_resp}},
        {400, {Arangox.Api.Collections, :update_collection_properties_400_json_resp}},
        {404, {Arangox.Api.Collections, :update_collection_properties_404_json_resp}}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:compact_collection_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:compact_collection_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_collection_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :create_collection_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :create_collection_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :create_collection_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:create_collection_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:create_collection_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:create_collection_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:create_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_collection_200_json_resp) do
    [code: :integer, error: :boolean, id: :string]
  end

  def __fields__(:delete_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:get_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_checksum_200_json_resp) do
    [
      checksum: :map,
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      revision: :map,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:get_collection_count_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :get_collection_count_200_json_resp_computed_values}
      ],
      count: :integer,
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :get_collection_count_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :get_collection_count_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_collection_count_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:get_collection_count_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:get_collection_count_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :get_collection_figures_200_json_resp_computed_values}
      ],
      count: :integer,
      distributeShardsLike: :string,
      error: :boolean,
      figures: {Arangox.Api.Collections, :get_collection_figures_200_json_resp_figures},
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :get_collection_figures_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :get_collection_figures_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp_figures) do
    [
      cacheInUse: :boolean,
      cacheLifeTimeHitRate: :number,
      cacheSize: :integer,
      cacheUsage: :integer,
      cacheWindowedHitRate: :number,
      documentsSize: :integer,
      engine: {Arangox.Api.Collections, :get_collection_figures_200_json_resp_figures_engine},
      indexes: {Arangox.Api.Collections, :get_collection_figures_200_json_resp_figures_indexes}
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp_figures_engine) do
    [
      documents: :integer,
      indexes: [
        {Arangox.Api.Collections, :get_collection_figures_200_json_resp_figures_engine_indexes}
      ]
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp_figures_engine_indexes) do
    [count: :integer, id: :integer, type: :string]
  end

  def __fields__(:get_collection_figures_200_json_resp_figures_indexes) do
    [count: :integer, size: :integer]
  end

  def __fields__(:get_collection_figures_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:get_collection_figures_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:get_collection_figures_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_figures_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_properties_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :get_collection_properties_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :get_collection_properties_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :get_collection_properties_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_collection_properties_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:get_collection_properties_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:get_collection_properties_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:get_collection_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_properties_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_revision_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :get_collection_revision_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :get_collection_revision_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      revision: :string,
      schema: {Arangox.Api.Collections, :get_collection_revision_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_collection_revision_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:get_collection_revision_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:get_collection_revision_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:get_collection_revision_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_revision_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_shards_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :get_collection_shards_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :get_collection_shards_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :get_collection_shards_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      shards: :map,
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_collection_shards_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:get_collection_shards_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:get_collection_shards_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:get_collection_shards_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_shards_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_collection_shards_501_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_key_generators_200_json_resp) do
    [keyGenerators: [enum: ["traditional", "autoincrement", "uuid", "padded"]]]
  end

  def __fields__(:get_responsible_shard_200_json_resp) do
    [code: :integer, error: :boolean, shardId: :string]
  end

  def __fields__(:get_responsible_shard_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_responsible_shard_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_responsible_shard_501_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_collections_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: [{Arangox.Api.Collections, :list_collections_200_json_resp_result}]
    ]
  end

  def __fields__(:list_collections_200_json_resp_result) do
    [
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:load_collection_200_json_resp) do
    [
      code: :integer,
      count: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:load_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:load_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:load_collection_indexes_200_json_resp) do
    [code: :integer, error: :boolean, result: :boolean]
  end

  def __fields__(:load_collection_indexes_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:load_collection_indexes_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:recalculate_collection_count_200_json_resp) do
    [code: :integer, count: :integer, error: :boolean, result: :boolean]
  end

  def __fields__(:recalculate_collection_count_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:recalculate_collection_count_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:rename_collection_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :rename_collection_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions: {Arangox.Api.Collections, :rename_collection_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :rename_collection_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:rename_collection_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:rename_collection_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:rename_collection_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:rename_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:rename_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:truncate_collection_200_json_resp) do
    [code: :integer, error: :boolean, id: :string]
  end

  def __fields__(:truncate_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:truncate_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:truncate_collection_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:unload_collection_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isSystem: :boolean,
      name: :string,
      status: :integer,
      type: :integer
    ]
  end

  def __fields__(:unload_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:unload_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_collection_properties_200_json_resp) do
    [
      cacheEnabled: :boolean,
      code: :integer,
      computedValues: [
        {Arangox.Api.Collections, :update_collection_properties_200_json_resp_computed_values}
      ],
      distributeShardsLike: :string,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      isDisjoint: :boolean,
      isSmart: :boolean,
      isSystem: :boolean,
      keyOptions:
        {Arangox.Api.Collections, :update_collection_properties_200_json_resp_key_options},
      name: :string,
      numberOfShards: :integer,
      replicationFactor: :integer,
      schema: {Arangox.Api.Collections, :update_collection_properties_200_json_resp_schema},
      shardKeys: [:string],
      shardingStrategy:
        {:enum,
         [
           "community-compat",
           "enterprise-compat",
           "enterprise-smart-edge-compat",
           "hash",
           "enterprise-hash-smart-edge",
           "enterprise-hex-smart-vertex"
         ]},
      smartGraphAttribute: :string,
      smartJoinAttribute: :string,
      status: :integer,
      statusString: {:enum, ["loaded", "deleted"]},
      syncByRevision: :boolean,
      type: :integer,
      waitForSync: :boolean,
      writeConcern: :integer
    ]
  end

  def __fields__(:update_collection_properties_200_json_resp_computed_values) do
    [
      computeOn: [enum: ["insert", "update", "replace"]],
      expression: :string,
      failOnWarning: :boolean,
      keepNull: :boolean,
      name: :string,
      overwrite: :boolean
    ]
  end

  def __fields__(:update_collection_properties_200_json_resp_key_options) do
    [
      allowUserKeys: :boolean,
      increment: :integer,
      lastValue: :integer,
      offset: :integer,
      type: {:enum, ["traditional", "autoincrement", "uuid", "padded"]}
    ]
  end

  def __fields__(:update_collection_properties_200_json_resp_schema) do
    [
      level: {:enum, ["none", "new", "moderate", "strict"]},
      message: :string,
      rule: :map,
      type: {:const, "json"}
    ]
  end

  def __fields__(:update_collection_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_collection_properties_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
