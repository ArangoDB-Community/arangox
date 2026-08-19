defmodule Arangox.Api.Replication do
  @moduledoc """
  ArangoDB's Replication operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  Get documents by revision

  > **WARNING:**
  This revision-based replication endpoint will only work with collections
  created in ArangoDB v3.8.0 or later.


  Returns documents by revision for replication.

  The body of the request should be JSON/VelocyPack and should consist of an
  array of string-encoded revision IDs:

  ```
  [
  <String, revision>,
  <String, revision>,
  ...
  <String, revision>
  ]
  ```

  In particular, the revisions should be sorted in ascending order of their
  decoded values.

  The result will be a JSON/VelocyPack array of document objects. If there is no
  document corresponding to a particular requested revision, an empty object will
  be returned in its place.

  The response may be truncated if it would be very long. In this case, the
  response array length will be less than the request array length, and
  subsequent requests can be made for the omitted documents.

  Each `<String, revision>` value type is a 64-bit value encoded as a string of
  11 characters, using the same encoding as our document `_rev` values. The
  reason for this is that 64-bit values cannot necessarily be represented in full
  in JavaScript, as it handles all numbers as floating point, and can only
  represent up to `2^53-1` faithfully.
  """
  @spec all_revision_documents(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def all_revision_documents(conn, collection, batch_id, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "replication", "revisions", "documents"],
      forced: [{"collection", collection}, {"batchId", batch_id}],
      opts: opts
    )
  end

  @doc """
  Get documents by revision. Raises on error.

  See `all_revision_documents/1`.
  """
  @spec all_revision_documents!(Arangox.conn(), binary, binary, keyword) :: term
  def all_revision_documents!(conn, collection, batch_id, opts \\ []) do
    case all_revision_documents(conn, collection, batch_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List document revision IDs within requested ranges

  > **WARNING:**
  This revision-based replication endpoint will only work with the RocksDB
  engine, and with collections created in ArangoDB v3.8.0 or later.


  Returns the revision IDs of documents within the requested ranges.

  The body of the request should be JSON/VelocyPack and should consist of an
  array of pairs of string-encoded revision IDs:

  ```
  [
  [<String, revision>, <String, revision>],
  [<String, revision>, <String, revision>],
  ...
  [<String, revision>, <String, revision>]
  ]
  ```

  In particular, the pairs should be non-overlapping, and sorted in ascending
  order of their decoded values.

  The result will be JSON/VelocyPack in the following format:
  ```
  {
  ranges: [
    [<String, revision>, <String, revision>, ... <String, revision>],
    [<String, revision>, <String, revision>, ... <String, revision>],
    ...,
    [<String, revision>, <String, revision>, ... <String, revision>]
  ]
  resume: <String, revision>
  }
  ```

  The `resume` field is optional. If specified, then the response is to be
  considered partial, only valid through the revision specified. A subsequent
  request should be made with the same request body, but specifying the `resume`
  URL parameter with the value specified. The subsequent response will pick up
  from the appropriate request pair, and omit any complete ranges or revisions
  which are less than the requested resume revision. As an example (ignoring the
  string-encoding for a moment), if ranges `[1, 3], [5, 9], [12, 15]` are
  requested, then a first response may return `[], [5, 6]` with a resume point of
  `7` and a subsequent response might be `[8], [12, 13]`.

  If a requested range contains no revisions, then an empty array is returned.
  Empty ranges will not be omitted.

  Each `<String, revision>` value type is a 64-bit value encoded as a string of
  11 characters, using the same encoding as our document `_rev` values. The
  reason for this is that 64-bit values cannot necessarily be represented in full
  in JavaScript, as it handles all numbers as floating point, and can only
  represent up to `2^53-1` faithfully.
  """
  @spec all_revision_ranges(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def all_revision_ranges(conn, collection, batch_id, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "replication", "revisions", "ranges"],
      forced: [{"collection", collection}, {"batchId", batch_id}],
      query: [resume: "resume"],
      opts: opts
    )
  end

  @doc """
  List document revision IDs within requested ranges. Raises on error.

  See `all_revision_ranges/1`.
  """
  @spec all_revision_ranges!(Arangox.conn(), binary, binary, keyword) :: term
  def all_revision_ranges!(conn, collection, batch_id, opts \\ []) do
    case all_revision_ranges(conn, collection, batch_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the cluster collections and indexes

  Returns the array of collections and indexes available on the cluster.

  The response will be an array of JSON objects, one for each collection.
  Each collection contains exactly two keys, `parameters` and `indexes`.
  This information comes from `Plan/Collections/{DB-Name}/*` in the Agency,
  just that the `indexes` attribute there is relocated to adjust it to
  the data format of arangodump.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "collections" => [%{
          "allInSync" => boolean,
          "indexes" => [],
          "isReady" => boolean,
          "parameters" => %{...}  # 28 keys, among them "cacheEnabled", "computedValues", "deleted", "distributeShardsLike", "globallyUniqueId", "id", "internalValidatorType", "isDisjoint",
          "planVersion" => integer
        }],
        "properties" => %{
          "id" => string,
          "isSystem" => boolean,
          "name" => string,
          "path" => string,
          "replicationFactor" => integer,
          "replicationVersion" => string,
          "sharding" => string,
          "writeConcern" => integer
        },
        "state" => string,
        "tick" => string,
        "views" => []
      }
  """
  @spec cluster_inventory(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def cluster_inventory(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "replication", "clusterInventory"],
      query: [include_system: "includeSystem"],
      opts: opts
    )
  end

  @doc """
  Get the cluster collections and indexes. Raises on error.

  See `cluster_inventory/1`.
  """
  @spec cluster_inventory!(Arangox.conn(), keyword) :: term
  def cluster_inventory!(conn, opts \\ []) do
    case cluster_inventory(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a new dump batch

  > **INFO:**
  This is an internally used endpoint.


  Creates a new dump batch and returns the batch's id.

  The response is a JSON object with the following attributes:

  - `id`: the id of the batch
  - `lastTick`: snapshot tick value using when creating the batch
  - `state`: additional leader state information (only present if the
  `state` URL parameter was set to `true` in the request)

  > **INFO:**
  On a Coordinator, this request must have a `DBserver`
  query parameter which must be an ID of a DB-Server.
  The very same request is forwarded synchronously to that DB-Server.
  It is an error if this attribute is not bound in the Coordinator case.
  """
  @spec create_batch(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create_batch(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "replication", "batch"],
      body: body,
      query: [state: "state"],
      opts: opts
    )
  end

  @doc """
  Create a new dump batch. Raises on error.

  See `create_batch/2`.
  """
  @spec create_batch!(Arangox.conn(), term, keyword) :: term
  def create_batch!(conn, body, opts \\ []) do
    case create_batch(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete an existing dump batch

  > **INFO:**
  This is an internally used endpoint.


  Deletes the existing dump batch, allowing compaction and cleanup to resume.

  > **INFO:**
  On a Coordinator, this request must have a `DBserver`
  query parameter which must be an ID of a DB-Server.
  The very same request is forwarded synchronously to that DB-Server.
  It is an error if this attribute is not bound in the Coordinator case.
  """
  @spec delete_batch(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete_batch(conn, id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "replication", "batch", id],
      opts: opts
    )
  end

  @doc """
  Delete an existing dump batch. Raises on error.

  See `delete_batch/2`.
  """
  @spec delete_batch!(Arangox.conn(), binary, keyword) :: term
  def delete_batch!(conn, id, opts \\ []) do
    case delete_batch(conn, id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a replication dump

  Returns the data from a collection for the requested range.

  The `chunkSize` query parameter can be used to control the size of the result.
  It must be specified in bytes. The `chunkSize` value will only be honored
  approximately. Otherwise a too low `chunkSize` value could cause the server
  to not be able to put just one entry into the result and return it.
  Therefore, the `chunkSize` value will only be consulted after an entry has
  been written into the result. If the result size is then greater than
  `chunkSize`, the server will respond with as many entries as there are
  in the response already. If the result size is still less than `chunkSize`,
  the server will try to return more data if there's more data left to return.

  If `chunkSize` is not specified, some server-side default value will be used.

  The `Content-Type` of the result is `application/x-arango-dump`. This is an
  easy-to-process format, with all entries going onto separate lines in the
  response body.

  Each line itself is a JSON object, with at least the following attributes:

  - `tick`: the operation's tick attribute

  - `key`: the key of the document/edge or the key used in the deletion operation

  - `rev`: the revision id of the document/edge or the deletion operation

  - `data`: the actual document/edge data for types 2300 and 2301. The full
  document/edge data will be returned even for updates.

  - `type`: the type of entry. Possible values for `type` are:

  - 2300: document insertion/update

  - 2301: edge insertion/update

  - 2302: document/edge deletion

  > **INFO:**
  There will be no distinction between inserts and updates when calling this method.
  """
  @spec dump(Arangox.conn(), binary, binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def dump(conn, collection, batch_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "replication", "dump"],
      forced: [{"collection", collection}, {"batchId", batch_id}],
      query: [chunk_size: "chunkSize"],
      opts: opts
    )
  end

  @doc """
  Get a replication dump. Raises on error.

  See `dump/1`.
  """
  @spec dump!(Arangox.conn(), binary, binary, keyword) :: term
  def dump!(conn, collection, batch_id, opts \\ []) do
    case dump(conn, collection, batch_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Extend the TTL of a dump batch

  > **INFO:**
  This is an internally used endpoint.


  Extends the time-to-live (TTL) of an existing dump batch, using the batch's ID and
  the provided TTL value.

  If the batch's TTL can be extended successfully, the response is empty.

  > **INFO:**
  On a Coordinator, this request must have a `DBserver`
  query parameter which must be an ID of a DB-Server.
  The very same request is forwarded synchronously to that DB-Server.
  It is an error if this attribute is not bound in the Coordinator case.
  """
  @spec extend_batch(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def extend_batch(conn, id, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "replication", "batch", id],
      body: body,
      opts: opts
    )
  end

  @doc """
  Extend the TTL of a dump batch. Raises on error.

  See `extend_batch/3`.
  """
  @spec extend_batch!(Arangox.conn(), binary, term, keyword) :: term
  def extend_batch!(conn, id, body, opts \\ []) do
    case extend_batch(conn, id, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a replication inventory

  Returns the array of collections and their indexes, and the array of Views available. These
  arrays can be used by replication clients to initiate an initial synchronization with the
  server.
  The response will contain all collections, their indexes and views in the requested database
  if `global` is not set, and all collections, indexes and views in all databases if `global`
  is set.
  In case `global` is not set, it is possible to restrict the response to a single collection
  by setting the `collection` parameter. In this case the response will contain only information
  about the requested collection in the `collections` array, and no information about views
  (i.e. the `views` response attribute will be an empty array).

  The response will contain a JSON object with the `collections`, `views`, `state` and
  `tick` attributes.

  `collections` is an array of collections with the following sub-attributes:

  - `parameters`: the collection properties

  - `indexes`: an array of the indexes of the collection. Primary indexes and edge indexes
   are not included in this array.

  The `state` attribute contains the current state of the replication logger. It
  contains the following sub-attributes:

  - `running`: whether or not the replication logger is currently active. Note:
  since ArangoDB 2.2, the value will always be `true`

  - `lastLogTick`: the value of the last tick the replication logger has written

  - `time`: the current time on the server

  `views` is an array of available views.

  Replication clients should note the `lastLogTick` value returned. They can then
  fetch collections' data using the dump method up to the value of lastLogTick, and
  query the continuous replication log for log events after this tick value.

  To create a full copy of the collections on the server, a replication client
  can execute these steps:

  - call the `/inventory` API method. This returns the `lastLogTick` value and the
  array of collections and indexes from the server.

  - for each collection returned by `/inventory`, create the collection locally and
  call `/dump` to stream the collection data to the client, up to the value of
  `lastLogTick`.
  After that, the client can create the indexes on the collections as they were
  reported by `/inventory`.

  If the clients wants to continuously stream replication log events from the logger
  server, the following additional steps need to be carried out:

  - the client should call `/_api/wal/tail` initially to fetch the first batch of
  replication events that were logged after the client's call to `/inventory`.

  The call to `/_api/wal/tail` should use a `from` parameter with the value of the
  `lastLogTick` as reported by `/inventory`. The call to `/_api/wal/tail` will
  return the `x-arango-replication-lastincluded` header which will contain the
  last tick value included in the response.

  - the client can then continuously call `/_api/wal/tail` to incrementally fetch new
  replication events that occurred after the last transfer.

  Calls should use a `from` parameter with the value of the `x-arango-replication-lastincluded`
  header of the previous response. If there are no more replication events, the
  response will be empty and clients can go to sleep for a while and try again
  later.

  > **INFO:**
  On a Coordinator, this request must have a `DBserver`
  query parameter which must be an ID of a DB-Server.
  The very same request is forwarded synchronously to that DB-Server.
  It is an error if this attribute is not bound in the Coordinator case.


  > **INFO:**
  Using the `global` parameter the top-level object contains a key `databases`
  under which each key represents a database name, and the value conforms to the above description.
  """
  @spec inventory(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def inventory(conn, batch_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "replication", "inventory"],
      forced: [{"batchId", batch_id}],
      query: [include_system: "includeSystem", global: "global", collection: "collection"],
      opts: opts
    )
  end

  @doc """
  Get a replication inventory. Raises on error.

  See `inventory/1`.
  """
  @spec inventory!(Arangox.conn(), binary, keyword) :: term
  def inventory!(conn, batch_id, opts \\ []) do
    case inventory(conn, batch_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the replication logger state

  Returns the current state of the server's replication logger. The state will
  include information about whether the logger is running and about the last
  logged tick value. This tick value is important for incremental fetching of
  data.

  The body of the response contains a JSON object with the following
  attributes:

  - `state`: the current logger state as a JSON object with the following
  sub-attributes:

  - `running`: whether or not the logger is running

  - `lastLogTick`: the tick value of the latest tick the logger has logged.
    This value can be used for incremental fetching of log data.

  - `totalEvents`: total number of events logged since the server was started.
    The value is not reset between multiple stops and re-starts of the logger.

  - `time`: the current date and time on the logger server

  - `server`: a JSON object with the following sub-attributes:

  - `version`: the logger server's version

  - `serverId`: the logger server's id

  - `clients`: returns the last fetch status by replication clients connected to
  the logger. Each client is returned as a JSON object with the following attributes:

  - `syncerId`: id of the client syncer

  - `serverId`: server id of client

  - `lastServedTick`: last tick value served to this client via the WAL tailing API

  - `time`: date and time when this client last called the WAL tailing API

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "clients" => [],
        "server" => %{
          "engine" => string,
          "serverId" => string,
          "version" => string
        },
        "state" => %{
          "lastLogTick" => string,
          "lastUncommittedLogTick" => string,
          "running" => boolean,
          "time" => string,
          "totalEvents" => integer
        }
      }
  """
  @spec logger_state(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def logger_state(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "replication", "logger-state"],
      opts: opts
    )
  end

  @doc """
  Get the replication logger state. Raises on error.

  See `logger_state/1`.
  """
  @spec logger_state!(Arangox.conn(), keyword) :: term
  def logger_state!(conn, opts \\ []) do
    case logger_state(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Rebuild the replication revision tree

  > **WARNING:**
  This revision-based replication endpoint will only work with collections
  created in ArangoDB v3.8.0 or later.


  Rebuilds the Merkle tree for a collection.

  If successful, there will be no return body.
  """
  @spec rebuild_revision_tree(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def rebuild_revision_tree(conn, collection, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "replication", "revisions", "tree"],
      forced: [{"collection", collection}],
      opts: opts
    )
  end

  @doc """
  Rebuild the replication revision tree. Raises on error.

  See `rebuild_revision_tree/1`.
  """
  @spec rebuild_revision_tree!(Arangox.conn(), binary, keyword) :: term
  def rebuild_revision_tree!(conn, collection, opts \\ []) do
    case rebuild_revision_tree(conn, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the replication revision tree

  > **WARNING:**
  This revision-based replication endpoint will only work with collections
  created in ArangoDB v3.8.0 or later.


  Returns the Merkle tree associated with the specified collection.

  The result will be JSON/VelocyPack in the following format:
  ```
  {
  version: <Number>,
  branchingFactor: <Number>
  maxDepth: <Number>,
  rangeMin: <String, revision>,
  rangeMax: <String, revision>,
  nodes: [
    { count: <Number>, hash: <String, revision> },
    { count: <Number>, hash: <String, revision> },
    ...
    { count: <Number>, hash: <String, revision> }
  ]
  }
  ```

  At the moment, there is only one version, 1, so this can safely be ignored for
  now.

  Each `<String, revision>` value type is a 64-bit value encoded as a string of
  11 characters, using the same encoding as our document `_rev` values. The
  reason for this is that 64-bit values cannot necessarily be represented in full
  in JavaScript, as it handles all numbers as floating point, and can only
  represent up to `2^53-1` faithfully.

  The node count should correspond to a full tree with the given `maxDepth` and
  `branchingFactor`. The nodes are laid out in level-order tree traversal, so the
  root is at index `0`, its children at indices `[1, branchingFactor]`, and so
  on.
  """
  @spec revision_tree(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def revision_tree(conn, collection, batch_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "replication", "revisions", "tree"],
      forced: [{"collection", collection}, {"batchId", batch_id}],
      opts: opts
    )
  end

  @doc """
  Get the replication revision tree. Raises on error.

  See `revision_tree/1`.
  """
  @spec revision_tree!(Arangox.conn(), binary, binary, keyword) :: term
  def revision_tree!(conn, collection, batch_id, opts \\ []) do
    case revision_tree(conn, collection, batch_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the last available tick value

  Returns the last available tick value that can be served from the server's
  replication log. This corresponds to the tick of the latest successful operation.

  The result is a JSON object containing the attributes `tick`, `time` and `server`.
  - `tick`: contains the last available tick, `time`
  - `time`: the server time as string in format `YYYY-MM-DDTHH:MM:SSZ`
  - `server`: An object with fields `version` and `serverId`

  > **INFO:**
  This method is not supported on a Coordinator in a cluster deployment.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "server" => %{
          "serverId" => string,
          "version" => string
        },
        "tick" => string,
        "time" => string
      }
  """
  @spec wal_last_tick(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def wal_last_tick(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "wal", "lastTick"],
      opts: opts
    )
  end

  @doc """
  Get the last available tick value. Raises on error.

  See `wal_last_tick/1`.
  """
  @spec wal_last_tick!(Arangox.conn(), keyword) :: term
  def wal_last_tick!(conn, opts \\ []) do
    case wal_last_tick(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the tick ranges available in the WAL

  Returns the currently available ranges of tick values for all Write-Ahead Log
  (WAL) files. The tick values can be used to determine if certain
  data (identified by tick value) are still available for replication.

  The body of the response contains a JSON object.
  - `tickMin`: minimum tick available
  - `tickMax`: maximum tick available
  - `time`: the server time as string in format `YYYY-MM-DDTHH:MM:SSZ`
  - `server`: An object with fields `version` and `serverId`

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "server" => %{
          "serverId" => string,
          "version" => string
        },
        "tickMax" => string,
        "tickMin" => string,
        "time" => string
      }
  """
  @spec wal_range(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def wal_range(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "wal", "range"],
      opts: opts
    )
  end

  @doc """
  Get the tick ranges available in the WAL. Raises on error.

  See `wal_range/1`.
  """
  @spec wal_range!(Arangox.conn(), keyword) :: term
  def wal_range!(conn, opts \\ []) do
    case wal_range(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Tail recent server operations

  Returns data from the server's write-ahead log (also named replication log). This method can be called
  by replication clients after an initial synchronization of data. The method
  returns all "recent" logged operations from the server. Clients
  can replay and apply these operations locally so they get to the same data
  state as the server.

  Clients can call this method repeatedly to incrementally fetch all changes
  from the server. In this case, they should provide the `from` value so
  they only get returned the log events since their last fetch.

  When the `from` query parameter is not used, the server returns log
  entries starting at the beginning of its replication log. When the `from`
  parameter is used, the server only returns log entries which have
  higher tick values than the specified `from` value (note: the log entry with a
  tick value equal to `from` is excluded). Use the `from` value when
  incrementally fetching log data.

  The `to` query parameter can be used to optionally restrict the upper bound of
  the result to a certain tick value. If used, the result contains only log events
  with tick values up to (including) `to`. In incremental fetching, there is no
  need to use the `to` parameter. It only makes sense in special situations,
  when only parts of the change log are required.

  The `chunkSize` query parameter can be used to control the size of the result.
  It must be specified in bytes. The `chunkSize` value is only honored
  approximately. Otherwise, a too low `chunkSize` value could cause the server
  to not be able to put just one log entry into the result and return it.
  Therefore, the `chunkSize` value is only consulted after a log entry has
  been written into the result. If the result size is then greater than
  `chunkSize`, the server responds with as many log entries as there are
  in the response already. If the result size is still less than `chunkSize`,
  the server tries to return more data if there's more data left to return.

  If `chunkSize` is not specified, some server-side default value is used.

  The `Content-Type` of the result is `application/x-arango-dump`. This is an
  easy-to-process format, with all log events going onto separate lines in the
  response body. Each log event itself is a JSON object, with at least the
  following attributes:

  - `tick`: the log event tick value

  - `type`: the log event type

  Individual log events also have additional attributes, depending on the
  event type. A few common attributes which are used for multiple events types
  are:

  - `cuid`: globally unique id of the View or collection the event was for

  - `db`: the database name the event was for

  - `tid`: id of the transaction the event was contained in

  - `data`: the original document data

  For a more detailed description of the individual replication event types
  and their data structures, see the Operation Types.

  The response also contains the following HTTP headers:

  - `x-arango-replication-active`: whether or not the logger is active. Clients
  can use this flag as an indication for their polling frequency. If the
  logger is not active and there are no more replication events available, it
  might be sensible for a client to abort, or to go to sleep for a long time
  and try again later to check whether the logger has been activated.

  - `x-arango-replication-lastincluded`: the tick value of the last included
  value in the result. In incremental log fetching, this value can be used
  as the `from` value for the following request. **Note** that if the result is
  empty, the value is `0`. This value should not be used as `from` value
  by clients in the next request (otherwise the server would return the log
  events from the start of the log again).

  - `x-arango-replication-lastscanned`: the last tick the server scanned while
  computing the operation log. This might include operations the server did not
  returned to you due to various reasons (i.e. the value was filtered or skipped).
  You may use this value in the `lastScanned` header to allow the RocksDB storage engine
  to break up requests over multiple responses.

  - `x-arango-replication-lasttick`: the last tick value the server has
  logged in its write ahead log (not necessarily included in the result). By comparing the last
  tick and last included tick values, clients have an approximate indication of
  how many events there are still left to fetch.

  - `x-arango-replication-frompresent`: is set to _true_ if server returned
  all tick values starting from the specified tick in the _from_ parameter.
  Should this be set to false the server did not have these operations anymore
  and the client might have missed operations.

  - `x-arango-replication-checkmore`: whether or not there already exists more
  log data which the client could fetch immediately. If there is more log data
  available, the client could call the tailing API again with an adjusted `from`
  value to fetch remaining log entries until there are no more.

  If there isn't any more log data to fetch, the client might decide to go
  to sleep for a while before calling the logger again.

  > **INFO:**
  This method is not supported on a Coordinator in a cluster deployment.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      [%{
        "db" => string,
        "tick" => string,
        "tid" => string,
        "type" => integer
      }]
  """
  @spec wal_tail(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def wal_tail(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "wal", "tail"],
      query: [
        global: "global",
        from: "from",
        to: "to",
        last_scanned: "lastScanned",
        chunk_size: "chunkSize",
        syncer_id: "syncerId",
        server_id: "serverId",
        client_info: "clientInfo"
      ],
      opts: opts
    )
  end

  @doc """
  Tail recent server operations. Raises on error.

  See `wal_tail/1`.
  """
  @spec wal_tail!(Arangox.conn(), keyword) :: term
  def wal_tail!(conn, opts \\ []) do
    case wal_tail(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
