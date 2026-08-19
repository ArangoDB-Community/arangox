defmodule Arangox.Api.Authentication do
  @moduledoc """
  ArangoDB's Authentication operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.Api.Client` for the options they all accept and
  for what a `404` answers.
  """

  alias Arangox.Api.Client

  @doc """
  List all access tokens

  List the access tokens for a given user.

  This only returns the access token metadata.
  The actual access token strings are only shown when creating tokens. 

  The user account you authenticate with needs to have administrate access
  to the `_system` database if you want to list the access tokens for a
  different user. You can always list your own access tokens,
  regardless of database access levels.
  """
  @spec all_access_tokens(Arangox.conn(), binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def all_access_tokens(conn, user, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_api", "token", user],
      opts: opts
    )
  end

  @doc """
  List all access tokens. Raises on error.

  See `all_access_tokens/2`.
  """
  @spec all_access_tokens!(Arangox.conn(), binary, keyword) :: term
  def all_access_tokens!(conn, user, opts \\ []) do
    case all_access_tokens(conn, user, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create an access token

  Create a new access token for the given user.

  The response includes the actual access token string that you need to
  store in a secure manner. It is only shown once.

  The user account you authenticate with needs to have administrate access
  to the `_system` database if you want to create an access token for a
  different user. You can always create an access token for yourself,
  regardless of database access levels.
  """
  @spec create_access_token(Arangox.conn(), binary, term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_access_token(conn, user, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_api", "token", user],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create an access token. Raises on error.

  See `create_access_token/3`.
  """
  @spec create_access_token!(Arangox.conn(), binary, term, keyword) :: term
  def create_access_token!(conn, user, body, opts \\ []) do
    case create_access_token(conn, user, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Create a JWT session token

  Obtain a JSON Web Token (JWT) from the credentials of an ArangoDB user account
  or a user's access token.
  You can use the JWT in the `Authorization` HTTP header as a `Bearer` token to
  authenticate requests.

  The lifetime for the token is controlled by the `--server.session-timeout`
  startup option.
  """
  @spec create_session_token(Arangox.conn(), term, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def create_session_token(conn, body, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_open", "auth"],
      body: body,
      opts: opts
    )
  end

  @doc """
  Create a JWT session token. Raises on error.

  See `create_session_token/2`.
  """
  @spec create_session_token!(Arangox.conn(), term, keyword) :: term
  def create_session_token!(conn, body, opts \\ []) do
    case create_session_token(conn, body, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Delete an access token

  Delete an access token with the specified identifier for the given user.

  The user account you authenticate with needs to have administrate access
  to the `_system` database if you want to delete an access token for a
  different user. You can always delete your own access tokens,
  regardless of database access levels.
  """
  @spec delete_access_token(Arangox.conn(), binary, binary, keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def delete_access_token(conn, user, token_id, opts \\ []) do
    Client.request(conn,
      method: :delete,
      segments: ["_api", "token", user, token_id],
      opts: opts
    )
  end

  @doc """
  Delete an access token. Raises on error.

  See `delete_access_token/3`.
  """
  @spec delete_access_token!(Arangox.conn(), binary, binary, keyword) :: term
  def delete_access_token!(conn, user, token_id, opts \\ []) do
    case delete_access_token(conn, user, token_id, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Hot-reload the JWT secret(s) from disk

  Sending a request without payload to this endpoint reloads the JWT secret(s)
  from disk. Only the files specified via the arangod startup option
  `--server.jwt-secret-keyfile` or `--server.jwt-secret-folder` are used.
  It is not possible to change the locations where files are loaded from
  without restarting the process.

  To utilize the API a superuser JWT token is necessary, otherwise the response
  will be _HTTP 403 Forbidden_.
  """
  @spec reload_server_jwt_secrets(Arangox.conn(), keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def reload_server_jwt_secrets(conn, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "server", "jwt"],
      opts: opts
    )
  end

  @doc """
  Hot-reload the JWT secret(s) from disk. Raises on error.

  See `reload_server_jwt_secrets/1`.
  """
  @spec reload_server_jwt_secrets!(Arangox.conn(), keyword) :: term
  def reload_server_jwt_secrets!(conn, opts \\ []) do
    case reload_server_jwt_secrets(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Get information about the loaded JWT secrets

  Get information about the currently loaded secrets.

  To utilize the API a superuser JWT token is necessary, otherwise the response
  will be _HTTP 403 Forbidden_.
  """
  @spec server_jwt_secrets(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_jwt_secrets(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "jwt"],
      opts: opts
    )
  end

  @doc """
  Get information about the loaded JWT secrets. Raises on error.

  See `server_jwt_secrets/1`.
  """
  @spec server_jwt_secrets!(Arangox.conn(), keyword) :: term
  def server_jwt_secrets!(conn, opts \\ []) do
    case server_jwt_secrets(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
