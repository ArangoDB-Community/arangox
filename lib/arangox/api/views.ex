defmodule Arangox.API.Views do
  @moduledoc """
  ArangoDB's Views operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

  @doc """
  List all Views

  Returns an object containing a listing of all Views in the current database,
  regardless of their type.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => [%{
          "globallyUniqueId" => string,
          "id" => string,
          "name" => string,
          "type" => string
        }]
      }
  """
  @spec all(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def all(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "view"],
      opts: opts
    )
  end

  @doc """
  List all Views. Raises on error.

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
  Create an arangosearch View

  Creates a new View with a given name and properties if it does not
  already exist.
  """
  @spec create(Arangox.conn(), term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def create(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "view"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create an arangosearch View. Raises on error.

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
  Drop a View

  Deletes the View identified by `view-name`.
  """
  @spec delete(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def delete(conn, view_name, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "view", view_name],
      opts: opts
    )
  end

  @doc """
  Drop a View. Raises on error.

  See `delete/2`.
  """
  @spec delete!(Arangox.conn(), binary, keyword) :: term
  def delete!(conn, view_name, opts \\ []) do
    case delete(conn, view_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get information about a View

  Returns the basic information about a specific View.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "name" => string,
        "type" => string
      }
  """
  @spec get(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def get(conn, view_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "view", view_name],
      opts: opts
    )
  end

  @doc """
  Get information about a View. Raises on error.

  See `get/2`.
  """
  @spec get!(Arangox.conn(), binary, keyword) :: term
  def get!(conn, view_name, opts \\ []) do
    case get(conn, view_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get the properties of a View

  Returns an object containing the definition of the View identified by `view-name`.

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "cleanupIntervalStep" => integer,
        "code" => integer,
        "commitIntervalMsec" => integer,
        "consolidationIntervalMsec" => integer,
        "consolidationPolicy" => %{
          "maxSkewThreshold" => float,
          "minDeletionRatio" => float,
          "segmentsBytesMax" => integer,
          "type" => string
        },
        "error" => boolean,
        "globallyUniqueId" => string,
        "id" => string,
        "links" => %{},
        "name" => string,
        "optimizeTopK" => [],
        "primarySort" => [],
        "primarySortCompression" => string,
        "storedValues" => [],
        "type" => string,
        "writebufferActive" => integer,
        "writebufferIdle" => integer,
        "writebufferSizeMax" => integer
      }
  """
  @spec properties(Arangox.conn(), binary, keyword) :: {:ok, term} | {:error, Exception.t()}
  def properties(conn, view_name, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "view", view_name, "properties"],
      opts: opts
    )
  end

  @doc """
  Get the properties of a View. Raises on error.

  See `properties/2`.
  """
  @spec properties!(Arangox.conn(), binary, keyword) :: term
  def properties!(conn, view_name, opts \\ []) do
    case properties(conn, view_name, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Rename a View

  Renames a View.

  > **INFO:**
  Renaming Views is not supported in cluster deployments.
  """
  @spec rename(Arangox.conn(), binary, term, keyword) :: {:ok, term} | {:error, Exception.t()}
  def rename(conn, view_name, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "view", view_name, "rename"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Rename a View. Raises on error.

  See `rename/3`.
  """
  @spec rename!(Arangox.conn(), binary, term, keyword) :: term
  def rename!(conn, view_name, body, opts \\ []) do
    case rename(conn, view_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Replace the properties of an arangosearch View

  Changes all properties of a View by replacing them, except for immutable properties.
  """
  @spec replace_properties(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def replace_properties(conn, view_name, body, opts \\ []) do
    Client.request(conn,
      method: :put,
      segments: ["_api", "view", view_name, "properties"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Replace the properties of an arangosearch View. Raises on error.

  See `replace_properties/3`.
  """
  @spec replace_properties!(Arangox.conn(), binary, term, keyword) :: term
  def replace_properties!(conn, view_name, body, opts \\ []) do
    case replace_properties(conn, view_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Update the properties of an arangosearch View

  Partially changes the properties of a View by updating the specified attributes.
  """
  @spec update_properties(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def update_properties(conn, view_name, body, opts \\ []) do
    Client.request(conn,
      method: :patch,
      segments: ["_api", "view", view_name, "properties"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Update the properties of an arangosearch View. Raises on error.

  See `update_properties/3`.
  """
  @spec update_properties!(Arangox.conn(), binary, term, keyword) :: term
  def update_properties!(conn, view_name, body, opts \\ []) do
    case update_properties(conn, view_name, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
