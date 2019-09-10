defmodule Arangox.Client do
  @moduledoc """
  HTTP client behaviour for `Arangox`.

  To use an http library other than `:gun` or `Mint`, implement this behaviour
  in a module and pass that module to the `:client` start option. Arangox
  will use that implementation to perform all it's http related connection and
  execution operations.
  """

  alias Arangox.{
    Connection,
    Request,
    Response
  }

  @type endpoint :: Arangox.endpoint()
  @type start_options :: [Arangox.start_option()]
  @type conn :: any
  @type exception_or_reason :: any
  @type state :: Connection.t()
  @type request :: Request.t()
  @type response :: Response.t()

  @doc """
  Receives a raw endpoint binary and all the start options from `Arangox.start_link/1`.

  The `Arangox.Endpoint` module has utilities for parsing ArangoDB endpoints.
  The `conn` returned from this callback gets placed in the `:socket` field
  of an `%Arango.Connection{}` struct, which represents a connection's state.

  It's up to the client to consolidate the `:connect_timeout`, `:transport_opts`
  and `:client_opts` options.
  """
  @callback connect(endpoint, start_options) ::
              {:ok, conn} | {:error, exception_or_reason}

  @callback alive?(state) :: boolean

  @doc """
  Receives a `Arangox.Request` struct and a connection's state, an `Arangox.Connection`
  struct, and returns an `Arangox.Response` struct or error (or exception struct),
  along with the new state.

  Arangox handles the encoding and decoding of request and response bodies.

  In the case of an error, this should return `{:error, :noproc, state}` if the connection
  was lost, otherwise an attempt to reconnect won't be made until the next request hitting
  this process fails.
  """
  @callback request(request, state) ::
              {:ok, response, state} | {:error, exception_or_reason, state}

  @callback close(state) :: :ok

  # API

  def connect(client, endpoint, opts), do: client.connect(endpoint, opts)

  def alive?(%Connection{client: client} = state), do: client.alive?(state)

  def request(%Request{} = request, %Connection{client: client} = state),
    do: client.request(request, state)

  def close(%Connection{client: client} = state), do: client.close(state)
end
