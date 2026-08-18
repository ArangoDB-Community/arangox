defmodule Arangox.Api.Cluster do
  @moduledoc """
  Provides API endpoints related to cluster
  """

  @default_client Arangox.Api.Client

  @type compute_cluster_rebalance_plan_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result()
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result :: %{
          imbalanceAfter:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after(),
          imbalanceBefore:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before(),
          moves: [Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_moves()]
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after :: %{
          leader:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_leader(),
          shards:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_shards()
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_leader :: %{
          imbalance: integer,
          leaderDupl: [integer],
          numberShards: [integer],
          targetWeight: [integer],
          totalShards: integer,
          totalWeight: integer,
          weightUsed: [integer]
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_shards :: %{
          imbalance: integer,
          numberShards: [integer],
          sizeUsed: [integer],
          targetSize: [integer],
          totalShards: integer,
          totalShardsFromSystemCollections: integer,
          totalUsed: integer
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before :: %{
          leader:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_leader(),
          shards:
            Arangox.Api.Cluster.compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_shards()
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_leader :: %{
          imbalance: integer,
          leaderDupl: [integer],
          numberShards: [integer],
          targetWeight: [integer],
          totalShards: integer,
          totalWeight: integer,
          weightUsed: [integer]
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_shards :: %{
          imbalance: integer,
          numberShards: [integer],
          sizeUsed: [integer],
          targetSize: [integer],
          totalShards: integer,
          totalShardsFromSystemCollections: integer,
          totalUsed: integer
        }

  @type compute_cluster_rebalance_plan_200_json_resp_result_moves :: %{
          collection: number,
          from: String.t(),
          isLeader: boolean,
          shard: String.t(),
          to: String.t()
        }

  @doc """
  Compute a set of move shard operations to improve balance

  Compute a set of move shard operations to improve balance.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec compute_cluster_rebalance_plan(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def compute_cluster_rebalance_plan(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Cluster, :compute_cluster_rebalance_plan},
      url: "/_admin/cluster/rebalance",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, {Arangox.Api.Cluster, :compute_cluster_rebalance_plan_200_json_resp}}],
      opts: opts
    })
  end

  @doc """
  Execute a set of move shard operations

  Execute the given set of move shard operations. You can use the
  `POST /_admin/cluster/rebalance` endpoint to calculate these operations to improve
  the balance of shards, leader shards, and follower shards.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec execute_cluster_rebalance_plan(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def execute_cluster_rebalance_plan(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Cluster, :execute_cluster_rebalance_plan},
      url: "/_admin/cluster/rebalance/execute",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {202, :null}],
      opts: opts
    })
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

  """
  @spec get_cluster_health(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_cluster_health(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :get_cluster_health},
      url: "/_admin/cluster/health",
      method: :get,
      response: [{200, :null}],
      opts: opts
    })
  end

  @type get_cluster_imbalance_200_json_resp :: %{
          code: integer,
          error: boolean,
          pendingMoveShards: number,
          result: Arangox.Api.Cluster.get_cluster_imbalance_200_json_resp_result(),
          todoMoveShards: number
        }

  @type get_cluster_imbalance_200_json_resp_result :: %{
          leader: Arangox.Api.Cluster.get_cluster_imbalance_200_json_resp_result_leader(),
          shards: Arangox.Api.Cluster.get_cluster_imbalance_200_json_resp_result_shards()
        }

  @type get_cluster_imbalance_200_json_resp_result_leader :: %{
          imbalance: integer,
          leaderDupl: [integer],
          numberShards: [integer],
          targetWeight: [integer],
          totalShards: integer,
          totalWeight: integer,
          weightUsed: [integer]
        }

  @type get_cluster_imbalance_200_json_resp_result_shards :: %{
          imbalance: integer,
          numberShards: [integer],
          sizeUsed: [integer],
          targetSize: [integer],
          totalShards: integer,
          totalShardsFromSystemCollections: integer,
          totalUsed: integer
        }

  @doc """
  Get the current cluster imbalance

  Computes the current cluster imbalance and returns the result.
  It additionally shows the amount of ongoing and pending move shard operations.

  """
  @spec get_cluster_imbalance(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_cluster_imbalance(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :get_cluster_imbalance},
      url: "/_admin/cluster/rebalance",
      method: :get,
      response: [{200, {Arangox.Api.Cluster, :get_cluster_imbalance_200_json_resp}}],
      opts: opts
    })
  end

  @doc """
  Get the statistics of a DB-Server

  > **WARNING:**
  This endpoint is deprecated and removed in ArangoDB v4.0.
  Use `GET /_admin/metrics` instead, which provides the data exposed by
  this API and a lot more.

  Queries the statistics of the given DB-Server

  ## Options

    * `DBserver`: The ID of a DB-Server.
      

  """
  @spec get_cluster_statistics(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_cluster_statistics(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:DBserver])

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :get_cluster_statistics},
      url: "/_admin/cluster/statistics",
      method: :get,
      query: query,
      response: [{200, :null}, {400, :null}, {403, :null}],
      opts: opts
    })
  end

  @type get_dbserver_maintenance_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Cluster.get_dbserver_maintenance_200_json_resp_result() | nil
        }

  @type get_dbserver_maintenance_200_json_resp_result :: %{Mode: String.t(), Until: String.t()}

  @doc """
  Get the maintenance status of a DB-Server

  Check whether the specified DB-Server is in maintenance mode and until when.

  """
  @spec get_dbserver_maintenance(db_server_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_dbserver_maintenance(db_server_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [db_server_id: db_server_id],
      call: {Arangox.Api.Cluster, :get_dbserver_maintenance},
      url: "/_admin/cluster/maintenance/#{db_server_id}",
      method: :get,
      response: [
        {200, {Arangox.Api.Cluster, :get_dbserver_maintenance_200_json_resp}},
        {400, :null},
        {412, :null},
        {504, :null}
      ],
      opts: opts
    })
  end

  @doc """
  Get the server ID

  Returns the ID of a server in a cluster. The request will fail if the
  server is not running in cluster mode.

  """
  @spec get_server_id(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_id(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :get_server_id},
      url: "/_admin/server/id",
      method: :get,
      response: [{200, :null}, {500, :null}],
      opts: opts
    })
  end

  @type get_server_role_200_json_resp :: %{
          code: integer,
          error: boolean,
          errorNum: integer,
          role: String.t()
        }

  @doc """
  Get the server role

  Returns the role of a server in a cluster.
  The server role is returned in the `role` attribute of the result.

  """
  @spec get_server_role(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_role(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :get_server_role},
      url: "/_admin/server/role",
      method: :get,
      response: [{200, {Arangox.Api.Cluster, :get_server_role_200_json_resp}}],
      opts: opts
    })
  end

  @type list_cluster_endpoints_200_json_resp :: %{
          code: integer,
          endpoints: [Arangox.Api.Cluster.list_cluster_endpoints_200_json_resp_endpoints()],
          error: boolean
        }

  @type list_cluster_endpoints_200_json_resp_endpoints :: %{endpoint: String.t()}

  @doc """
  List all Coordinator endpoints

  Returns an object with an attribute `endpoints`, which contains an
  array of objects, which each have the attribute `endpoint`, whose value
  is a string with the endpoint description. There is an entry for each
  Coordinator in the cluster. This method only works on Coordinators in
  cluster mode. In case of an error the `error` attribute is set to
  `true`.

  """
  @spec list_cluster_endpoints(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_cluster_endpoints(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :list_cluster_endpoints},
      url: "/_api/cluster/endpoints",
      method: :get,
      response: [
        {200, {Arangox.Api.Cluster, :list_cluster_endpoints_200_json_resp}},
        {501, :null}
      ],
      opts: opts
    })
  end

  @type reserve_unique_i_ds_200_json_resp :: %{
          code: integer,
          error: boolean,
          largest: String.t(),
          smallest: String.t()
        }

  @type reserve_unique_i_ds_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Reserve globally unique IDs

  Reserve or skip globally unique identifiers that are used as automatically
  generated document keys when using the `traditional` or `padded` key generators.

  Either the `number` or the `minimum` query parameter needs to be specified.

  > **WARNING:**
  Only use this endpoint to resolve issues with the key generation,
  in particular of cluster deployments created with v3.12.5-2 or older.

  ## Options

    * `number`: Reserve as many globally unique IDs as specified.
      
    * `minimum`: Make sure that globally unique IDs used in the future will always be
      at least as large as the specified value.
      
      Coordinators and DB-Servers will use these larger IDs only after a restart.
      

  """
  @spec reserve_unique_i_ds(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def reserve_unique_i_ds(opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:minimum, :number])

    client.request(%{
      args: [],
      call: {Arangox.Api.Cluster, :reserve_unique_i_ds},
      url: "/_admin/cluster/uniqId",
      method: :put,
      query: query,
      response: [
        {200, {Arangox.Api.Cluster, :reserve_unique_i_ds_200_json_resp}},
        {400, {Arangox.Api.Cluster, :reserve_unique_i_ds_400_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Set the cluster maintenance mode

  Enable or disable the cluster supervision (Agency) maintenance mode.

  This endpoint allows you to temporarily enable the supervision maintenance mode.
  Please be aware that no automatic failovers of any kind will take place
  while the maintenance mode is enabled. The cluster supervision reactivates
  itself automatically at some point after disabling it.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_cluster_maintenance(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_cluster_maintenance(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Cluster, :set_cluster_maintenance},
      url: "/_admin/cluster/maintenance",
      body: body,
      method: :put,
      request: [{"application/json", :string}],
      response: [{200, :null}, {400, :null}, {501, :null}, {504, :null}],
      opts: opts
    })
  end

  @type set_dbserver_maintenance_200_json_resp :: %{code: integer, error: boolean}

  @doc """
  Set the maintenance status of a DB-Server

  Enable or disable the maintenance mode of a DB-Server.

  For rolling upgrades or rolling restarts, DB-Servers can be put into
  maintenance mode, so that no attempts are made to re-distribute the data in a
  cluster for such planned events. DB-Servers in maintenance mode are not
  considered viable failover targets because they are likely restarted soon.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec set_dbserver_maintenance(db_server_id :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def set_dbserver_maintenance(db_server_id, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [db_server_id: db_server_id, body: body],
      call: {Arangox.Api.Cluster, :set_dbserver_maintenance},
      url: "/_admin/cluster/maintenance/#{db_server_id}",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Cluster, :set_dbserver_maintenance_200_json_resp}},
        {400, :null},
        {412, :null},
        {504, :null}
      ],
      opts: opts
    })
  end

  @type start_cluster_rebalance_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result()
        }

  @type start_cluster_rebalance_200_json_resp_result :: %{
          imbalanceAfter:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_after(),
          imbalanceBefore:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_before(),
          moves: [Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_moves()]
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_after :: %{
          leader:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_after_leader(),
          shards:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_after_shards()
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_after_leader :: %{
          imbalance: integer,
          leaderDupl: [integer],
          numberShards: [integer],
          targetWeight: [integer],
          totalShards: integer,
          totalWeight: integer,
          weightUsed: [integer]
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_after_shards :: %{
          imbalance: integer,
          numberShards: [integer],
          sizeUsed: [integer],
          targetSize: [integer],
          totalShards: integer,
          totalShardsFromSystemCollections: integer,
          totalUsed: integer
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_before :: %{
          leader:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_before_leader(),
          shards:
            Arangox.Api.Cluster.start_cluster_rebalance_200_json_resp_result_imbalance_before_shards()
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_before_leader :: %{
          imbalance: integer,
          leaderDupl: [integer],
          numberShards: [integer],
          targetWeight: [integer],
          totalShards: integer,
          totalWeight: integer,
          weightUsed: [integer]
        }

  @type start_cluster_rebalance_200_json_resp_result_imbalance_before_shards :: %{
          imbalance: integer,
          numberShards: [integer],
          sizeUsed: [integer],
          targetSize: [integer],
          totalShards: integer,
          totalShardsFromSystemCollections: integer,
          totalUsed: integer
        }

  @type start_cluster_rebalance_200_json_resp_result_moves :: %{
          collection: number,
          from: String.t(),
          isLeader: boolean,
          shard: String.t(),
          to: String.t()
        }

  @doc """
  Compute and execute a set of move shard operations to improve balance

  Compute a set of move shard operations to improve balance.
  These moves are then immediately executed.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec start_cluster_rebalance(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def start_cluster_rebalance(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Cluster, :start_cluster_rebalance},
      url: "/_admin/cluster/rebalance",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [{200, {Arangox.Api.Cluster, :start_cluster_rebalance_200_json_resp}}],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:compute_cluster_rebalance_plan_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Cluster, :compute_cluster_rebalance_plan_200_json_resp_result}
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result) do
    [
      imbalanceAfter:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after},
      imbalanceBefore:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before},
      moves: [{Arangox.Api.Cluster, :compute_cluster_rebalance_plan_200_json_resp_result_moves}]
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after) do
    [
      leader:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_leader},
      shards:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_shards}
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_leader) do
    [
      imbalance: :integer,
      leaderDupl: [:integer],
      numberShards: [:integer],
      targetWeight: [:integer],
      totalShards: :integer,
      totalWeight: :integer,
      weightUsed: [:integer]
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_after_shards) do
    [
      imbalance: :integer,
      numberShards: [:integer],
      sizeUsed: [:integer],
      targetSize: [:integer],
      totalShards: :integer,
      totalShardsFromSystemCollections: :integer,
      totalUsed: :integer
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before) do
    [
      leader:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_leader},
      shards:
        {Arangox.Api.Cluster,
         :compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_shards}
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_leader) do
    [
      imbalance: :integer,
      leaderDupl: [:integer],
      numberShards: [:integer],
      targetWeight: [:integer],
      totalShards: :integer,
      totalWeight: :integer,
      weightUsed: [:integer]
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_imbalance_before_shards) do
    [
      imbalance: :integer,
      numberShards: [:integer],
      sizeUsed: [:integer],
      targetSize: [:integer],
      totalShards: :integer,
      totalShardsFromSystemCollections: :integer,
      totalUsed: :integer
    ]
  end

  def __fields__(:compute_cluster_rebalance_plan_200_json_resp_result_moves) do
    [collection: :number, from: :string, isLeader: :boolean, shard: :string, to: :string]
  end

  def __fields__(:get_cluster_imbalance_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      pendingMoveShards: :number,
      result: {Arangox.Api.Cluster, :get_cluster_imbalance_200_json_resp_result},
      todoMoveShards: :number
    ]
  end

  def __fields__(:get_cluster_imbalance_200_json_resp_result) do
    [
      leader: {Arangox.Api.Cluster, :get_cluster_imbalance_200_json_resp_result_leader},
      shards: {Arangox.Api.Cluster, :get_cluster_imbalance_200_json_resp_result_shards}
    ]
  end

  def __fields__(:get_cluster_imbalance_200_json_resp_result_leader) do
    [
      imbalance: :integer,
      leaderDupl: [:integer],
      numberShards: [:integer],
      targetWeight: [:integer],
      totalShards: :integer,
      totalWeight: :integer,
      weightUsed: [:integer]
    ]
  end

  def __fields__(:get_cluster_imbalance_200_json_resp_result_shards) do
    [
      imbalance: :integer,
      numberShards: [:integer],
      sizeUsed: [:integer],
      targetSize: [:integer],
      totalShards: :integer,
      totalShardsFromSystemCollections: :integer,
      totalUsed: :integer
    ]
  end

  def __fields__(:get_dbserver_maintenance_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Cluster, :get_dbserver_maintenance_200_json_resp_result}
    ]
  end

  def __fields__(:get_dbserver_maintenance_200_json_resp_result) do
    [Mode: :string, Until: :string]
  end

  def __fields__(:get_server_role_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      errorNum: :integer,
      role: {:enum, ["SINGLE", "COORDINATOR", "PRIMARY", "SECONDARY", "AGENT", "UNDEFINED"]}
    ]
  end

  def __fields__(:list_cluster_endpoints_200_json_resp) do
    [
      code: :integer,
      endpoints: [{Arangox.Api.Cluster, :list_cluster_endpoints_200_json_resp_endpoints}],
      error: :boolean
    ]
  end

  def __fields__(:list_cluster_endpoints_200_json_resp_endpoints) do
    [endpoint: :string]
  end

  def __fields__(:reserve_unique_i_ds_200_json_resp) do
    [code: :integer, error: :boolean, largest: :string, smallest: :string]
  end

  def __fields__(:reserve_unique_i_ds_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:set_dbserver_maintenance_200_json_resp) do
    [code: :integer, error: :boolean]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Cluster, :start_cluster_rebalance_200_json_resp_result}
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result) do
    [
      imbalanceAfter:
        {Arangox.Api.Cluster, :start_cluster_rebalance_200_json_resp_result_imbalance_after},
      imbalanceBefore:
        {Arangox.Api.Cluster, :start_cluster_rebalance_200_json_resp_result_imbalance_before},
      moves: [{Arangox.Api.Cluster, :start_cluster_rebalance_200_json_resp_result_moves}]
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_after) do
    [
      leader:
        {Arangox.Api.Cluster,
         :start_cluster_rebalance_200_json_resp_result_imbalance_after_leader},
      shards:
        {Arangox.Api.Cluster,
         :start_cluster_rebalance_200_json_resp_result_imbalance_after_shards}
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_after_leader) do
    [
      imbalance: :integer,
      leaderDupl: [:integer],
      numberShards: [:integer],
      targetWeight: [:integer],
      totalShards: :integer,
      totalWeight: :integer,
      weightUsed: [:integer]
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_after_shards) do
    [
      imbalance: :integer,
      numberShards: [:integer],
      sizeUsed: [:integer],
      targetSize: [:integer],
      totalShards: :integer,
      totalShardsFromSystemCollections: :integer,
      totalUsed: :integer
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_before) do
    [
      leader:
        {Arangox.Api.Cluster,
         :start_cluster_rebalance_200_json_resp_result_imbalance_before_leader},
      shards:
        {Arangox.Api.Cluster,
         :start_cluster_rebalance_200_json_resp_result_imbalance_before_shards}
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_before_leader) do
    [
      imbalance: :integer,
      leaderDupl: [:integer],
      numberShards: [:integer],
      targetWeight: [:integer],
      totalShards: :integer,
      totalWeight: :integer,
      weightUsed: [:integer]
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_imbalance_before_shards) do
    [
      imbalance: :integer,
      numberShards: [:integer],
      sizeUsed: [:integer],
      targetSize: [:integer],
      totalShards: :integer,
      totalShardsFromSystemCollections: :integer,
      totalUsed: :integer
    ]
  end

  def __fields__(:start_cluster_rebalance_200_json_resp_result_moves) do
    [collection: :number, from: :string, isLeader: :boolean, shard: :string, to: :string]
  end
end
