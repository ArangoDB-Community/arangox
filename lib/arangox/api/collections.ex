defmodule Arangox.Api.Collections do
  @moduledoc """
  ArangoDB's Collections operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all collections

  Returns basic information for all collections in the current database,
  optionally excluding system collections.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => [%{
          "globallyUniqueId" => string,
          "id" => string,
          "isSystem" => boolean,
          "name" => string,
          "status" => integer,
          "type" => integer
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection"],
      query: [exclude_system: "excludeSystem"],
      opts: opts
    )
  end

  @doc """
  List all collections. Raises on error.

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

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "checksum" => string,
        "code" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "isSystem" => boolean,
        "name" => string,
        "revision" => string,
        "status" => integer,
        "type" => integer
      }
  """
  @spec checksum(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def checksum(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "checksum"],
      query: [with_revisions: "withRevisions", with_data: "withData"],
      opts: opts
    )
  end

  @doc """
  Get the collection checksum. Raises on error.

  See `checksum/2`.
  """
  @spec checksum!(Arangox.conn(), binary, keyword) :: term
  def checksum!(conn, collection_name, opts \\ []) do
    case checksum(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec compact(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def compact(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "compact"],
      opts: opts
    )
  end

  @doc """
  Compact a collection. Raises on error.

  See `compact/2`.
  """
  @spec compact!(Arangox.conn(), binary, keyword) :: term
  def compact!(conn, collection_name, opts \\ []) do
    case compact(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the document count of a collection

  Get the number of documents in a collection.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "computedValues" => null,
        "count" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "internalValidatorType" => integer,
        "isSmartChild" => boolean,
        "isSystem" => boolean,
        "keyOptions" => %{
          "allowUserKeys" => boolean,
          "lastValue" => integer,
          "type" => string
        },
        "name" => string,
        "objectId" => string,
        "schema" => null,
        "status" => integer,
        "statusString" => string,
        "supportsRBAC" => boolean,
        "syncByRevision" => boolean,
        "type" => integer,
        "usesRevisionsAsDocumentIds" => boolean,
        "waitForSync" => boolean,
        "writeConcern" => integer
      }
  """
  @spec count(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def count(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "count"],
      opts: opts
    )
  end

  @doc """
  Get the document count of a collection. Raises on error.

  See `count/2`.
  """
  @spec count!(Arangox.conn(), binary, keyword) :: term
  def count!(conn, collection_name, opts \\ []) do
    case count(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a collection

  Creates a new collection with a given name. The request must contain an
  object with the following attributes.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "computedValues" => null,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "internalValidatorType" => integer,
        "isSmartChild" => boolean,
        "isSystem" => boolean,
        "keyOptions" => %{
          "allowUserKeys" => boolean,
          "lastValue" => integer,
          "type" => string
        },
        "name" => string,
        "objectId" => string,
        "schema" => null,
        "status" => integer,
        "statusString" => string,
        "supportsRBAC" => boolean,
        "syncByRevision" => boolean,
        "type" => integer,
        "usesRevisionsAsDocumentIds" => boolean,
        "waitForSync" => boolean,
        "writeConcern" => integer
      }
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "collection"],
      body: body,
      query: [
        wait_for_sync_replication: "waitForSyncReplication",
        enforce_replication_factor: "enforceReplicationFactor"
      ],
      opts: opts
    )
  end

  @doc """
  Create a collection. Raises on error.

  See `create/2`.
  """
  @spec create!(Arangox.conn(), term, keyword) :: term
  def create!(conn, body, opts \\ []) do
    case create(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Drop a collection

  Delete the collection identified by `collection-name` and all its documents.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "id" => string
      }
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "collection", collection_name],
      query: [is_system: "isSystem"],
      opts: opts
    )
  end

  @doc """
  Drop a collection. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, collection_name, opts \\ []) do
    case delete(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the collection statistics

  Get the number of documents and additional statistical information
  about the collection.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "computedValues" => null,
        "count" => integer,
        "error" => boolean,
        "figures" => %{
          "cacheInUse" => boolean,
          "cacheSize" => integer,
          "cacheUsage" => integer,
          "documentsSize" => integer,
          "indexes" => %{
            "count" => integer,
            "size" => integer
          }
        },
        "globallyUniqueId" => string,
        "id" => string,
        "internalValidatorType" => integer,
        "isSmartChild" => boolean,
        "isSystem" => boolean,
        "keyOptions" => %{
          "allowUserKeys" => boolean,
          "lastValue" => integer,
          "type" => string
        },
        "name" => string,
        "objectId" => string,
        "schema" => null,
        "status" => integer,
        "statusString" => string,
        "supportsRBAC" => boolean,
        "syncByRevision" => boolean,
        "type" => integer,
        "usesRevisionsAsDocumentIds" => boolean,
        "waitForSync" => boolean,
        "writeConcern" => integer
      }
  """
  @spec figures(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def figures(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "figures"],
      query: [details: "details"],
      opts: opts
    )
  end

  @doc """
  Get the collection statistics. Raises on error.

  See `figures/2`.
  """
  @spec figures!(Arangox.conn(), binary, keyword) :: term
  def figures!(conn, collection_name, opts \\ []) do
    case figures(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the collection information

  Returns the basic information about a specific collection.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "isSystem" => boolean,
        "name" => string,
        "status" => integer,
        "type" => integer
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name],
      opts: opts
    )
  end

  @doc """
  Get the collection information. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, collection_name, opts \\ []) do
    case get(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the available key generators

  Returns the available key generators for collections.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "keyGenerators" => [string]
      }
  """
  @spec key_generators(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def key_generators(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "key-generators"],
      opts: opts
    )
  end

  @doc """
  Get the available key generators. Raises on error.

  See `key_generators/1`.
  """
  @spec key_generators!(Arangox.conn(), keyword) :: term
  def key_generators!(conn, opts \\ []) do
    case key_generators(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Load a collection

  > **WARNING:**
  The load function is deprecated from version 3.8.0 onwards and is a no-op
  from version 3.9.0 onwards. It should no longer be used and is removed
  in ArangoDB v4.0.


  Since ArangoDB version 3.9.0 this API does nothing. Previously, it used to
  load a collection into memory.
  """
  @spec load(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def load(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "load"],
      opts: opts
    )
  end

  @doc """
  Load a collection. Raises on error.

  See `load/2`.
  """
  @spec load!(Arangox.conn(), binary, keyword) :: term
  def load!(conn, collection_name, opts \\ []) do
    case load(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  @spec load_indexes(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def load_indexes(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "loadIndexesIntoMemory"],
      opts: opts
    )
  end

  @doc """
  Load collection indexes into memory. Raises on error.

  See `load_indexes/2`.
  """
  @spec load_indexes!(Arangox.conn(), binary, keyword) :: term
  def load_indexes!(conn, collection_name, opts \\ []) do
    case load_indexes(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the properties of a collection

  Returns all properties of the specified collection.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "computedValues" => null,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "internalValidatorType" => integer,
        "isSmartChild" => boolean,
        "isSystem" => boolean,
        "keyOptions" => %{
          "allowUserKeys" => boolean,
          "lastValue" => integer,
          "type" => string
        },
        "name" => string,
        "objectId" => string,
        "schema" => null,
        "status" => integer,
        "statusString" => string,
        "supportsRBAC" => boolean,
        "syncByRevision" => boolean,
        "type" => integer,
        "usesRevisionsAsDocumentIds" => boolean,
        "waitForSync" => boolean,
        "writeConcern" => integer
      }
  """
  @spec properties(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def properties(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "properties"],
      opts: opts
    )
  end

  @doc """
  Get the properties of a collection. Raises on error.

  See `properties/2`.
  """
  @spec properties!(Arangox.conn(), binary, keyword) :: term
  def properties!(conn, collection_name, opts \\ []) do
    case properties(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Recalculate the document count of a collection

  Recalculates the document count of a collection, if it ever becomes inconsistent.
  """
  @spec recalculate_count(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def recalculate_count(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "recalculateCount"],
      opts: opts
    )
  end

  @doc """
  Recalculate the document count of a collection. Raises on error.

  See `recalculate_count/2`.
  """
  @spec recalculate_count!(Arangox.conn(), binary, keyword) :: term
  def recalculate_count!(conn, collection_name, opts \\ []) do
    case recalculate_count(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Rename a collection

  Renames a collection.

  > **INFO:**
  Renaming collections is not supported in cluster deployments.


  If renaming the collection succeeds, then the collection is also renamed in
  all graph definitions inside the `_graphs` collection in the current database.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "isSystem" => boolean,
        "name" => string,
        "status" => integer,
        "type" => integer
      }
  """
  @spec rename(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def rename(conn, collection_name, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "rename"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Rename a collection. Raises on error.

  See `rename/3`.
  """
  @spec rename!(Arangox.conn(), binary, term, keyword) :: term
  def rename!(conn, collection_name, body, opts \\ []) do
    case rename(conn, collection_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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
  """
  @spec responsible_shard(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def responsible_shard(conn, collection_name, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "responsibleShard"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Get the responsible shard for a document. Raises on error.

  See `responsible_shard/3`.
  """
  @spec responsible_shard!(Arangox.conn(), binary, term, keyword) :: term
  def responsible_shard!(conn, collection_name, body, opts \\ []) do
    case responsible_shard(conn, collection_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the collection revision ID

  The response contains the collection's latest used revision ID.
  The revision ID is a server-generated string that clients can use to
  check whether data in a collection has changed since the last revision check.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cacheEnabled" => boolean,
        "code" => integer,
        "computedValues" => null,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "internalValidatorType" => integer,
        "isSmartChild" => boolean,
        "isSystem" => boolean,
        "keyOptions" => %{
          "allowUserKeys" => boolean,
          "lastValue" => integer,
          "type" => string
        },
        "name" => string,
        "objectId" => string,
        "revision" => string,
        "schema" => null,
        "status" => integer,
        "statusString" => string,
        "supportsRBAC" => boolean,
        "syncByRevision" => boolean,
        "type" => integer,
        "usesRevisionsAsDocumentIds" => boolean,
        "waitForSync" => boolean,
        "writeConcern" => integer
      }
  """
  @spec revision(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def revision(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "revision"],
      opts: opts
    )
  end

  @doc """
  Get the collection revision ID. Raises on error.

  See `revision/2`.
  """
  @spec revision!(Arangox.conn(), binary, keyword) :: term
  def revision!(conn, collection_name, opts \\ []) do
    case revision(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the shard IDs of a collection

  The response contains a list of the collection's shard IDs.

  If the `details` parameter is set to `true`, it returns an object instead
  of a list, with the shard IDs as object attribute keys, and an array with
  the responsible servers for each shard mapped to them as attribute values.
  The first element of each array is the leader shard.

  > **INFO:**
  This method is only available in cluster deployments on Coordinators.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{...}  # 28 keys, among them "cacheEnabled", "code", "computedValues", "error", "globallyUniqueId", "id", "internalValidatorType", "isDisjoint"
  """
  @spec shards(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def shards(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "collection", collection_name, "shards"],
      query: [details: "details"],
      opts: opts
    )
  end

  @doc """
  Get the shard IDs of a collection. Raises on error.

  See `shards/2`.
  """
  @spec shards!(Arangox.conn(), binary, keyword) :: term
  def shards!(conn, collection_name, opts \\ []) do
    case shards(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Truncate a collection

  Removes all documents from the collection, but leaves the indexes intact.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "isSystem" => boolean,
        "name" => string,
        "status" => integer,
        "type" => integer
      }
  """
  @spec truncate(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def truncate(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "truncate"],
      query: [wait_for_sync: "waitForSync", compact: "compact"],
      opts: opts
    )
  end

  @doc """
  Truncate a collection. Raises on error.

  See `truncate/2`.
  """
  @spec truncate!(Arangox.conn(), binary, keyword) :: term
  def truncate!(conn, collection_name, opts \\ []) do
    case truncate(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Unload a collection

  > **WARNING:**
  The unload function is deprecated from version 3.8.0 onwards and is a no-op
  from version 3.9.0 onwards. It should no longer be used and is removed
  in ArangoDB v4.0.


  Since ArangoDB version 3.9.0 this API does nothing. Previously it used to
  unload a collection from memory, while preserving all documents.
  """
  @spec unload(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def unload(conn, collection_name, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "unload"],
      opts: opts
    )
  end

  @doc """
  Unload a collection. Raises on error.

  See `unload/2`.
  """
  @spec unload!(Arangox.conn(), binary, keyword) :: term
  def unload!(conn, collection_name, opts \\ []) do
    case unload(conn, collection_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Change the properties of a collection

  Changes the properties of a collection. Only the provided attributes are
  updated. Collection properties **cannot be changed** once a collection is
  created except for the listed properties, as well as the collection name via
  the rename endpoint (but not in clusters).
  """
  @spec update_properties(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_properties(conn, collection_name, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "collection", collection_name, "properties"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Change the properties of a collection. Raises on error.

  See `update_properties/3`.
  """
  @spec update_properties!(Arangox.conn(), binary, term, keyword) :: term
  def update_properties!(conn, collection_name, body, opts \\ []) do
    case update_properties(conn, collection_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
