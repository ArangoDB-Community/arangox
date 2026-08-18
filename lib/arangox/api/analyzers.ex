defmodule Arangox.Api.Analyzers do
  @moduledoc """
  Provides API endpoints related to analyzers
  """

  @default_client Arangox.Api.Client

  @doc """
  Create an Analyzer

  Creates a new Analyzer based on the provided configuration.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_analyzer(database_name :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_analyzer(database_name, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, body: body],
      call: {Arangox.Api.Analyzers, :create_analyzer},
      url: "/_db/#{database_name}/_api/analyzer",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [{200, :null}, {201, :null}, {400, :null}, {403, :null}],
      opts: opts
    })
  end

  @doc """
  Remove an Analyzer

  Removes an Analyzer configuration identified by `analyzer-name`.

  If the Analyzer definition was successfully dropped, an object is returned with
  the following attributes:
  - `error`: `false`
  - `name`: The name of the removed Analyzer

  ## Options

    * `force`: The Analyzer configuration should be removed even if it is in-use.
      

  """
  @spec delete_analyzer(database_name :: String.t(), analyzer_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_analyzer(database_name, analyzer_name, opts \\ []) do
    client = opts[:client] || @default_client
    query = Keyword.take(opts, [:force])

    client.request(%{
      args: [database_name: database_name, analyzer_name: analyzer_name],
      call: {Arangox.Api.Analyzers, :delete_analyzer},
      url: "/_db/#{database_name}/_api/analyzer/#{analyzer_name}",
      method: :delete,
      query: query,
      response: [{200, :null}, {400, :null}, {403, :null}, {404, :null}, {409, :null}],
      opts: opts
    })
  end

  @doc """
  Get an Analyzer definition

  Retrieves the full definition for the specified Analyzer name.
  The resulting object contains the following attributes:
  - `name`: the Analyzer name
  - `type`: the Analyzer type
  - `properties`: the properties used to configure the specified type
  - `features`: the set of features to set on the Analyzer generated fields

  """
  @spec get_analyzer(database_name :: String.t(), analyzer_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_analyzer(database_name, analyzer_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name, analyzer_name: analyzer_name],
      call: {Arangox.Api.Analyzers, :get_analyzer},
      url: "/_db/#{database_name}/_api/analyzer/#{analyzer_name}",
      method: :get,
      response: [{200, :null}, {404, :null}],
      opts: opts
    })
  end

  @doc """
  List all Analyzers

  Retrieves a an array of all Analyzer definitions.
  The resulting array contains objects with the following attributes:
  - `name`: the Analyzer name
  - `type`: the Analyzer type
  - `properties`: the properties used to configure the specified type
  - `features`: the set of features to set on the Analyzer generated fields

  """
  @spec list_analyzers(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_analyzers(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Analyzers, :list_analyzers},
      url: "/_db/#{database_name}/_api/analyzer",
      method: :get,
      response: [{200, :null}],
      opts: opts
    })
  end
end
