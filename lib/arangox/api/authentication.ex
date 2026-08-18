defmodule Arangox.Api.Authentication do
  @moduledoc """
  Provides API endpoints related to authentication
  """

  @default_client Arangox.Api.Client

  @type create_access_token_200_json_resp :: %{
          active: boolean,
          created_at: integer,
          fingerprint: String.t(),
          id: integer,
          name: String.t(),
          token: String.t(),
          valid_until: integer
        }

  @type create_access_token_400_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_access_token_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_access_token_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_access_token_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type create_access_token_409_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Create an access token

  Create a new access token for the given user.

  The response includes the actual access token string that you need to
  store in a secure manner. It is only shown once.

  The user account you authenticate with needs to have administrate access
  to the `_system` database if you want to create an access token for a
  different user. You can always create an access token for yourself,
  regardless of database access levels.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_access_token(user :: String.t(), body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_access_token(user, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [user: user, body: body],
      call: {Arangox.Api.Authentication, :create_access_token},
      url: "/_api/token/#{user}",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Authentication, :create_access_token_200_json_resp}},
        {400, {Arangox.Api.Authentication, :create_access_token_400_json_resp}},
        {401, {Arangox.Api.Authentication, :create_access_token_401_json_resp}},
        {403, {Arangox.Api.Authentication, :create_access_token_403_json_resp}},
        {404, {Arangox.Api.Authentication, :create_access_token_404_json_resp}},
        {409, {Arangox.Api.Authentication, :create_access_token_409_json_resp}}
      ],
      opts: opts
    })
  end

  @type create_session_token_200_json_resp :: %{jwt: String.t()}

  @doc """
  Create a JWT session token

  Obtain a JSON Web Token (JWT) from the credentials of an ArangoDB user account
  or a user's access token.
  You can use the JWT in the `Authorization` HTTP header as a `Bearer` token to
  authenticate requests.

  The lifetime for the token is controlled by the `--server.session-timeout`
  startup option.

  ## Request Body

  **Content Types**: `application/json`
  """
  @spec create_session_token(body :: term, keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def create_session_token(body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [body: body],
      call: {Arangox.Api.Authentication, :create_session_token},
      url: "/_open/auth",
      body: body,
      method: :post,
      request: [{"application/json", :map}],
      response: [
        {200, {Arangox.Api.Authentication, :create_session_token_200_json_resp}},
        {400, :null},
        {401, :null},
        {404, :null}
      ],
      opts: opts
    })
  end

  @type delete_access_token_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_access_token_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type delete_access_token_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @doc """
  Delete an access token

  Delete an access token with the specified identifier for the given user.

  The user account you authenticate with needs to have administrate access
  to the `_system` database if you want to delete an access token for a
  different user. You can always delete your own access tokens,
  regardless of database access levels.

  """
  @spec delete_access_token(user :: String.t(), token_id :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def delete_access_token(user, token_id, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [user: user, token_id: token_id],
      call: {Arangox.Api.Authentication, :delete_access_token},
      url: "/_api/token/#{user}/#{token_id}",
      method: :delete,
      response: [
        {200, :map},
        {401, {Arangox.Api.Authentication, :delete_access_token_401_json_resp}},
        {403, {Arangox.Api.Authentication, :delete_access_token_403_json_resp}},
        {404, {Arangox.Api.Authentication, :delete_access_token_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type get_server_jwt_secrets_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Authentication.get_server_jwt_secrets_200_json_resp_result()
        }

  @type get_server_jwt_secrets_200_json_resp_result :: %{active: map, passive: [map]}

  @doc """
  Get information about the loaded JWT secrets

  Get information about the currently loaded secrets.

  To utilize the API a superuser JWT token is necessary, otherwise the response
  will be _HTTP 403 Forbidden_.

  """
  @spec get_server_jwt_secrets(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_jwt_secrets(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Authentication, :get_server_jwt_secrets},
      url: "/_db/#{database_name}/_admin/server/jwt",
      method: :get,
      response: [
        {200, {Arangox.Api.Authentication, :get_server_jwt_secrets_200_json_resp}},
        {403, :null}
      ],
      opts: opts
    })
  end

  @type list_access_tokens_200_json_resp :: %{
          tokens: [Arangox.Api.Authentication.list_access_tokens_200_json_resp_tokens()]
        }

  @type list_access_tokens_200_json_resp_tokens :: %{
          active: boolean,
          created_at: integer,
          fingerprint: String.t(),
          id: integer,
          name: String.t(),
          valid_until: integer
        }

  @type list_access_tokens_401_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_access_tokens_403_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

  @type list_access_tokens_404_json_resp :: %{
          code: integer,
          error: boolean,
          errorMessage: String.t(),
          errorNum: integer
        }

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
  @spec list_access_tokens(user :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def list_access_tokens(user, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [user: user],
      call: {Arangox.Api.Authentication, :list_access_tokens},
      url: "/_api/token/#{user}",
      method: :get,
      response: [
        {200, {Arangox.Api.Authentication, :list_access_tokens_200_json_resp}},
        {401, {Arangox.Api.Authentication, :list_access_tokens_401_json_resp}},
        {403, {Arangox.Api.Authentication, :list_access_tokens_403_json_resp}},
        {404, {Arangox.Api.Authentication, :list_access_tokens_404_json_resp}}
      ],
      opts: opts
    })
  end

  @type reload_server_jwt_secrets_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Authentication.reload_server_jwt_secrets_200_json_resp_result()
        }

  @type reload_server_jwt_secrets_200_json_resp_result :: %{active: map, passive: [map]}

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
  @spec reload_server_jwt_secrets(keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def reload_server_jwt_secrets(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Authentication, :reload_server_jwt_secrets},
      url: "/_admin/server/jwt",
      method: :post,
      response: [
        {200, {Arangox.Api.Authentication, :reload_server_jwt_secrets_200_json_resp}},
        {403, :null}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:create_access_token_200_json_resp) do
    [
      active: :boolean,
      created_at: :integer,
      fingerprint: :string,
      id: :integer,
      name: :string,
      token: :string,
      valid_until: :integer
    ]
  end

  def __fields__(:create_access_token_400_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_access_token_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_access_token_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_access_token_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_access_token_409_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:create_session_token_200_json_resp) do
    [jwt: :string]
  end

  def __fields__(:delete_access_token_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_access_token_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:delete_access_token_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:get_server_jwt_secrets_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Authentication, :get_server_jwt_secrets_200_json_resp_result}
    ]
  end

  def __fields__(:get_server_jwt_secrets_200_json_resp_result) do
    [active: :map, passive: [:map]]
  end

  def __fields__(:list_access_tokens_200_json_resp) do
    [tokens: [{Arangox.Api.Authentication, :list_access_tokens_200_json_resp_tokens}]]
  end

  def __fields__(:list_access_tokens_200_json_resp_tokens) do
    [
      active: :boolean,
      created_at: :integer,
      fingerprint: :string,
      id: :integer,
      name: :string,
      valid_until: :integer
    ]
  end

  def __fields__(:list_access_tokens_401_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_access_tokens_403_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:list_access_tokens_404_json_resp) do
    [code: :integer, error: :boolean, errorMessage: :string, errorNum: :integer]
  end

  def __fields__(:reload_server_jwt_secrets_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Authentication, :reload_server_jwt_secrets_200_json_resp_result}
    ]
  end

  def __fields__(:reload_server_jwt_secrets_200_json_resp_result) do
    [active: :map, passive: [:map]]
  end
end
