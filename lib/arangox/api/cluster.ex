defmodule Arangox.Api.Cluster do
  @moduledoc """
  ArangoDB's Cluster operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all Coordinator endpoints

  Returns an object with an attribute `endpoints`, which contains an
  array of objects, which each have the attribute `endpoint`, whose value
  is a string with the endpoint description. There is an entry for each
  Coordinator in the cluster. This method only works on Coordinators in
  cluster mode. In case of an error the `error` attribute is set to
  `true`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "endpoints" => [%{
          "endpoint" => string
        }],
        "error" => boolean
      }
  """
  @spec all_endpoints(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all_endpoints(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "cluster", "endpoints"],
      opts: opts
    )
  end

  @doc """
  List all Coordinator endpoints. Raises on error.

  See `all_endpoints/1`.
  """
  @spec all_endpoints!(Arangox.conn(), keyword) :: term
  def all_endpoints!(conn, opts \\ []) do
    case all_endpoints(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Compute a set of move shard operations to improve balance

  Compute a set of move shard operations to improve balance.
  """
  @spec compute_rebalance_plan(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def compute_rebalance_plan(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "cluster", "rebalance"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Compute a set of move shard operations to improve balance. Raises on error.

  See `compute_rebalance_plan/2`.
  """
  @spec compute_rebalance_plan!(Arangox.conn(), term, keyword) :: term
  def compute_rebalance_plan!(conn, body, opts \\ []) do
    case compute_rebalance_plan(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the maintenance status of a DB-Server

  Check whether the specified DB-Server is in maintenance mode and until when.
  """
  @spec dbserver_maintenance(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def dbserver_maintenance(conn, dbserver_id, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "cluster", "maintenance", dbserver_id],
      opts: opts
    )
  end

  @doc """
  Get the maintenance status of a DB-Server. Raises on error.

  See `dbserver_maintenance/2`.
  """
  @spec dbserver_maintenance!(Arangox.conn(), binary, keyword) :: term
  def dbserver_maintenance!(conn, dbserver_id, opts \\ []) do
    case dbserver_maintenance(conn, dbserver_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Execute a set of move shard operations

  Execute the given set of move shard operations. You can use the
  `POST /_admin/cluster/rebalance` endpoint to calculate these operations to improve
  the balance of shards, leader shards, and follower shards.
  """
  @spec execute_rebalance_plan(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def execute_rebalance_plan(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "cluster", "rebalance", "execute"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Execute a set of move shard operations. Raises on error.

  See `execute_rebalance_plan/2`.
  """
  @spec execute_rebalance_plan!(Arangox.conn(), term, keyword) :: term
  def execute_rebalance_plan!(conn, body, opts \\ []) do
    case execute_rebalance_plan(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the cluster health

  Queries the health of the cluster as assessed by the supervision (Agency) for
  monitoring purposes. The response is a JSON object, containing the standard
  `code`, `error`, `errorNum`, and `errorMessage` fields as appropriate.
  The endpoint-specific fields are as follows:

  - `ClusterId`: A UUID string identifying the cluster
  - `Health`: An object containing a descriptive sub-object for each node in the cluster.
  - `<nodeID>`: Each entry in `Health` will be keyed by the node ID and contain the following attributes:
    - `Endpoint`: A string representing the network endpoint of the server.
    - `Role`: The role the server plays. Possible values are `"AGENT"`, `"COORDINATOR"`, and `"DBSERVER"`.
    - `CanBeDeleted`: Boolean representing whether the node can safely be removed from the cluster.
    - `Version`: Version String of ArangoDB used by that node.
    - `Engine`: Storage Engine used by that node.
    - `Status`: A string indicating the health of the node as assessed by the supervision (Agency). This should be considered primary source of truth for Coordinator and DB-Servers node health. If the node is responding normally to requests, it is `"GOOD"`. If it has missed one heartbeat, it is `"BAD"`. If it has been declared failed by the supervision, which occurs after missing heartbeats for about 15 seconds, it will be marked `"FAILED"`.

    Additionally it will also have the following attributes for:

    **Coordinators** and **DB-Servers**
    - `SyncStatus`: The last sync status reported by the node. This value is primarily used to determine the value of `Status`. Possible values include `"UNKNOWN"`, `"UNDEFINED"`, `"STARTUP"`, `"STOPPING"`, `"STOPPED"`, `"SERVING"`, `"SHUTDOWN"`.
    - `LastAckedTime`: ISO 8601 timestamp specifying the last heartbeat received.
    - `ShortName`: A string representing the shortname of the server, e.g. `"Coordinator0001"`.
    - `Timestamp`: ISO 8601 timestamp specifying the last heartbeat received. (deprecated)
    - `Host`: An optional string, specifying the host machine if known.
    - `SyncTime`: ISO 8601 timestamp of the last sync time reported by the node.

    **Coordinators** only
    - `AdvertisedEndpoint`: A string representing the advertised endpoint, if set. (e.g. external IP address or load balancer, optional)

    **Agents**
    - `Leader`: ID of the Agent this node regards as leader.
    - `Leading`: Whether this Agent is the leader (true) or not (false).
    - `LastAckedTime`: Time since last `acked` in seconds.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "ClusterId" => string,
        "Health" => %{
          "AGNT-45e0a050-ce4d-4da8-9fde-36c6a917c66d" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "LastAckedTime" => integer,
            "Leader" => string,
            "Leading" => boolean,
            "Role" => string,
            "Status" => string,
            "Version" => string
          },
          "AGNT-a8209bbc-1afd-45ef-90f5-dc208c57004f" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "LastAckedTime" => float,
            "Leader" => string,
            "Leading" => boolean,
            "Role" => string,
            "Status" => string,
            "Version" => string
          },
          "AGNT-f24d169c-d8c8-43cf-9089-c28251402983" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "LastAckedTime" => float,
            "Leader" => string,
            "Leading" => boolean,
            "Role" => string,
            "Status" => string,
            "Version" => string
          },
          "CRDN-42a57593-b942-49b0-84af-7231d373f272" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          },
          "CRDN-76cb69cd-2d7d-4294-8b8a-41a859aa70f5" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          },
          "CRDN-7db819e9-ec25-4a0a-9c39-e3f99e5a3de8" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          },
          "PRMR-36e455fd-7f1a-4516-9f40-497fbfc420d7" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          },
          "PRMR-61e7bb1b-77c3-4910-b7f9-589bc482db6f" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          },
          "PRMR-9fc93aee-322f-4ae3-9b20-116477c50f41" => %{
            "CanBeDeleted" => boolean,
            "Endpoint" => string,
            "Engine" => string,
            "Host" => string,
            "LastAckedTime" => string,
            "Role" => string,
            "ShortName" => string,
            "Status" => string,
            "SyncStatus" => string,
            "SyncTime" => string,
            "Timestamp" => string,
            "Version" => string
          }
        },
        "code" => integer,
        "error" => boolean
      }
  """
  @spec health(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def health(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "cluster", "health"],
      opts: opts
    )
  end

  @doc """
  Get the cluster health. Raises on error.

  See `health/1`.
  """
  @spec health!(Arangox.conn(), keyword) :: term
  def health!(conn, opts \\ []) do
    case health(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the current cluster imbalance

  Computes the current cluster imbalance and returns the result.
  It additionally shows the amount of ongoing and pending move shard operations.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => %{
          "leader" => %{
            "imbalance" => float,
            "leaderDupl" => [integer],
            "numberShards" => [integer],
            "targetWeight" => [float],
            "totalShards" => integer,
            "totalWeight" => integer,
            "weightUsed" => [integer]
          },
          "pendingMoveShards" => integer,
          "shards" => %{
            "imbalance" => integer,
            "numberShards" => [integer],
            "sizeUsed" => [integer],
            "targetSize" => [integer],
            "totalShards" => integer,
            "totalShardsFromSystemCollections" => integer,
            "totalUsed" => integer
          },
          "todoMoveShards" => integer
        }
      }
  """
  @spec imbalance(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def imbalance(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "cluster", "rebalance"],
      opts: opts
    )
  end

  @doc """
  Get the current cluster imbalance. Raises on error.

  See `imbalance/1`.
  """
  @spec imbalance!(Arangox.conn(), keyword) :: term
  def imbalance!(conn, opts \\ []) do
    case imbalance(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Reserve globally unique IDs

  Reserve or skip globally unique identifiers that are used as automatically
  generated document keys when using the `traditional` or `padded` key generators.

  Either the `number` or the `minimum` query parameter needs to be specified.

  > **WARNING:**
  Only use this endpoint to resolve issues with the key generation,
  in particular of cluster deployments created with v3.12.5-2 or older.
  """
  @spec reserve_unique_ids(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def reserve_unique_ids(conn, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "cluster", "uniqId"],
      query: [number: "number", minimum: "minimum"],
      opts: opts
    )
  end

  @doc """
  Reserve globally unique IDs. Raises on error.

  See `reserve_unique_ids/1`.
  """
  @spec reserve_unique_ids!(Arangox.conn(), keyword) :: term
  def reserve_unique_ids!(conn, opts \\ []) do
    case reserve_unique_ids(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the server ID

  Returns the ID of a server in a cluster. The request will fail if the
  server is not running in cluster mode.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "id" => string
      }
  """
  @spec server_id(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_id(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "id"],
      opts: opts
    )
  end

  @doc """
  Get the server ID. Raises on error.

  See `server_id/1`.
  """
  @spec server_id!(Arangox.conn(), keyword) :: term
  def server_id!(conn, opts \\ []) do
    case server_id(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the server role

  Returns the role of a server in a cluster.
  The server role is returned in the `role` attribute of the result.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "mode" => string,
        "role" => string
      }
  """
  @spec server_role(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_role(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "role"],
      opts: opts
    )
  end

  @doc """
  Get the server role. Raises on error.

  See `server_role/1`.
  """
  @spec server_role!(Arangox.conn(), keyword) :: term
  def server_role!(conn, opts \\ []) do
    case server_role(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set the maintenance status of a DB-Server

  Enable or disable the maintenance mode of a DB-Server.

  For rolling upgrades or rolling restarts, DB-Servers can be put into
  maintenance mode, so that no attempts are made to re-distribute the data in a
  cluster for such planned events. DB-Servers in maintenance mode are not
  considered viable failover targets because they are likely restarted soon.
  """
  @spec set_dbserver_maintenance(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def set_dbserver_maintenance(conn, dbserver_id, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "cluster", "maintenance", dbserver_id],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set the maintenance status of a DB-Server. Raises on error.

  See `set_dbserver_maintenance/3`.
  """
  @spec set_dbserver_maintenance!(Arangox.conn(), binary, term, keyword) :: term
  def set_dbserver_maintenance!(conn, dbserver_id, body, opts \\ []) do
    case set_dbserver_maintenance(conn, dbserver_id, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Set the cluster maintenance mode

  Enable or disable the cluster supervision (Agency) maintenance mode.

  This endpoint allows you to temporarily enable the supervision maintenance mode.
  Please be aware that no automatic failovers of any kind will take place
  while the maintenance mode is enabled. The cluster supervision reactivates
  itself automatically at some point after disabling it.
  """
  @spec set_maintenance(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def set_maintenance(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "cluster", "maintenance"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Set the cluster maintenance mode. Raises on error.

  See `set_maintenance/2`.
  """
  @spec set_maintenance!(Arangox.conn(), term, keyword) :: term
  def set_maintenance!(conn, body, opts \\ []) do
    case set_maintenance(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Compute and execute a set of move shard operations to improve balance

  Compute a set of move shard operations to improve balance.
  These moves are then immediately executed.
  """
  @spec start_rebalance(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def start_rebalance(conn, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_admin", "cluster", "rebalance"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Compute and execute a set of move shard operations to improve balance. Raises on error.

  See `start_rebalance/2`.
  """
  @spec start_rebalance!(Arangox.conn(), term, keyword) :: term
  def start_rebalance!(conn, body, opts \\ []) do
    case start_rebalance(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the statistics of a DB-Server

  > **WARNING:**
  This endpoint is deprecated and removed in ArangoDB v4.0.
  Use `GET /_admin/metrics` instead, which provides the data exposed by
  this API and a lot more.


  Queries the statistics of the given DB-Server
  """
  @spec statistics(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def statistics(conn, d_bserver, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "cluster", "statistics"],
      forced: [{"DBserver", d_bserver}],
      opts: opts
    )
  end

  @doc """
  Get the statistics of a DB-Server. Raises on error.

  See `statistics/1`.
  """
  @spec statistics!(Arangox.conn(), binary, keyword) :: term
  def statistics!(conn, d_bserver, opts \\ []) do
    case statistics(conn, d_bserver, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
