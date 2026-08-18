defmodule Arangox.Api.Security do
  @moduledoc """
  Provides API endpoints related to security
  """

  @default_client Arangox.Api.Client

  @doc """
  Get the TLS data

  Return a summary of the TLS data. The JSON response will contain a field
  `result` with the following components:

    - `keyfile`: Information about the key file.
    - `clientCA`: Information about the Certificate Authority (CA) for
      client certificate verification.

  If server name indication (SNI) is used and multiple key files are
  configured for different server names, then there is an additional
  attribute `SNI`, which contains for each configured server name
  the corresponding information about the key file for that server name.

  In all cases the value of the attribute will be a JSON object, which
  has a subset of the following attributes (whatever is appropriate):

    - `sha256`: The value is a string with the SHA256 of the whole input
      file.
    - `certificates`: The value is a JSON array with the public
      certificates in the chain in the file.
    - `privateKeySha256`: In cases where there is a private key (`keyfile`
      but not `clientCA`), this field is present and contains a
      JSON string with the SHA256 of the private key.

  This API requires authentication.

  """
  @spec get_server_tls(database_name :: String.t(), keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def get_server_tls(database_name, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [database_name: database_name],
      call: {Arangox.Api.Security, :get_server_tls},
      url: "/_db/#{database_name}/_admin/server/tls",
      method: :get,
      response: [{200, :null}],
      opts: opts
    })
  end

  @doc """
  Reload the TLS data

  This API call triggers a reload of all the TLS data (server key, client-auth CA)
  and then returns a summary. The JSON response is exactly as in the corresponding
  GET request.

  This is a protected API and can only be executed with superuser rights.

  """
  @spec reload_server_tls(keyword) :: {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def reload_server_tls(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Security, :reload_server_tls},
      url: "/_admin/server/tls",
      method: :post,
      response: [{200, :null}, {403, :null}],
      opts: opts
    })
  end

  @type rotate_encryption_at_rest_key_200_json_resp :: %{
          code: integer,
          error: boolean,
          result: Arangox.Api.Security.rotate_encryption_at_rest_key_200_json_resp_result()
        }

  @type rotate_encryption_at_rest_key_200_json_resp_result :: %{"encryption-keys": [map]}

  @doc """
  Rotate the encryption at rest key

  Change the user-supplied encryption at rest key by sending a request without
  payload to this endpoint. The file supplied via `--rocksdb.encryption-keyfolder`
  will be reloaded and the internal encryption key will be re-encrypted with the
  new user key.

  This is a protected API and can only be executed with superuser rights.
  This API is not available on Coordinator nodes.

  """
  @spec rotate_encryption_at_rest_key(keyword) ::
          {:ok, Arangox.Response.t()} | {:error, Exception.t()}
  def rotate_encryption_at_rest_key(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {Arangox.Api.Security, :rotate_encryption_at_rest_key},
      url: "/_admin/server/encryption",
      method: :post,
      response: [
        {200, {Arangox.Api.Security, :rotate_encryption_at_rest_key_200_json_resp}},
        {403, :null},
        {404, :null}
      ],
      opts: opts
    })
  end

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(:rotate_encryption_at_rest_key_200_json_resp) do
    [
      code: :integer,
      error: :boolean,
      result: {Arangox.Api.Security, :rotate_encryption_at_rest_key_200_json_resp_result}
    ]
  end

  def __fields__(:rotate_encryption_at_rest_key_200_json_resp_result) do
    ["encryption-keys": [:map]]
  end
end
