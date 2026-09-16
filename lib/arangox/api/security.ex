defmodule Arangox.API.Security do
  @moduledoc """
  ArangoDB's Security operations.

  Every function takes the pool as its first argument and returns the decoded
  response body. See `Arangox.API.Client` for the options they all accept and
  for what a `404` returns.
  """

  alias Arangox.API.Client

  @doc """
  Reload the TLS data

  This API call triggers a reload of all the TLS data (server key, client-auth CA)
  and then returns a summary. The JSON response is exactly as in the corresponding
  GET request.

  This is a protected API and can only be executed with superuser rights.
  """
  @spec reload_server_tls(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def reload_server_tls(conn, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "server", "tls"],
      database_scope: :server,
      opts: opts
    )
  end

  @doc """
  Reload the TLS data. Raises on error.

  See `reload_server_tls/1`.
  """
  @spec reload_server_tls!(Arangox.conn(), keyword) :: term
  def reload_server_tls!(conn, opts \\ []) do
    case reload_server_tls(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  @doc """
  Rotate the encryption at rest key

  Change the user-supplied encryption at rest key by sending a request without
  payload to this endpoint. The file supplied via `--rocksdb.encryption-keyfolder`
  will be reloaded and the internal encryption key will be re-encrypted with the
  new user key.

  This is a protected API and can only be executed with superuser rights.
  This API is not available on Coordinator nodes.
  """
  @spec rotate_encryption_at_rest_key(Arangox.conn(), keyword) ::
          {:ok, term} | {:error, Exception.t()}
  def rotate_encryption_at_rest_key(conn, opts \\ []) do
    Client.request(conn,
      method: :post,
      segments: ["_admin", "server", "encryption"],
      database_scope: :server,
      opts: opts
    )
  end

  @doc """
  Rotate the encryption at rest key. Raises on error.

  See `rotate_encryption_at_rest_key/1`.
  """
  @spec rotate_encryption_at_rest_key!(Arangox.conn(), keyword) :: term
  def rotate_encryption_at_rest_key!(conn, opts \\ []) do
    case rotate_encryption_at_rest_key(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

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

  ## Returns

  Recorded against ArangoDB 3.12.10:

      %{
        "code" => integer,
        "error" => boolean,
        "result" => %{}
      }
  """
  @spec server_tls(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def server_tls(conn, opts \\ []) do
    Client.request(conn,
      method: :get,
      segments: ["_admin", "server", "tls"],
      opts: opts
    )
  end

  @doc """
  Get the TLS data. Raises on error.

  See `server_tls/1`.
  """
  @spec server_tls!(Arangox.conn(), keyword) :: term
  def server_tls!(conn, opts \\ []) do
    case server_tls(conn, opts) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end
end
