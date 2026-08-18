defmodule Arangox.Api.Graphs do
  @moduledoc """
  Provides API endpoints related to graphs
  """

  @default_client Arangox.Api.Client

  @type add_vertex_collection_201_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.add_vertex_collection_201_json_resp_graph()
        }

  @type add_vertex_collection_201_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.add_vertex_collection_201_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type add_vertex_collection_201_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type add_vertex_collection_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.add_vertex_collection_202_json_resp_graph()
        }

  @type add_vertex_collection_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.add_vertex_collection_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type add_vertex_collection_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type add_vertex_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type add_vertex_collection_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type add_vertex_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Add a node collection

  Adds a node collection to the set of orphan collections of the graph.
  If the collection does not exist, it is created.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec add_vertex_collection(
          database_name :: String.t(),
          graph :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def add_vertex_collection(database_name, graph, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph, body: body],
      call: {Arangox.Api.Graphs, :add_vertex_collection},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :add_vertex_collection_201_json_resp}},
        {202, {Arangox.Api.Graphs, :add_vertex_collection_202_json_resp}},
        {400, {Arangox.Api.Graphs, :add_vertex_collection_400_json_resp}},
        {403, {Arangox.Api.Graphs, :add_vertex_collection_403_json_resp}},
        {404, {Arangox.Api.Graphs, :add_vertex_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_edge_201_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.create_edge_201_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.create_edge_201_json_resp_new() | nil
        }

  @type create_edge_201_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type create_edge_201_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type create_edge_202_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.create_edge_202_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.create_edge_202_json_resp_new() | nil
        }

  @type create_edge_202_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type create_edge_202_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type create_edge_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_edge_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_edge_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_edge_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create an edge

  Creates a new edge in the specified collection.
  Within the body the edge has to contain a `_from` and `_to` value referencing to valid nodes in the graph.
  Furthermore, the edge has to be valid according to the edge definitions.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_edge(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_edge(database_name, graph, collection, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:returnNew, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, body: body],
      call: {Arangox.Api.Graphs, :create_edge},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :create_edge_201_json_resp}},
        {202, {Arangox.Api.Graphs, :create_edge_202_json_resp}},
        {400, {Arangox.Api.Graphs, :create_edge_400_json_resp}},
        {403, {Arangox.Api.Graphs, :create_edge_403_json_resp}},
        {404, {Arangox.Api.Graphs, :create_edge_404_json_resp}},
        {410, {Arangox.Api.Graphs, :create_edge_410_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_edge_definition_201_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.create_edge_definition_201_json_resp_graph()
        }

  @type create_edge_definition_201_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.create_edge_definition_201_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type create_edge_definition_201_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type create_edge_definition_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.create_edge_definition_202_json_resp_graph()
        }

  @type create_edge_definition_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.create_edge_definition_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type create_edge_definition_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type create_edge_definition_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_edge_definition_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_edge_definition_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_edge_definition(
          database_name :: String.t(),
          graph :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_edge_definition(database_name, graph, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph, body: body],
      call: {Arangox.Api.Graphs, :create_edge_definition},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :create_edge_definition_201_json_resp}},
        {202, {Arangox.Api.Graphs, :create_edge_definition_202_json_resp}},
        {400, {Arangox.Api.Graphs, :create_edge_definition_400_json_resp}},
        {403, {Arangox.Api.Graphs, :create_edge_definition_403_json_resp}},
        {404, {Arangox.Api.Graphs, :create_edge_definition_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_graph_201_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.create_graph_201_json_resp_graph()
        }

  @type create_graph_201_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.create_graph_201_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type create_graph_201_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type create_graph_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.create_graph_202_json_resp_graph()
        }

  @type create_graph_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.create_graph_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type create_graph_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type create_graph_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_graph_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_graph_409_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a graph

  The creation of a graph requires the name of the graph and a
  definition of its edges.

  ## Options

    * `waitForSync`: Define if the request should wait until everything is synced to disk.
      Changes the success HTTP response status code.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_graph(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_graph(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:waitForSync])

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Graphs, :create_graph},
      url: "/_db/#{database_name}/_api/gharial",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :create_graph_201_json_resp}},
        {202, {Arangox.Api.Graphs, :create_graph_202_json_resp}},
        {400, {Arangox.Api.Graphs, :create_graph_400_json_resp}},
        {403, {Arangox.Api.Graphs, :create_graph_403_json_resp}},
        {409, {Arangox.Api.Graphs, :create_graph_409_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_vertex_201_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.create_vertex_201_json_resp_new() | nil,
          vertex: Arangox.Api.Graphs.create_vertex_201_json_resp_vertex()
        }

  @type create_vertex_201_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type create_vertex_201_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type create_vertex_202_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.create_vertex_202_json_resp_new() | nil,
          vertex: Arangox.Api.Graphs.create_vertex_202_json_resp_vertex()
        }

  @type create_vertex_202_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type create_vertex_202_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type create_vertex_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_vertex_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_vertex_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a node

  Adds a node to the given collection.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_vertex(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_vertex(database_name, graph, collection, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:returnNew, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, body: body],
      call: {Arangox.Api.Graphs, :create_vertex},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}",
      body: body,
      method: :post,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :create_vertex_201_json_resp}},
        {202, {Arangox.Api.Graphs, :create_vertex_202_json_resp}},
        {403, {Arangox.Api.Graphs, :create_vertex_403_json_resp}},
        {404, {Arangox.Api.Graphs, :create_vertex_404_json_resp}},
        {410, {Arangox.Api.Graphs, :create_vertex_410_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_edge_200_json_resp :: %{
          code: integer,
          error: boolean,
          old: Arangox.Api.Graphs.delete_edge_200_json_resp_old() | nil,
          removed: boolean
        }

  @type delete_edge_200_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type delete_edge_202_json_resp :: %{
          code: integer,
          error: boolean,
          old: Arangox.Api.Graphs.delete_edge_202_json_resp_old() | nil,
          removed: boolean
        }

  @type delete_edge_202_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type delete_edge_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_edge_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_edge_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_edge_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Remove an edge

  Removes an edge from an edge collection of the named graph. Any other edges
  that directly reference this edge like a node are removed, too.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      

  """
  @spec delete_edge(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          edge :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_edge(database_name, graph, collection, edge, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:returnOld, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, edge: edge],
      call: {Arangox.Api.Graphs, :delete_edge},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}/#{edge}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Graphs, :delete_edge_200_json_resp}},
        {202, {Arangox.Api.Graphs, :delete_edge_202_json_resp}},
        {403, {Arangox.Api.Graphs, :delete_edge_403_json_resp}},
        {404, {Arangox.Api.Graphs, :delete_edge_404_json_resp}},
        {410, {Arangox.Api.Graphs, :delete_edge_410_json_resp}},
        {412, {Arangox.Api.Graphs, :delete_edge_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_edge_definition_201_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.delete_edge_definition_201_json_resp_graph()
        }

  @type delete_edge_definition_201_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.delete_edge_definition_201_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type delete_edge_definition_201_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type delete_edge_definition_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.delete_edge_definition_202_json_resp_graph()
        }

  @type delete_edge_definition_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.delete_edge_definition_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type delete_edge_definition_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type delete_edge_definition_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_edge_definition_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Remove an edge definition

  Remove one edge definition from the graph. This only removes the
  edge collection from the graph definition. The node collections of the
  edge definition become orphan collections but otherwise remain untouched
  and can still be used in your queries.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `dropCollections`: Drop the edge collection in addition to removing it from the graph.
      The collection is only dropped if it is not used in other graphs.
      

  """
  @spec delete_edge_definition(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_edge_definition(database_name, graph, collection, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:dropCollections, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection],
      call: {Arangox.Api.Graphs, :delete_edge_definition},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}",
      method: :delete,
      query: query,
      response: [
        {201, {Arangox.Api.Graphs, :delete_edge_definition_201_json_resp}},
        {202, {Arangox.Api.Graphs, :delete_edge_definition_202_json_resp}},
        {403, {Arangox.Api.Graphs, :delete_edge_definition_403_json_resp}},
        {404, {Arangox.Api.Graphs, :delete_edge_definition_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_graph_202_json_resp :: %{code: integer, error: boolean, removed: boolean}

  @type delete_graph_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_graph_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Drop a graph

  Drops an existing graph object by name.
  Optionally all collections not used by other graphs
  can be dropped as well.

  ## Options

    * `dropCollections`: Drop the collections of this graph as well. Collections are only
      dropped if they are not used in other graphs.
      

  """
  @spec delete_graph(database_name :: String.t(), graph :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_graph(database_name, graph, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:dropCollections])

    client.request(%{
      args: [database_name: database_name, graph: graph],
      call: {Arangox.Api.Graphs, :delete_graph},
      url: "/_db/#{database_name}/_api/gharial/#{graph}",
      method: :delete,
      query: query,
      response: [
        {202, {Arangox.Api.Graphs, :delete_graph_202_json_resp}},
        {403, {Arangox.Api.Graphs, :delete_graph_403_json_resp}},
        {404, {Arangox.Api.Graphs, :delete_graph_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_vertex_200_json_resp :: %{
          code: integer,
          error: boolean,
          old: Arangox.Api.Graphs.delete_vertex_200_json_resp_old() | nil,
          removed: boolean
        }

  @type delete_vertex_200_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type delete_vertex_202_json_resp :: %{
          code: integer,
          error: boolean,
          old: Arangox.Api.Graphs.delete_vertex_202_json_resp_old() | nil,
          removed: boolean
        }

  @type delete_vertex_202_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type delete_vertex_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_vertex_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_vertex_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_vertex_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Remove a node

  Removes a node from a collection of the named graph. Additionally removes all
  incoming and outgoing edges of the node.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      

  """
  @spec delete_vertex(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          vertex :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_vertex(database_name, graph, collection, vertex, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:returnOld, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, vertex: vertex],
      call: {Arangox.Api.Graphs, :delete_vertex},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}/#{vertex}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Graphs, :delete_vertex_200_json_resp}},
        {202, {Arangox.Api.Graphs, :delete_vertex_202_json_resp}},
        {403, {Arangox.Api.Graphs, :delete_vertex_403_json_resp}},
        {404, {Arangox.Api.Graphs, :delete_vertex_404_json_resp}},
        {410, {Arangox.Api.Graphs, :delete_vertex_410_json_resp}},
        {412, {Arangox.Api.Graphs, :delete_vertex_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_vertex_collection_200_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.delete_vertex_collection_200_json_resp_graph()
        }

  @type delete_vertex_collection_200_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.delete_vertex_collection_200_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type delete_vertex_collection_200_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type delete_vertex_collection_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.delete_vertex_collection_202_json_resp_graph()
        }

  @type delete_vertex_collection_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.delete_vertex_collection_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type delete_vertex_collection_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type delete_vertex_collection_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_vertex_collection_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_vertex_collection_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Remove a node collection

  Removes a node collection from the list of the graph's
  orphan collections. It can optionally delete the collection if it is
  not used in any other graph.

  You cannot remove node collections that are used in one of the
  edge definitions of the graph. You need to modify or remove the
  edge definition first in order to fully remove a node collection from
  the graph.

  ## Options

    * `dropCollection`: Drop the collection in addition to removing it from the graph.
      The collection is only dropped if it is not used in other graphs.
      

  """
  @spec delete_vertex_collection(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_vertex_collection(database_name, graph, collection, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:dropCollection])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection],
      call: {Arangox.Api.Graphs, :delete_vertex_collection},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}",
      method: :delete,
      query: query,
      response: [
        {200, {Arangox.Api.Graphs, :delete_vertex_collection_200_json_resp}},
        {202, {Arangox.Api.Graphs, :delete_vertex_collection_202_json_resp}},
        {400, {Arangox.Api.Graphs, :delete_vertex_collection_400_json_resp}},
        {403, {Arangox.Api.Graphs, :delete_vertex_collection_403_json_resp}},
        {404, {Arangox.Api.Graphs, :delete_vertex_collection_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_edge_200_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.get_edge_200_json_resp_edge(),
          error: boolean
        }

  @type get_edge_200_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type get_edge_304_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_edge_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_edge_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_edge_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_edge_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get an edge

  Gets an edge from the given collection.

  """
  @spec get_edge(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          edge :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_edge(database_name, graph, collection, edge, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, edge: edge],
      call: {Arangox.Api.Graphs, :get_edge},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}/#{edge}",
      method: :get,
      response: [
        {200, {Arangox.Api.Graphs, :get_edge_200_json_resp}},
        {304, {Arangox.Api.Graphs, :get_edge_304_json_resp}},
        {403, {Arangox.Api.Graphs, :get_edge_403_json_resp}},
        {404, {Arangox.Api.Graphs, :get_edge_404_json_resp}},
        {410, {Arangox.Api.Graphs, :get_edge_410_json_resp}},
        {412, {Arangox.Api.Graphs, :get_edge_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_graph_200_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.get_graph_200_json_resp_graph()
        }

  @type get_graph_200_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [Arangox.Api.Graphs.get_graph_200_json_resp_graph_edge_definitions()],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type get_graph_200_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type get_graph_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get a graph

  Selects information for a given graph.
  Returns the edge definitions as well as the orphan collections,
  or returns an error if the graph does not exist.

  """
  @spec get_graph(database_name :: String.t(), graph :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_graph(database_name, graph, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph],
      call: {Arangox.Api.Graphs, :get_graph},
      url: "/_db/#{database_name}/_api/gharial/#{graph}",
      method: :get,
      response: [
        {200, {Arangox.Api.Graphs, :get_graph_200_json_resp}},
        {404, {Arangox.Api.Graphs, :get_graph_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_vertex_200_json_resp :: %{
          code: integer,
          error: boolean,
          vertex: Arangox.Api.Graphs.get_vertex_200_json_resp_vertex()
        }

  @type get_vertex_200_json_resp_vertex :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type get_vertex_304_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_vertex_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_vertex_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_vertex_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_vertex_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get a node

  Gets a node from the given collection.

  """
  @spec get_vertex(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          vertex :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_vertex(database_name, graph, collection, vertex, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, vertex: vertex],
      call: {Arangox.Api.Graphs, :get_vertex},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}/#{vertex}",
      method: :get,
      response: [
        {200, {Arangox.Api.Graphs, :get_vertex_200_json_resp}},
        {304, {Arangox.Api.Graphs, :get_vertex_304_json_resp}},
        {403, {Arangox.Api.Graphs, :get_vertex_403_json_resp}},
        {404, {Arangox.Api.Graphs, :get_vertex_404_json_resp}},
        {410, {Arangox.Api.Graphs, :get_vertex_410_json_resp}},
        {412, {Arangox.Api.Graphs, :get_vertex_412_json_resp}}
      ],
      opts: opts
    })
  end

  @doc """
  Get inbound and outbound edges

  Returns an array of edges starting or ending in the node identified by
  `vertex`.

  ## Options

    * `vertex`: The document identifier of the start node.
      
    * `direction`: - `"in"`: Return edges that reference the `vertex` in the `_to` attribute.
      - `"out"`: Return edges that reference the `vertex` in the `_from` attribute.
      - `"any"`: Return edges that reference the `vertex` in the `_from` or `_to` attribute.
      

  """
  @spec get_vertex_edges(database_name :: String.t(), collection :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_vertex_edges(database_name, collection, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:direction, :vertex])

    client.request(%{
      args: [database_name: database_name, collection: collection],
      call: {Arangox.Api.Graphs, :get_vertex_edges},
      url: "/_db/#{database_name}/_api/edges/#{collection}",
      method: :get,
      query: query,
      response: [{200, :null}, {400, :null}, {404, :null}],
      opts: opts
    })
  end

  @type list_edge_collections_200_json_resp :: %{
          code: integer,
          collections: [String.t()],
          error: boolean
        }

  @type list_edge_collections_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  List edge collections

  Lists all edge collections within this graph.

  """
  @spec list_edge_collections(database_name :: String.t(), graph :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_edge_collections(database_name, graph, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph],
      call: {Arangox.Api.Graphs, :list_edge_collections},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge",
      method: :get,
      response: [
        {200, {Arangox.Api.Graphs, :list_edge_collections_200_json_resp}},
        {404, {Arangox.Api.Graphs, :list_edge_collections_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_graphs_200_json_resp :: %{
          code: integer,
          error: boolean,
          graphs: [Arangox.Api.Graphs.list_graphs_200_json_resp_graphs()]
        }

  @type list_graphs_200_json_resp_graphs :: %{
          graph: Arangox.Api.Graphs.list_graphs_200_json_resp_graphs_graph() | nil
        }

  @type list_graphs_200_json_resp_graphs_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.list_graphs_200_json_resp_graphs_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type list_graphs_200_json_resp_graphs_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @doc """
  List all graphs

  Lists all graphs stored in this database.

  """
  @spec list_graphs(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_graphs(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Graphs, :list_graphs},
      url: "/_db/#{database_name}/_api/gharial",
      method: :get,
      response: [{200, {Arangox.Api.Graphs, :list_graphs_200_json_resp}}],
      opts: opts
    })
  end

  @type list_vertex_collections_200_json_resp :: %{
          code: integer,
          collections: [String.t()],
          error: boolean
        }

  @type list_vertex_collections_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  List node collections

  Lists all node collections within this graph, including orphan collections.

  """
  @spec list_vertex_collections(database_name :: String.t(), graph :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_vertex_collections(database_name, graph, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, graph: graph],
      call: {Arangox.Api.Graphs, :list_vertex_collections},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex",
      method: :get,
      response: [
        {200, {Arangox.Api.Graphs, :list_vertex_collections_200_json_resp}},
        {404, {Arangox.Api.Graphs, :list_vertex_collections_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type replace_edge_201_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.replace_edge_201_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.replace_edge_201_json_resp_new() | nil,
          old: Arangox.Api.Graphs.replace_edge_201_json_resp_old() | nil
        }

  @type replace_edge_201_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_201_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_201_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_202_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.replace_edge_202_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.replace_edge_202_json_resp_new() | nil,
          old: Arangox.Api.Graphs.replace_edge_202_json_resp_old() | nil
        }

  @type replace_edge_202_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_202_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_202_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type replace_edge_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_edge_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_edge_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_edge_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Replace an edge

  Replaces the data of an edge in the collection.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `keepNull`: Define if values set to `null` should be stored.
      By default (`true`), the given documents attribute(s) are set to `null`.
      If this parameter is set to `false`, top-level attribute and sub-attributes with
      a `null` value in the request are removed from the document (but not attributes
      of objects that are nested inside of arrays).
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_edge(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          edge :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_edge(database_name, graph, collection, edge, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:keepNull, :returnNew, :returnOld, :waitForSync])

    client.request(%{
      args: [
        database_name: database_name,
        graph: graph,
        collection: collection,
        edge: edge,
        body: body
      ],
      call: {Arangox.Api.Graphs, :replace_edge},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}/#{edge}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :replace_edge_201_json_resp}},
        {202, {Arangox.Api.Graphs, :replace_edge_202_json_resp}},
        {403, {Arangox.Api.Graphs, :replace_edge_403_json_resp}},
        {404, {Arangox.Api.Graphs, :replace_edge_404_json_resp}},
        {410, {Arangox.Api.Graphs, :replace_edge_410_json_resp}},
        {412, {Arangox.Api.Graphs, :replace_edge_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type replace_edge_definition_201_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.replace_edge_definition_201_json_resp_graph()
        }

  @type replace_edge_definition_201_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.replace_edge_definition_201_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type replace_edge_definition_201_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type replace_edge_definition_202_json_resp :: %{
          code: integer,
          error: boolean,
          graph: Arangox.Api.Graphs.replace_edge_definition_202_json_resp_graph()
        }

  @type replace_edge_definition_202_json_resp_graph :: %{
          _id: String.t(),
          _rev: String.t(),
          edgeDefinitions: [
            Arangox.Api.Graphs.replace_edge_definition_202_json_resp_graph_edge_definitions()
          ],
          isDisjoint: boolean,
          isSatellite: boolean,
          isSmart: boolean,
          name: String.t(),
          numberOfShards: integer,
          orphanCollections: [String.t()],
          replicationFactor: integer,
          smartGraphAttribute: String.t() | nil,
          writeConcern: integer | nil
        }

  @type replace_edge_definition_202_json_resp_graph_edge_definitions :: %{
          collection: String.t(),
          from: [String.t()],
          to: [String.t()]
        }

  @type replace_edge_definition_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_edge_definition_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_edge_definition_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Replace an edge definition

  Change the node collections of one specific edge definition.
  This modifies all occurrences of this definition in all graphs known to your database.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `dropCollections`: Drop the edge collection in addition to removing it from the graph.
      The collection is only dropped if it is not used in other graphs.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_edge_definition(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_edge_definition(database_name, graph, collection, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:dropCollections, :waitForSync])

    client.request(%{
      args: [database_name: database_name, graph: graph, collection: collection, body: body],
      call: {Arangox.Api.Graphs, :replace_edge_definition},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Graphs, :replace_edge_definition_201_json_resp}},
        {202, {Arangox.Api.Graphs, :replace_edge_definition_202_json_resp}},
        {400, {Arangox.Api.Graphs, :replace_edge_definition_400_json_resp}},
        {403, {Arangox.Api.Graphs, :replace_edge_definition_403_json_resp}},
        {404, {Arangox.Api.Graphs, :replace_edge_definition_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type replace_vertex_200_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.replace_vertex_200_json_resp_new() | nil,
          old: Arangox.Api.Graphs.replace_vertex_200_json_resp_old() | nil,
          vertex: Arangox.Api.Graphs.replace_vertex_200_json_resp_vertex()
        }

  @type replace_vertex_200_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type replace_vertex_200_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type replace_vertex_200_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type replace_vertex_202_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.replace_vertex_202_json_resp_new() | nil,
          old: Arangox.Api.Graphs.replace_vertex_202_json_resp_old() | nil,
          vertex: Arangox.Api.Graphs.replace_vertex_202_json_resp_vertex()
        }

  @type replace_vertex_202_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type replace_vertex_202_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type replace_vertex_202_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type replace_vertex_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_vertex_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_vertex_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_vertex_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Replace a node

  Replaces the data of a node in the collection.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `keepNull`: Define if values set to `null` should be stored.
      By default (`true`), the given documents attribute(s) are set to `null`.
      If this parameter is set to `false`, top-level attribute and sub-attributes with
      a `null` value in the request are removed from the document (but not attributes
      of objects that are nested inside of arrays).
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_vertex(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          vertex :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_vertex(database_name, graph, collection, vertex, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:keepNull, :returnNew, :returnOld, :waitForSync])

    client.request(%{
      args: [
        database_name: database_name,
        graph: graph,
        collection: collection,
        vertex: vertex,
        body: body
      ],
      call: {Arangox.Api.Graphs, :replace_vertex},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}/#{vertex}",
      body: body,
      method: :put,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Graphs, :replace_vertex_200_json_resp}},
        {202, {Arangox.Api.Graphs, :replace_vertex_202_json_resp}},
        {403, {Arangox.Api.Graphs, :replace_vertex_403_json_resp}},
        {404, {Arangox.Api.Graphs, :replace_vertex_404_json_resp}},
        {410, {Arangox.Api.Graphs, :replace_vertex_410_json_resp}},
        {412, {Arangox.Api.Graphs, :replace_vertex_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type update_edge_200_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.update_edge_200_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.update_edge_200_json_resp_new() | nil,
          old: Arangox.Api.Graphs.update_edge_200_json_resp_old() | nil
        }

  @type update_edge_200_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_200_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_200_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_202_json_resp :: %{
          code: integer,
          edge: Arangox.Api.Graphs.update_edge_202_json_resp_edge(),
          error: boolean,
          new: Arangox.Api.Graphs.update_edge_202_json_resp_new() | nil,
          old: Arangox.Api.Graphs.update_edge_202_json_resp_old() | nil
        }

  @type update_edge_202_json_resp_edge :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_202_json_resp_new :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_202_json_resp_old :: %{
          _from: String.t(),
          _id: String.t(),
          _key: String.t(),
          _rev: String.t(),
          _to: String.t()
        }

  @type update_edge_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_edge_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_edge_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_edge_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Update an edge

  Partially modify the data of the specific edge in the collection.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `keepNull`: Define if values set to `null` should be stored.
      By default (`true`), the given documents attribute(s) are set to `null`.
      If this parameter is set to `false`, top-level attribute and sub-attributes with
      a `null` value in the request are removed from the document (but not attributes
      of objects that are nested inside of arrays).
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_edge(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          edge :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_edge(database_name, graph, collection, edge, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:keepNull, :returnNew, :returnOld, :waitForSync])

    client.request(%{
      args: [
        database_name: database_name,
        graph: graph,
        collection: collection,
        edge: edge,
        body: body
      ],
      call: {Arangox.Api.Graphs, :update_edge},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/edge/#{collection}/#{edge}",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Graphs, :update_edge_200_json_resp}},
        {202, {Arangox.Api.Graphs, :update_edge_202_json_resp}},
        {403, {Arangox.Api.Graphs, :update_edge_403_json_resp}},
        {404, {Arangox.Api.Graphs, :update_edge_404_json_resp}},
        {410, {Arangox.Api.Graphs, :update_edge_410_json_resp}},
        {412, {Arangox.Api.Graphs, :update_edge_412_json_resp}}
      ],
      opts: opts
    })
  end

  @type update_vertex_200_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.update_vertex_200_json_resp_new() | nil,
          old: Arangox.Api.Graphs.update_vertex_200_json_resp_old() | nil,
          vertex: Arangox.Api.Graphs.update_vertex_200_json_resp_vertex()
        }

  @type update_vertex_200_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type update_vertex_200_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type update_vertex_200_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type update_vertex_202_json_resp :: %{
          code: integer,
          error: boolean,
          new: Arangox.Api.Graphs.update_vertex_202_json_resp_new() | nil,
          old: Arangox.Api.Graphs.update_vertex_202_json_resp_old() | nil,
          vertex: Arangox.Api.Graphs.update_vertex_202_json_resp_vertex()
        }

  @type update_vertex_202_json_resp_new :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type update_vertex_202_json_resp_old :: %{_id: String.t(), _key: String.t(), _rev: String.t()}

  @type update_vertex_202_json_resp_vertex :: %{
          _id: String.t(),
          _key: String.t(),
          _rev: String.t()
        }

  @type update_vertex_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_vertex_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_vertex_410_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_vertex_412_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Update a node

  Updates the data of the specific node in the collection.

  ## Options

    * `waitForSync`: Define if the request should wait until synced to disk.
      
    * `keepNull`: Define if values set to `null` should be stored.
      By default (`true`), the given documents attribute(s) are set to `null`.
      If this parameter is set to `false`, top-level attribute and sub-attributes with
      a `null` value in the request are removed from the document (but not attributes
      of objects that are nested inside of arrays).
      
    * `returnOld`: Whether to additionally include the complete previous document under the
      `old` attribute in the result.
      
    * `returnNew`: Whether to additionally include the complete new document under the
      `new` attribute in the result.
      

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_vertex(
          database_name :: String.t(),
          graph :: String.t(),
          collection :: String.t(),
          vertex :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_vertex(database_name, graph, collection, vertex, body, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:keepNull, :returnNew, :returnOld, :waitForSync])

    client.request(%{
      args: [
        database_name: database_name,
        graph: graph,
        collection: collection,
        vertex: vertex,
        body: body
      ],
      call: {Arangox.Api.Graphs, :update_vertex},
      url: "/_db/#{database_name}/_api/gharial/#{graph}/vertex/#{collection}/#{vertex}",
      body: body,
      method: :patch,
      query: query,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Graphs, :update_vertex_200_json_resp}},
        {202, {Arangox.Api.Graphs, :update_vertex_202_json_resp}},
        {403, {Arangox.Api.Graphs, :update_vertex_403_json_resp}},
        {404, {Arangox.Api.Graphs, :update_vertex_404_json_resp}},
        {410, {Arangox.Api.Graphs, :update_vertex_410_json_resp}},
        {412, {Arangox.Api.Graphs, :update_vertex_412_json_resp}}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:add_vertex_collection_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :add_vertex_collection_201_json_resp_graph}
    ]
  end

  def __fields__(:add_vertex_collection_201_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :add_vertex_collection_201_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:add_vertex_collection_201_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:add_vertex_collection_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :add_vertex_collection_202_json_resp_graph}
    ]
  end

  def __fields__(:add_vertex_collection_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :add_vertex_collection_202_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:add_vertex_collection_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:add_vertex_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:add_vertex_collection_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:add_vertex_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_201_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :create_edge_201_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :create_edge_201_json_resp_new}
    ]
  end

  def __fields__(:create_edge_201_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:create_edge_201_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:create_edge_202_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :create_edge_202_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :create_edge_202_json_resp_new}
    ]
  end

  def __fields__(:create_edge_202_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:create_edge_202_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:create_edge_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_definition_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :create_edge_definition_201_json_resp_graph}
    ]
  end

  def __fields__(:create_edge_definition_201_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :create_edge_definition_201_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:create_edge_definition_201_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:create_edge_definition_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :create_edge_definition_202_json_resp_graph}
    ]
  end

  def __fields__(:create_edge_definition_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :create_edge_definition_202_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:create_edge_definition_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:create_edge_definition_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_definition_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_edge_definition_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_graph_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :create_graph_201_json_resp_graph}
    ]
  end

  def __fields__(:create_graph_201_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [{Arangox.Api.Graphs, :create_graph_201_json_resp_graph_edge_definitions}],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:create_graph_201_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:create_graph_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :create_graph_202_json_resp_graph}
    ]
  end

  def __fields__(:create_graph_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [{Arangox.Api.Graphs, :create_graph_202_json_resp_graph_edge_definitions}],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:create_graph_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:create_graph_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_graph_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_graph_409_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_vertex_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :create_vertex_201_json_resp_new},
      vertex: {Arangox.Api.Graphs, :create_vertex_201_json_resp_vertex}
    ]
  end

  def __fields__(:create_vertex_201_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:create_vertex_201_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:create_vertex_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :create_vertex_202_json_resp_new},
      vertex: {Arangox.Api.Graphs, :create_vertex_202_json_resp_vertex}
    ]
  end

  def __fields__(:create_vertex_202_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:create_vertex_202_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:create_vertex_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_vertex_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_vertex_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      old: {Arangox.Api.Graphs, :delete_edge_200_json_resp_old},
      removed: :boolean
    ]
  end

  def __fields__(:delete_edge_200_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:delete_edge_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      old: {Arangox.Api.Graphs, :delete_edge_202_json_resp_old},
      removed: :boolean
    ]
  end

  def __fields__(:delete_edge_202_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:delete_edge_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_definition_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :delete_edge_definition_201_json_resp_graph}
    ]
  end

  def __fields__(:delete_edge_definition_201_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :delete_edge_definition_201_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:delete_edge_definition_201_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:delete_edge_definition_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :delete_edge_definition_202_json_resp_graph}
    ]
  end

  def __fields__(:delete_edge_definition_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :delete_edge_definition_202_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:delete_edge_definition_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:delete_edge_definition_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_edge_definition_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_graph_202_json_resp) do
    [code: :integer, error: :boolean, removed: :boolean]
  end

  def __fields__(:delete_graph_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_graph_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      old: {Arangox.Api.Graphs, :delete_vertex_200_json_resp_old},
      removed: :boolean
    ]
  end

  def __fields__(:delete_vertex_200_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:delete_vertex_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      old: {Arangox.Api.Graphs, :delete_vertex_202_json_resp_old},
      removed: :boolean
    ]
  end

  def __fields__(:delete_vertex_202_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:delete_vertex_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_collection_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :delete_vertex_collection_200_json_resp_graph}
    ]
  end

  def __fields__(:delete_vertex_collection_200_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :delete_vertex_collection_200_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:delete_vertex_collection_200_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:delete_vertex_collection_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :delete_vertex_collection_202_json_resp_graph}
    ]
  end

  def __fields__(:delete_vertex_collection_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :delete_vertex_collection_202_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:delete_vertex_collection_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:delete_vertex_collection_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_collection_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_vertex_collection_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_edge_200_json_resp) do
    [code: :integer, edge: {Arangox.Api.Graphs, :get_edge_200_json_resp_edge}, error: :boolean]
  end

  def __fields__(:get_edge_200_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:get_edge_304_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_edge_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_edge_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_edge_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_edge_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_graph_200_json_resp) do
    [code: :integer, error: :boolean, graph: {Arangox.Api.Graphs, :get_graph_200_json_resp_graph}]
  end

  def __fields__(:get_graph_200_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [{Arangox.Api.Graphs, :get_graph_200_json_resp_graph_edge_definitions}],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:get_graph_200_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:get_graph_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_vertex_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      vertex: {Arangox.Api.Graphs, :get_vertex_200_json_resp_vertex}
    ]
  end

  def __fields__(:get_vertex_200_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:get_vertex_304_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_vertex_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_vertex_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_vertex_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_vertex_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_edge_collections_200_json_resp) do
    [code: :integer, collections: [:string], error: :boolean]
  end

  def __fields__(:list_edge_collections_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_graphs_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graphs: [{Arangox.Api.Graphs, :list_graphs_200_json_resp_graphs}]
    ]
  end

  def __fields__(:list_graphs_200_json_resp_graphs) do
    [graph: {Arangox.Api.Graphs, :list_graphs_200_json_resp_graphs_graph}]
  end

  def __fields__(:list_graphs_200_json_resp_graphs_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :list_graphs_200_json_resp_graphs_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:list_graphs_200_json_resp_graphs_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:list_vertex_collections_200_json_resp) do
    [code: :integer, collections: [:string], error: :boolean]
  end

  def __fields__(:list_vertex_collections_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_201_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :replace_edge_201_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :replace_edge_201_json_resp_new},
      old: {Arangox.Api.Graphs, :replace_edge_201_json_resp_old}
    ]
  end

  def __fields__(:replace_edge_201_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_201_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_201_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_202_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :replace_edge_202_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :replace_edge_202_json_resp_new},
      old: {Arangox.Api.Graphs, :replace_edge_202_json_resp_old}
    ]
  end

  def __fields__(:replace_edge_202_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_202_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_202_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:replace_edge_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_definition_201_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :replace_edge_definition_201_json_resp_graph}
    ]
  end

  def __fields__(:replace_edge_definition_201_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :replace_edge_definition_201_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:replace_edge_definition_201_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:replace_edge_definition_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      graph: {Arangox.Api.Graphs, :replace_edge_definition_202_json_resp_graph}
    ]
  end

  def __fields__(:replace_edge_definition_202_json_resp_graph) do
    [
      _id: :string,
      _rev: :string,
      edgeDefinitions: [
        {Arangox.Api.Graphs, :replace_edge_definition_202_json_resp_graph_edge_definitions}
      ],
      isDisjoint: :boolean,
      isSatellite: :boolean,
      isSmart: :boolean,
      name: :string,
      numberOfShards: :integer,
      orphanCollections: [:string],
      replicationFactor: :integer,
      smartGraphAttribute: :string,
      writeConcern: :integer
    ]
  end

  def __fields__(:replace_edge_definition_202_json_resp_graph_edge_definitions) do
    [collection: :string, from: [:string], to: [:string]]
  end

  def __fields__(:replace_edge_definition_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_definition_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_edge_definition_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_vertex_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :replace_vertex_200_json_resp_new},
      old: {Arangox.Api.Graphs, :replace_vertex_200_json_resp_old},
      vertex: {Arangox.Api.Graphs, :replace_vertex_200_json_resp_vertex}
    ]
  end

  def __fields__(:replace_vertex_200_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_200_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_200_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :replace_vertex_202_json_resp_new},
      old: {Arangox.Api.Graphs, :replace_vertex_202_json_resp_old},
      vertex: {Arangox.Api.Graphs, :replace_vertex_202_json_resp_vertex}
    ]
  end

  def __fields__(:replace_vertex_202_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_202_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_202_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:replace_vertex_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_vertex_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_vertex_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_vertex_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_edge_200_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :update_edge_200_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :update_edge_200_json_resp_new},
      old: {Arangox.Api.Graphs, :update_edge_200_json_resp_old}
    ]
  end

  def __fields__(:update_edge_200_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_200_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_200_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_202_json_resp) do
    [
      code: :integer,
      edge: {Arangox.Api.Graphs, :update_edge_202_json_resp_edge},
      error: :boolean,
      new: {Arangox.Api.Graphs, :update_edge_202_json_resp_new},
      old: {Arangox.Api.Graphs, :update_edge_202_json_resp_old}
    ]
  end

  def __fields__(:update_edge_202_json_resp_edge) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_202_json_resp_new) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_202_json_resp_old) do
    [_from: :string, _id: :string, _key: :string, _rev: :string, _to: :string]
  end

  def __fields__(:update_edge_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_edge_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_edge_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_edge_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_vertex_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :update_vertex_200_json_resp_new},
      old: {Arangox.Api.Graphs, :update_vertex_200_json_resp_old},
      vertex: {Arangox.Api.Graphs, :update_vertex_200_json_resp_vertex}
    ]
  end

  def __fields__(:update_vertex_200_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_200_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_200_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_202_json_resp) do
    [
      code: :integer,
      error: :boolean,
      new: {Arangox.Api.Graphs, :update_vertex_202_json_resp_new},
      old: {Arangox.Api.Graphs, :update_vertex_202_json_resp_old},
      vertex: {Arangox.Api.Graphs, :update_vertex_202_json_resp_vertex}
    ]
  end

  def __fields__(:update_vertex_202_json_resp_new) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_202_json_resp_old) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_202_json_resp_vertex) do
    [_id: :string, _key: :string, _rev: :string]
  end

  def __fields__(:update_vertex_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_vertex_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_vertex_410_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_vertex_412_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
