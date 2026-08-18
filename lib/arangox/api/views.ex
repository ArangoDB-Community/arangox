defmodule Arangox.Api.Views do
  @moduledoc """
  Provides API endpoints related to views
  """

  @default_client Arangox.Api.Client

  @type create_view_201_json_resp :: %{
          cleanupIntervalStep: integer,
          commitIntervalMsec: integer,
          consolidationIntervalMsec: integer,
          consolidationPolicy: Arangox.Api.Views.create_view_201_json_resp_consolidation_policy(),
          globallyUniqueId: String.t(),
          id: String.t(),
          links: map,
          name: String.t(),
          optimizeTopK: [String.t()],
          primaryKeyCache: boolean | nil,
          primarySort: [Arangox.Api.Views.create_view_201_json_resp_primary_sort()],
          primarySortCache: boolean | nil,
          primarySortCompression: String.t(),
          storedValues: [Arangox.Api.Views.create_view_201_json_resp_stored_values()],
          type: String.t(),
          writebufferActive: integer,
          writebufferIdle: integer,
          writebufferSizeMax: integer
        }

  @type create_view_201_json_resp_consolidation_policy :: %{
          maxSkewThreshold: number | nil,
          minDeletionRatio: number | nil,
          minScore: integer | nil,
          segmentsBytesFloor: integer | nil,
          segmentsBytesMax: integer | nil,
          segmentsMax: integer | nil,
          segmentsMin: integer | nil,
          threshold: number | nil,
          type: String.t() | nil
        }

  @type create_view_201_json_resp_primary_sort :: %{asc: boolean, field: String.t()}

  @type create_view_201_json_resp_stored_values :: %{
          cache: boolean | nil,
          compression: String.t() | nil,
          fields: [String.t()]
        }

  @type create_view_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_view_409_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create an arangosearch View

  Creates a new View with a given name and properties if it does not
  already exist.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_view(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_view(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Views, :create_view},
      url: "/_db/#{database_name}/_api/view",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Views, :create_view_201_json_resp}},
        {400, {Arangox.Api.Views, :create_view_400_json_resp}},
        {409, {Arangox.Api.Views, :create_view_409_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_view_search_alias_201_json_resp :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          indexes: [Arangox.Api.Views.create_view_search_alias_201_json_resp_indexes()],
          name: String.t(),
          type: String.t()
        }

  @type create_view_search_alias_201_json_resp_indexes :: %{
          collection: String.t(),
          index: String.t()
        }

  @type create_view_search_alias_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_view_search_alias_409_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create a search-alias View

  Creates a new View with a given name and properties if it does not
  already exist.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_view_search_alias(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_view_search_alias(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Views, :create_view_search_alias},
      url: "/_db/#{database_name}/_api/view",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {201, {Arangox.Api.Views, :create_view_search_alias_201_json_resp}},
        {400, {Arangox.Api.Views, :create_view_search_alias_400_json_resp}},
        {409, {Arangox.Api.Views, :create_view_search_alias_409_json_resp}}
      ],
      opts: opts
    })
  end

  @type delete_view_200_json_resp :: %{code: integer, error: boolean, result: boolean}

  @type delete_view_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_view_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Drop a View

  Deletes the View identified by `view-name`.

  """
  @spec delete_view(database_name :: String.t(), view_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_view(database_name, view_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name],
      call: {Arangox.Api.Views, :delete_view},
      url: "/_db/#{database_name}/_api/view/#{view_name}",
      method: :delete,
      response: [
        {200, {Arangox.Api.Views, :delete_view_200_json_resp}},
        {400, {Arangox.Api.Views, :delete_view_400_json_resp}},
        {404, {Arangox.Api.Views, :delete_view_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_view_200_json_resp :: %{
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          name: String.t(),
          type: String.t()
        }

  @type get_view_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get information about a View

  Returns the basic information about a specific View.

  """
  @spec get_view(database_name :: String.t(), view_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_view(database_name, view_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name],
      call: {Arangox.Api.Views, :get_view},
      url: "/_db/#{database_name}/_api/view/#{view_name}",
      method: :get,
      response: [
        {200, {Arangox.Api.Views, :get_view_200_json_resp}},
        {404, {Arangox.Api.Views, :get_view_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_view_properties_200_json_resp :: %{
          cleanupIntervalStep: integer,
          code: integer,
          commitIntervalMsec: integer,
          consolidationIntervalMsec: integer,
          consolidationPolicy:
            Arangox.Api.Views.get_view_properties_200_json_resp_consolidation_policy(),
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          links: map,
          name: String.t(),
          optimizeTopK: [String.t()],
          primaryKeyCache: boolean | nil,
          primarySort: [Arangox.Api.Views.get_view_properties_200_json_resp_primary_sort()],
          primarySortCache: boolean | nil,
          primarySortCompression: String.t(),
          storedValues: [Arangox.Api.Views.get_view_properties_200_json_resp_stored_values()],
          type: String.t(),
          writebufferActive: integer,
          writebufferIdle: integer,
          writebufferSizeMax: integer
        }

  @type get_view_properties_200_json_resp_consolidation_policy :: %{
          maxSkewThreshold: number | nil,
          minDeletionRatio: number | nil,
          minScore: integer | nil,
          segmentsBytesFloor: integer | nil,
          segmentsBytesMax: integer | nil,
          segmentsMax: integer | nil,
          segmentsMin: integer | nil,
          threshold: number | nil,
          type: String.t() | nil
        }

  @type get_view_properties_200_json_resp_primary_sort :: %{asc: boolean, field: String.t()}

  @type get_view_properties_200_json_resp_stored_values :: %{
          cache: boolean | nil,
          compression: String.t() | nil,
          fields: [String.t()]
        }

  @type get_view_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_view_properties_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get the properties of a View

  Returns an object containing the definition of the View identified by `view-name`.

  """
  @spec get_view_properties(database_name :: String.t(), view_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_view_properties(database_name, view_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name],
      call: {Arangox.Api.Views, :get_view_properties},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      method: :get,
      response: [
        {200, {Arangox.Api.Views, :get_view_properties_200_json_resp}},
        {400, {Arangox.Api.Views, :get_view_properties_400_json_resp}},
        {404, {Arangox.Api.Views, :get_view_properties_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_view_properties_search_alias_200_json_resp :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          indexes: [Arangox.Api.Views.get_view_properties_search_alias_200_json_resp_indexes()],
          name: String.t(),
          type: String.t()
        }

  @type get_view_properties_search_alias_200_json_resp_indexes :: %{
          collection: String.t(),
          index: String.t()
        }

  @type get_view_properties_search_alias_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type get_view_properties_search_alias_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Read properties of a View

  Returns an object containing the definition of the View identified by `view-name`.

  """
  @spec get_view_properties_search_alias(
          database_name :: String.t(),
          view_name :: String.t(),
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_view_properties_search_alias(database_name, view_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name],
      call: {Arangox.Api.Views, :get_view_properties_search_alias},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      method: :get,
      response: [
        {200, {Arangox.Api.Views, :get_view_properties_search_alias_200_json_resp}},
        {400, {Arangox.Api.Views, :get_view_properties_search_alias_400_json_resp}},
        {404, {Arangox.Api.Views, :get_view_properties_search_alias_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_view_search_alias_200_json_resp :: %{
          code: integer,
          error: boolean,
          globallyUniqueId: String.t(),
          id: String.t(),
          name: String.t(),
          type: String.t()
        }

  @type get_view_search_alias_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Get information about a View

  Returns the basic information about a specific View.

  """
  @spec get_view_search_alias(database_name :: String.t(), view_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_view_search_alias(database_name, view_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name],
      call: {Arangox.Api.Views, :get_view_search_alias},
      url: "/_db/#{database_name}/_api/view/#{view_name}",
      method: :get,
      response: [
        {200, {Arangox.Api.Views, :get_view_search_alias_200_json_resp}},
        {404, {Arangox.Api.Views, :get_view_search_alias_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type list_views_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: [Arangox.Api.Views.list_views_200_json_resp_result()]
        }

  @type list_views_200_json_resp_result :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          name: String.t(),
          type: String.t()
        }

  @doc """
  List all Views

  Returns an object containing a listing of all Views in the current database,
  regardless of their type.

  """
  @spec list_views(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_views(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Views, :list_views},
      url: "/_db/#{database_name}/_api/view",
      method: :get,
      response: [{200, {Arangox.Api.Views, :list_views_200_json_resp}}],
      opts: opts
    })
  end

  @type rename_view_200_json_resp :: %{
          cleanupIntervalStep: integer,
          commitIntervalMsec: integer,
          consolidationIntervalMsec: integer,
          consolidationPolicy: Arangox.Api.Views.rename_view_200_json_resp_consolidation_policy(),
          globallyUniqueId: String.t(),
          id: String.t(),
          links: map,
          name: String.t(),
          optimizeTopK: [String.t()],
          primaryKeyCache: boolean | nil,
          primarySort: [Arangox.Api.Views.rename_view_200_json_resp_primary_sort()],
          primarySortCache: boolean | nil,
          primarySortCompression: String.t(),
          storedValues: [Arangox.Api.Views.rename_view_200_json_resp_stored_values()],
          type: String.t(),
          writebufferActive: integer,
          writebufferIdle: integer,
          writebufferSizeMax: integer
        }

  @type rename_view_200_json_resp_consolidation_policy :: %{
          maxSkewThreshold: number | nil,
          minDeletionRatio: number | nil,
          minScore: integer | nil,
          segmentsBytesFloor: integer | nil,
          segmentsBytesMax: integer | nil,
          segmentsMax: integer | nil,
          segmentsMin: integer | nil,
          threshold: number | nil,
          type: String.t() | nil
        }

  @type rename_view_200_json_resp_primary_sort :: %{asc: boolean, field: String.t()}

  @type rename_view_200_json_resp_stored_values :: %{
          cache: boolean | nil,
          compression: String.t() | nil,
          fields: [String.t()]
        }

  @type rename_view_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type rename_view_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Rename a View

  Renames a View.

  > **INFO:**
  Renaming Views is not supported in cluster deployments.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec rename_view(database_name :: String.t(), view_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def rename_view(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :rename_view},
      url: "/_db/#{database_name}/_api/view/#{view_name}/rename",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :rename_view_200_json_resp}},
        {400, {Arangox.Api.Views, :rename_view_400_json_resp}},
        {404, {Arangox.Api.Views, :rename_view_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type rename_view_search_alias_200_json_resp :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          indexes: [Arangox.Api.Views.rename_view_search_alias_200_json_resp_indexes()],
          name: String.t(),
          type: String.t()
        }

  @type rename_view_search_alias_200_json_resp_indexes :: %{
          collection: String.t(),
          index: String.t()
        }

  @type rename_view_search_alias_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type rename_view_search_alias_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Rename a View

  Renames a View.

  > **INFO:**
  Renaming Views is not supported in cluster deployments.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec rename_view_search_alias(
          database_name :: String.t(),
          view_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def rename_view_search_alias(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :rename_view_search_alias},
      url: "/_db/#{database_name}/_api/view/#{view_name}/rename",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :rename_view_search_alias_200_json_resp}},
        {400, {Arangox.Api.Views, :rename_view_search_alias_400_json_resp}},
        {404, {Arangox.Api.Views, :rename_view_search_alias_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type replace_view_properties_200_json_resp :: %{
          cleanupIntervalStep: integer,
          commitIntervalMsec: integer,
          consolidationIntervalMsec: integer,
          consolidationPolicy:
            Arangox.Api.Views.replace_view_properties_200_json_resp_consolidation_policy(),
          globallyUniqueId: String.t(),
          id: String.t(),
          links: map,
          name: String.t(),
          optimizeTopK: [String.t()],
          primaryKeyCache: boolean | nil,
          primarySort: [Arangox.Api.Views.replace_view_properties_200_json_resp_primary_sort()],
          primarySortCache: boolean | nil,
          primarySortCompression: String.t(),
          storedValues: [Arangox.Api.Views.replace_view_properties_200_json_resp_stored_values()],
          type: String.t(),
          writebufferActive: integer,
          writebufferIdle: integer,
          writebufferSizeMax: integer
        }

  @type replace_view_properties_200_json_resp_consolidation_policy :: %{
          maxSkewThreshold: number | nil,
          minDeletionRatio: number | nil,
          minScore: integer | nil,
          segmentsBytesFloor: integer | nil,
          segmentsBytesMax: integer | nil,
          segmentsMax: integer | nil,
          segmentsMin: integer | nil,
          threshold: number | nil,
          type: String.t() | nil
        }

  @type replace_view_properties_200_json_resp_primary_sort :: %{asc: boolean, field: String.t()}

  @type replace_view_properties_200_json_resp_stored_values :: %{
          cache: boolean | nil,
          compression: String.t() | nil,
          fields: [String.t()]
        }

  @type replace_view_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_view_properties_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Replace the properties of an arangosearch View

  Changes all properties of a View by replacing them, except for immutable properties.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_view_properties(
          database_name :: String.t(),
          view_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_view_properties(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :replace_view_properties},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :replace_view_properties_200_json_resp}},
        {400, {Arangox.Api.Views, :replace_view_properties_400_json_resp}},
        {404, {Arangox.Api.Views, :replace_view_properties_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type replace_view_properties_search_alias_200_json_resp :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          indexes: [
            Arangox.Api.Views.replace_view_properties_search_alias_200_json_resp_indexes()
          ],
          name: String.t(),
          type: String.t()
        }

  @type replace_view_properties_search_alias_200_json_resp_indexes :: %{
          collection: String.t(),
          index: String.t()
        }

  @type replace_view_properties_search_alias_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type replace_view_properties_search_alias_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Replace the properties of a search-alias View

  Replaces the list of indexes of a `search-alias` View.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec replace_view_properties_search_alias(
          database_name :: String.t(),
          view_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def replace_view_properties_search_alias(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :replace_view_properties_search_alias},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      body: body,
      method: :put,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :replace_view_properties_search_alias_200_json_resp}},
        {400, {Arangox.Api.Views, :replace_view_properties_search_alias_400_json_resp}},
        {404, {Arangox.Api.Views, :replace_view_properties_search_alias_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type update_view_properties_200_json_resp :: %{
          cleanupIntervalStep: integer,
          commitIntervalMsec: integer,
          consolidationIntervalMsec: integer,
          consolidationPolicy:
            Arangox.Api.Views.update_view_properties_200_json_resp_consolidation_policy(),
          globallyUniqueId: String.t(),
          id: String.t(),
          links: map,
          name: String.t(),
          optimizeTopK: [String.t()],
          primaryKeyCache: boolean | nil,
          primarySort: [Arangox.Api.Views.update_view_properties_200_json_resp_primary_sort()],
          primarySortCache: boolean | nil,
          primarySortCompression: String.t(),
          storedValues: [Arangox.Api.Views.update_view_properties_200_json_resp_stored_values()],
          type: String.t(),
          writebufferActive: integer,
          writebufferIdle: integer,
          writebufferSizeMax: integer
        }

  @type update_view_properties_200_json_resp_consolidation_policy :: %{
          maxSkewThreshold: number | nil,
          minDeletionRatio: number | nil,
          minScore: integer | nil,
          segmentsBytesFloor: integer | nil,
          segmentsBytesMax: integer | nil,
          segmentsMax: integer | nil,
          segmentsMin: integer | nil,
          threshold: number | nil,
          type: String.t() | nil
        }

  @type update_view_properties_200_json_resp_primary_sort :: %{asc: boolean, field: String.t()}

  @type update_view_properties_200_json_resp_stored_values :: %{
          cache: boolean | nil,
          compression: String.t() | nil,
          fields: [String.t()]
        }

  @type update_view_properties_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_view_properties_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Update the properties of an arangosearch View

  Partially changes the properties of a View by updating the specified attributes.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_view_properties(
          database_name :: String.t(),
          view_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_view_properties(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :update_view_properties},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      body: body,
      method: :patch,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :update_view_properties_200_json_resp}},
        {400, {Arangox.Api.Views, :update_view_properties_400_json_resp}},
        {404, {Arangox.Api.Views, :update_view_properties_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type update_view_properties_search_alias_200_json_resp :: %{
          globallyUniqueId: String.t(),
          id: String.t(),
          indexes: [Arangox.Api.Views.update_view_properties_search_alias_200_json_resp_indexes()],
          name: String.t(),
          type: String.t()
        }

  @type update_view_properties_search_alias_200_json_resp_indexes :: %{
          collection: String.t(),
          index: String.t()
        }

  @type update_view_properties_search_alias_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type update_view_properties_search_alias_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Update the properties of a search-alias View

  Updates the list of indexes of a `search-alias` View.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec update_view_properties_search_alias(
          database_name :: String.t(),
          view_name :: String.t(),
          body :: term,
          keyword
        ) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def update_view_properties_search_alias(database_name, view_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, view_name: view_name, body: body],
      call: {Arangox.Api.Views, :update_view_properties_search_alias},
      url: "/_db/#{database_name}/_api/view/#{view_name}/properties",
      body: body,
      method: :patch,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Views, :update_view_properties_search_alias_200_json_resp}},
        {400, {Arangox.Api.Views, :update_view_properties_search_alias_400_json_resp}},
        {404, {Arangox.Api.Views, :update_view_properties_search_alias_404_json_resp}}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:create_view_201_json_resp) do
    [
      cleanupIntervalStep: :integer,
      commitIntervalMsec: :integer,
      consolidationIntervalMsec: :integer,
      consolidationPolicy: {Arangox.Api.Views, :create_view_201_json_resp_consolidation_policy},
      globallyUniqueId: :string,
      id: :string,
      links: :map,
      name: :string,
      optimizeTopK: [:string],
      primaryKeyCache: :boolean,
      primarySort: [{Arangox.Api.Views, :create_view_201_json_resp_primary_sort}],
      primarySortCache: :boolean,
      primarySortCompression: {:enum, ["lz4", "none"]},
      storedValues: [{Arangox.Api.Views, :create_view_201_json_resp_stored_values}],
      type: :string,
      writebufferActive: :integer,
      writebufferIdle: :integer,
      writebufferSizeMax: :integer
    ]
  end

  def __fields__(:create_view_201_json_resp_consolidation_policy) do
    [
      maxSkewThreshold: :number,
      minDeletionRatio: :number,
      minScore: :integer,
      segmentsBytesFloor: :integer,
      segmentsBytesMax: :integer,
      segmentsMax: :integer,
      segmentsMin: :integer,
      threshold: :number,
      type: {:enum, ["tier", "bytes_accum"]}
    ]
  end

  def __fields__(:create_view_201_json_resp_primary_sort) do
    [asc: :boolean, field: :string]
  end

  def __fields__(:create_view_201_json_resp_stored_values) do
    [cache: :boolean, compression: {:enum, ["lz4", "none"]}, fields: [:string]]
  end

  def __fields__(:create_view_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_view_409_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_view_search_alias_201_json_resp) do
    [
      globallyUniqueId: :string,
      id: :string,
      indexes: [{Arangox.Api.Views, :create_view_search_alias_201_json_resp_indexes}],
      name: :string,
      type: :string
    ]
  end

  def __fields__(:create_view_search_alias_201_json_resp_indexes) do
    [collection: :string, index: :string]
  end

  def __fields__(:create_view_search_alias_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_view_search_alias_409_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_view_200_json_resp) do
    [code: :integer, error: :boolean, result: :boolean]
  end

  def __fields__(:delete_view_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_view_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      name: :string,
      type: :string
    ]
  end

  def __fields__(:get_view_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_properties_200_json_resp) do
    [
      cleanupIntervalStep: :integer,
      code: :integer,
      commitIntervalMsec: :integer,
      consolidationIntervalMsec: :integer,
      consolidationPolicy:
        {Arangox.Api.Views, :get_view_properties_200_json_resp_consolidation_policy},
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      links: :map,
      name: :string,
      optimizeTopK: [:string],
      primaryKeyCache: :boolean,
      primarySort: [{Arangox.Api.Views, :get_view_properties_200_json_resp_primary_sort}],
      primarySortCache: :boolean,
      primarySortCompression: {:enum, ["lz4", "none"]},
      storedValues: [{Arangox.Api.Views, :get_view_properties_200_json_resp_stored_values}],
      type: :string,
      writebufferActive: :integer,
      writebufferIdle: :integer,
      writebufferSizeMax: :integer
    ]
  end

  def __fields__(:get_view_properties_200_json_resp_consolidation_policy) do
    [
      maxSkewThreshold: :number,
      minDeletionRatio: :number,
      minScore: :integer,
      segmentsBytesFloor: :integer,
      segmentsBytesMax: :integer,
      segmentsMax: :integer,
      segmentsMin: :integer,
      threshold: :number,
      type: {:enum, ["tier", "bytes_accum"]}
    ]
  end

  def __fields__(:get_view_properties_200_json_resp_primary_sort) do
    [asc: :boolean, field: :string]
  end

  def __fields__(:get_view_properties_200_json_resp_stored_values) do
    [cache: :boolean, compression: {:enum, ["lz4", "none"]}, fields: [:string]]
  end

  def __fields__(:get_view_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_properties_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_properties_search_alias_200_json_resp) do
    [
      globallyUniqueId: :string,
      id: :string,
      indexes: [{Arangox.Api.Views, :get_view_properties_search_alias_200_json_resp_indexes}],
      name: :string,
      type: :string
    ]
  end

  def __fields__(:get_view_properties_search_alias_200_json_resp_indexes) do
    [collection: :string, index: :string]
  end

  def __fields__(:get_view_properties_search_alias_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_properties_search_alias_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_view_search_alias_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      globallyUniqueId: :string,
      id: :string,
      name: :string,
      type: :string
    ]
  end

  def __fields__(:get_view_search_alias_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_views_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: [{Arangox.Api.Views, :list_views_200_json_resp_result}]
    ]
  end

  def __fields__(:list_views_200_json_resp_result) do
    [
      globallyUniqueId: :string,
      id: :string,
      name: :string,
      type: {:enum, ["arangosearch", "search-alias"]}
    ]
  end

  def __fields__(:rename_view_200_json_resp) do
    [
      cleanupIntervalStep: :integer,
      commitIntervalMsec: :integer,
      consolidationIntervalMsec: :integer,
      consolidationPolicy: {Arangox.Api.Views, :rename_view_200_json_resp_consolidation_policy},
      globallyUniqueId: :string,
      id: :string,
      links: :map,
      name: :string,
      optimizeTopK: [:string],
      primaryKeyCache: :boolean,
      primarySort: [{Arangox.Api.Views, :rename_view_200_json_resp_primary_sort}],
      primarySortCache: :boolean,
      primarySortCompression: {:enum, ["lz4", "none"]},
      storedValues: [{Arangox.Api.Views, :rename_view_200_json_resp_stored_values}],
      type: :string,
      writebufferActive: :integer,
      writebufferIdle: :integer,
      writebufferSizeMax: :integer
    ]
  end

  def __fields__(:rename_view_200_json_resp_consolidation_policy) do
    [
      maxSkewThreshold: :number,
      minDeletionRatio: :number,
      minScore: :integer,
      segmentsBytesFloor: :integer,
      segmentsBytesMax: :integer,
      segmentsMax: :integer,
      segmentsMin: :integer,
      threshold: :number,
      type: {:enum, ["tier", "bytes_accum"]}
    ]
  end

  def __fields__(:rename_view_200_json_resp_primary_sort) do
    [asc: :boolean, field: :string]
  end

  def __fields__(:rename_view_200_json_resp_stored_values) do
    [cache: :boolean, compression: {:enum, ["lz4", "none"]}, fields: [:string]]
  end

  def __fields__(:rename_view_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:rename_view_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:rename_view_search_alias_200_json_resp) do
    [
      globallyUniqueId: :string,
      id: :string,
      indexes: [{Arangox.Api.Views, :rename_view_search_alias_200_json_resp_indexes}],
      name: :string,
      type: :string
    ]
  end

  def __fields__(:rename_view_search_alias_200_json_resp_indexes) do
    [collection: :string, index: :string]
  end

  def __fields__(:rename_view_search_alias_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:rename_view_search_alias_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_view_properties_200_json_resp) do
    [
      cleanupIntervalStep: :integer,
      commitIntervalMsec: :integer,
      consolidationIntervalMsec: :integer,
      consolidationPolicy:
        {Arangox.Api.Views, :replace_view_properties_200_json_resp_consolidation_policy},
      globallyUniqueId: :string,
      id: :string,
      links: :map,
      name: :string,
      optimizeTopK: [:string],
      primaryKeyCache: :boolean,
      primarySort: [{Arangox.Api.Views, :replace_view_properties_200_json_resp_primary_sort}],
      primarySortCache: :boolean,
      primarySortCompression: {:enum, ["lz4", "none"]},
      storedValues: [{Arangox.Api.Views, :replace_view_properties_200_json_resp_stored_values}],
      type: :string,
      writebufferActive: :integer,
      writebufferIdle: :integer,
      writebufferSizeMax: :integer
    ]
  end

  def __fields__(:replace_view_properties_200_json_resp_consolidation_policy) do
    [
      maxSkewThreshold: :number,
      minDeletionRatio: :number,
      minScore: :integer,
      segmentsBytesFloor: :integer,
      segmentsBytesMax: :integer,
      segmentsMax: :integer,
      segmentsMin: :integer,
      threshold: :number,
      type: {:enum, ["tier", "bytes_accum"]}
    ]
  end

  def __fields__(:replace_view_properties_200_json_resp_primary_sort) do
    [asc: :boolean, field: :string]
  end

  def __fields__(:replace_view_properties_200_json_resp_stored_values) do
    [cache: :boolean, compression: {:enum, ["lz4", "none"]}, fields: [:string]]
  end

  def __fields__(:replace_view_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_view_properties_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_view_properties_search_alias_200_json_resp) do
    [
      globallyUniqueId: :string,
      id: :string,
      indexes: [{Arangox.Api.Views, :replace_view_properties_search_alias_200_json_resp_indexes}],
      name: :string,
      type: :string
    ]
  end

  def __fields__(:replace_view_properties_search_alias_200_json_resp_indexes) do
    [collection: :string, index: :string]
  end

  def __fields__(:replace_view_properties_search_alias_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:replace_view_properties_search_alias_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_view_properties_200_json_resp) do
    [
      cleanupIntervalStep: :integer,
      commitIntervalMsec: :integer,
      consolidationIntervalMsec: :integer,
      consolidationPolicy:
        {Arangox.Api.Views, :update_view_properties_200_json_resp_consolidation_policy},
      globallyUniqueId: :string,
      id: :string,
      links: :map,
      name: :string,
      optimizeTopK: [:string],
      primaryKeyCache: :boolean,
      primarySort: [{Arangox.Api.Views, :update_view_properties_200_json_resp_primary_sort}],
      primarySortCache: :boolean,
      primarySortCompression: {:enum, ["lz4", "none"]},
      storedValues: [{Arangox.Api.Views, :update_view_properties_200_json_resp_stored_values}],
      type: :string,
      writebufferActive: :integer,
      writebufferIdle: :integer,
      writebufferSizeMax: :integer
    ]
  end

  def __fields__(:update_view_properties_200_json_resp_consolidation_policy) do
    [
      maxSkewThreshold: :number,
      minDeletionRatio: :number,
      minScore: :integer,
      segmentsBytesFloor: :integer,
      segmentsBytesMax: :integer,
      segmentsMax: :integer,
      segmentsMin: :integer,
      threshold: :number,
      type: {:enum, ["tier", "bytes_accum"]}
    ]
  end

  def __fields__(:update_view_properties_200_json_resp_primary_sort) do
    [asc: :boolean, field: :string]
  end

  def __fields__(:update_view_properties_200_json_resp_stored_values) do
    [cache: :boolean, compression: {:enum, ["lz4", "none"]}, fields: [:string]]
  end

  def __fields__(:update_view_properties_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_view_properties_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_view_properties_search_alias_200_json_resp) do
    [
      globallyUniqueId: :string,
      id: :string,
      indexes: [{Arangox.Api.Views, :update_view_properties_search_alias_200_json_resp_indexes}],
      name: :string,
      type: :string
    ]
  end

  def __fields__(:update_view_properties_search_alias_200_json_resp_indexes) do
    [collection: :string, index: :string]
  end

  def __fields__(:update_view_properties_search_alias_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:update_view_properties_search_alias_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end
end
