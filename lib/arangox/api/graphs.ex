defmodule Arangox.Api.Graphs do
  @moduledoc """
  ArangoDB's Graphs operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  Add a node collection

  Adds a node collection to the set of orphan collections of the graph.
  If the collection does not exist, it is created.
  """
  @spec add_vertex_collection(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def add_vertex_collection(conn, graph, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "gharial", graph, "vertex"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Add a node collection. Raises on error.

  See `add_vertex_collection/3`.
  """
  @spec add_vertex_collection!(Arangox.conn(), binary, term, keyword) :: term
  def add_vertex_collection!(conn, graph, body, opts \\ []) do
    case add_vertex_collection(conn, graph, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List all graphs

  Lists all graphs stored in this database.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "graphs" => [%{
          "_id" => string,
          "_key" => string,
          "_rev" => string,
          "edgeDefinitions" => [%{
            "collection" => string,
            "from" => [string],
            "to" => [string]
          }],
          "name" => string,
          "orphanCollections" => []
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial"],
      opts: opts
    )
  end

  @doc """
  List all graphs. Raises on error.

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
  List edge collections

  Lists all edge collections within this graph.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "collections" => [string],
        "error" => boolean
      }
  """
  @spec all_edge_collections(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def all_edge_collections(conn, graph, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial", graph, "edge"],
      opts: opts
    )
  end

  @doc """
  List edge collections. Raises on error.

  See `all_edge_collections/2`.
  """
  @spec all_edge_collections!(Arangox.conn(), binary, keyword) :: term
  def all_edge_collections!(conn, graph, opts \\ []) do
    case all_edge_collections(conn, graph, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  List node collections

  Lists all node collections within this graph, including orphan collections.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "collections" => [string],
        "error" => boolean
      }
  """
  @spec all_vertex_collections(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def all_vertex_collections(conn, graph, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial", graph, "vertex"],
      opts: opts
    )
  end

  @doc """
  List node collections. Raises on error.

  See `all_vertex_collections/2`.
  """
  @spec all_vertex_collections!(Arangox.conn(), binary, keyword) :: term
  def all_vertex_collections!(conn, graph, opts \\ []) do
    case all_vertex_collections(conn, graph, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a graph

  The creation of a graph requires the name of the graph and a
  definition of its edges.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "gharial"],
      body: body,
      query: [wait_for_sync: "waitForSync"],
      opts: opts
    )
  end

  @doc """
  Create a graph. Raises on error.

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
  Create an edge

  Creates a new edge in the specified collection.
  Within the body the edge has to contain a `_from` and `_to` value referencing to valid nodes in the graph.
  Furthermore, the edge has to be valid according to the edge definitions.
  """
  @spec create_edge(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_edge(conn, graph, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "gharial", graph, "edge", collection],
      body: body,
      query: [wait_for_sync: "waitForSync", return_new: "returnNew"],
      opts: opts
    )
  end

  @doc """
  Create an edge. Raises on error.

  See `create_edge/4`.
  """
  @spec create_edge!(Arangox.conn(), binary, binary, term, keyword) :: term
  def create_edge!(conn, graph, collection, body, opts \\ []) do
    case create_edge(conn, graph, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Add an edge definition

  Adds an additional edge definition to the graph.

  This edge definition has to contain a `collection` and an array of
  each `from` and `to` node collections. An edge definition can only
  be added if this definition is either not used in any other graph, or
  it is used with exactly the same definition. For example, it is not
  possible to store a definition "e" from "v1" to "v2" in one graph, and
  "e" from "v2" to "v1" in another graph, but both can have "e" from
  "v1" to "v2".

  Additionally, collection creation options can be set.
  """
  @spec create_edge_definition(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_edge_definition(conn, graph, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "gharial", graph, "edge"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Add an edge definition. Raises on error.

  See `create_edge_definition/3`.
  """
  @spec create_edge_definition!(Arangox.conn(), binary, term, keyword) :: term
  def create_edge_definition!(conn, graph, body, opts \\ []) do
    case create_edge_definition(conn, graph, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a node

  Adds a node to the given collection.
  """
  @spec create_vertex(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_vertex(conn, graph, collection, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "gharial", graph, "vertex", collection],
      body: body,
      query: [wait_for_sync: "waitForSync", return_new: "returnNew"],
      opts: opts
    )
  end

  @doc """
  Create a node. Raises on error.

  See `create_vertex/4`.
  """
  @spec create_vertex!(Arangox.conn(), binary, binary, term, keyword) :: term
  def create_vertex!(conn, graph, collection, body, opts \\ []) do
    case create_vertex(conn, graph, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Drop a graph

  Drops an existing graph object by name.
  Optionally all collections not used by other graphs
  can be dropped as well.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, graph, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "gharial", graph],
      query: [drop_collections: "dropCollections"],
      opts: opts
    )
  end

  @doc """
  Drop a graph. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, graph, opts \\ []) do
    case delete(conn, graph, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove an edge

  Removes an edge from an edge collection of the named graph. Any other edges
  that directly reference this edge like a node are removed, too.
  """
  @spec delete_edge(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_edge(conn, graph, collection, edge, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "gharial", graph, "edge", collection, edge],
      query: [wait_for_sync: "waitForSync", return_old: "returnOld"],
      opts: opts
    )
  end

  @doc """
  Remove an edge. Raises on error.

  See `delete_edge/4`.
  """
  @spec delete_edge!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def delete_edge!(conn, graph, collection, edge, opts \\ []) do
    case delete_edge(conn, graph, collection, edge, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove an edge definition

  Remove one edge definition from the graph. This only removes the
  edge collection from the graph definition. The node collections of the
  edge definition become orphan collections but otherwise remain untouched
  and can still be used in your queries.
  """
  @spec delete_edge_definition(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_edge_definition(conn, graph, collection, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "gharial", graph, "edge", collection],
      query: [wait_for_sync: "waitForSync", drop_collections: "dropCollections"],
      opts: opts
    )
  end

  @doc """
  Remove an edge definition. Raises on error.

  See `delete_edge_definition/3`.
  """
  @spec delete_edge_definition!(Arangox.conn(), binary, binary, keyword) :: term
  def delete_edge_definition!(conn, graph, collection, opts \\ []) do
    case delete_edge_definition(conn, graph, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove a node

  Removes a node from a collection of the named graph. Additionally removes all
  incoming and outgoing edges of the node.
  """
  @spec delete_vertex(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_vertex(conn, graph, collection, vertex, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "gharial", graph, "vertex", collection, vertex],
      query: [wait_for_sync: "waitForSync", return_old: "returnOld"],
      opts: opts
    )
  end

  @doc """
  Remove a node. Raises on error.

  See `delete_vertex/4`.
  """
  @spec delete_vertex!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def delete_vertex!(conn, graph, collection, vertex, opts \\ []) do
    case delete_vertex(conn, graph, collection, vertex, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Remove a node collection

  Removes a node collection from the list of the graph's
  orphan collections. It can optionally delete the collection if it is
  not used in any other graph.

  You cannot remove node collections that are used in one of the
  edge definitions of the graph. You need to modify or remove the
  edge definition first in order to fully remove a node collection from
  the graph.
  """
  @spec delete_vertex_collection(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_vertex_collection(conn, graph, collection, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "gharial", graph, "vertex", collection],
      query: [drop_collection: "dropCollection"],
      opts: opts
    )
  end

  @doc """
  Remove a node collection. Raises on error.

  See `delete_vertex_collection/3`.
  """
  @spec delete_vertex_collection!(Arangox.conn(), binary, binary, keyword) :: term
  def delete_vertex_collection!(conn, graph, collection, opts \\ []) do
    case delete_vertex_collection(conn, graph, collection, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a graph

  Selects information for a given graph.
  Returns the edge definitions as well as the orphan collections,
  or returns an error if the graph does not exist.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "graph" => %{
          "_id" => string,
          "_key" => string,
          "_rev" => string,
          "edgeDefinitions" => [%{
            "collection" => string,
            "from" => [string],
            "to" => [string]
          }],
          "name" => string,
          "orphanCollections" => []
        }
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, graph, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial", graph],
      opts: opts
    )
  end

  @doc """
  Get a graph. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, graph, opts \\ []) do
    case get(conn, graph, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get an edge

  Gets an edge from the given collection.
  """
  @spec get_edge(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def get_edge(conn, graph, collection, edge, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial", graph, "edge", collection, edge],
      opts: opts
    )
  end

  @doc """
  Get an edge. Raises on error.

  See `get_edge/4`.
  """
  @spec get_edge!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def get_edge!(conn, graph, collection, edge, opts \\ []) do
    case get_edge(conn, graph, collection, edge, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get a node

  Gets a node from the given collection.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "vertex" => %{
          "_id" => string,
          "_key" => string,
          "_rev" => string
        }
      }
  """
  @spec get_vertex(Arangox.conn(), binary, binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def get_vertex(conn, graph, collection, vertex, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "gharial", graph, "vertex", collection, vertex],
      opts: opts
    )
  end

  @doc """
  Get a node. Raises on error.

  See `get_vertex/4`.
  """
  @spec get_vertex!(Arangox.conn(), binary, binary, binary, keyword) :: term
  def get_vertex!(conn, graph, collection, vertex, opts \\ []) do
    case get_vertex(conn, graph, collection, vertex, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace an edge

  Replaces the data of an edge in the collection.
  """
  @spec replace_edge(Arangox.conn(), binary, binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_edge(conn, graph, collection, edge, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "gharial", graph, "edge", collection, edge],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        keep_null: "keepNull",
        return_old: "returnOld",
        return_new: "returnNew"
      ],
      opts: opts
    )
  end

  @doc """
  Replace an edge. Raises on error.

  See `replace_edge/5`.
  """
  @spec replace_edge!(Arangox.conn(), binary, binary, binary, term, keyword) :: term
  def replace_edge!(conn, graph, collection, edge, body, opts \\ []) do
    case replace_edge(conn, graph, collection, edge, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace an edge definition

  Change the node collections of one specific edge definition.
  This modifies all occurrences of this definition in all graphs known to your database.
  """
  @spec replace_edge_definition(Arangox.conn(), binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_edge_definition(conn, graph, collection, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "gharial", graph, "edge", collection],
      body: body,
      query: [wait_for_sync: "waitForSync", drop_collections: "dropCollections"],
      opts: opts
    )
  end

  @doc """
  Replace an edge definition. Raises on error.

  See `replace_edge_definition/4`.
  """
  @spec replace_edge_definition!(Arangox.conn(), binary, binary, term, keyword) :: term
  def replace_edge_definition!(conn, graph, collection, body, opts \\ []) do
    case replace_edge_definition(conn, graph, collection, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace a node

  Replaces the data of a node in the collection.
  """
  @spec replace_vertex(Arangox.conn(), binary, binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_vertex(conn, graph, collection, vertex, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "gharial", graph, "vertex", collection, vertex],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        keep_null: "keepNull",
        return_old: "returnOld",
        return_new: "returnNew"
      ],
      opts: opts
    )
  end

  @doc """
  Replace a node. Raises on error.

  See `replace_vertex/5`.
  """
  @spec replace_vertex!(Arangox.conn(), binary, binary, binary, term, keyword) :: term
  def replace_vertex!(conn, graph, collection, vertex, body, opts \\ []) do
    case replace_vertex(conn, graph, collection, vertex, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update an edge

  Partially modify the data of the specific edge in the collection.
  """
  @spec update_edge(Arangox.conn(), binary, binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_edge(conn, graph, collection, edge, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "gharial", graph, "edge", collection, edge],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        keep_null: "keepNull",
        return_old: "returnOld",
        return_new: "returnNew"
      ],
      opts: opts
    )
  end

  @doc """
  Update an edge. Raises on error.

  See `update_edge/5`.
  """
  @spec update_edge!(Arangox.conn(), binary, binary, binary, term, keyword) :: term
  def update_edge!(conn, graph, collection, edge, body, opts \\ []) do
    case update_edge(conn, graph, collection, edge, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update a node

  Updates the data of the specific node in the collection.
  """
  @spec update_vertex(Arangox.conn(), binary, binary, binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_vertex(conn, graph, collection, vertex, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "gharial", graph, "vertex", collection, vertex],
      body: body,
      query: [
        wait_for_sync: "waitForSync",
        keep_null: "keepNull",
        return_old: "returnOld",
        return_new: "returnNew"
      ],
      opts: opts
    )
  end

  @doc """
  Update a node. Raises on error.

  See `update_vertex/5`.
  """
  @spec update_vertex!(Arangox.conn(), binary, binary, binary, term, keyword) :: term
  def update_vertex!(conn, graph, collection, vertex, body, opts \\ []) do
    case update_vertex(conn, graph, collection, vertex, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get inbound and outbound edges

  Returns an array of edges starting or ending in the node identified by
  `vertex`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "edges" => [%{
          "_from" => string,
          "_id" => string,
          "_key" => string,
          "_rev" => string,
          "_to" => string
        }],
        "error" => boolean,
        "stats" => %{
          "cacheHits" => integer,
          "cacheMisses" => integer,
          "cursorsCreated" => integer,
          "cursorsRearmed" => integer,
          "documentLookups" => integer,
          "executionTime" => float,
          "filtered" => integer,
          "httpRequests" => integer,
          "intermediateCommits" => integer,
          "peakMemoryUsage" => integer,
          "scannedFull" => integer,
          "scannedIndex" => integer,
          "searchParallelism" => integer,
          "seeks" => integer,
          "writesExecuted" => integer,
          "writesIgnored" => integer
        }
      }
  """
  @spec vertex_edges(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def vertex_edges(conn, collection, vertex, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "edges", collection],
      forced: [{"vertex", vertex}],
      query: [direction: "direction"],
      opts: opts
    )
  end

  @doc """
  Get inbound and outbound edges. Raises on error.

  See `vertex_edges/2`.
  """
  @spec vertex_edges!(Arangox.conn(), binary, binary, keyword) :: term
  def vertex_edges!(conn, collection, vertex, opts \\ []) do
    case vertex_edges(conn, collection, vertex, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
