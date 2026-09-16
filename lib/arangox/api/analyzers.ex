defmodule Arangox.API.Analyzers do
  @moduledoc """
  ArangoDB's Analyzers operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

  @doc """
  List all Analyzers

  Retrieves a an array of all Analyzer definitions.
  The resulting array contains objects with the following attributes:
  - `name`: the Analyzer name
  - `type`: the Analyzer type
  - `properties`: the properties used to configure the specified type
  - `features`: the set of features to set on the Analyzer generated fields

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => [%{
          "features" => [string],
          "name" => string,
          "properties" => %{
            "accent" => boolean,
            "case" => string,
            "locale" => string,
            "stemming" => boolean,
            "stopwords" => []
          },
          "type" => string
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "analyzer"],
      opts: opts
    )
  end

  @doc """
  List all Analyzers. Raises on error.

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
  Create an Analyzer

  Creates a new Analyzer based on the provided configuration.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "analyzer"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create an Analyzer. Raises on error.

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
  Remove an Analyzer

  Removes an Analyzer configuration identified by `analyzer-name`.

  If the Analyzer definition was successfully dropped, an object is returned with
  the following attributes:
  - `error`: `false`
  - `name`: The name of the removed Analyzer
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, analyzer_name, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "analyzer", analyzer_name],
      query: [force: "force"],
      opts: opts
    )
  end

  @doc """
  Remove an Analyzer. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, analyzer_name, opts \\ []) do
    case delete(conn, analyzer_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get an Analyzer definition

  Retrieves the full definition for the specified Analyzer name.
  The resulting object contains the following attributes:
  - `name`: the Analyzer name
  - `type`: the Analyzer type
  - `properties`: the properties used to configure the specified type
  - `features`: the set of features to set on the Analyzer generated fields

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "features" => [],
        "name" => string,
        "properties" => %{},
        "type" => string
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, analyzer_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "analyzer", analyzer_name],
      opts: opts
    )
  end

  @doc """
  Get an Analyzer definition. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, analyzer_name, opts \\ []) do
    case get(conn, analyzer_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
