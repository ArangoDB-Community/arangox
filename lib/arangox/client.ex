defmodule Arangox.Client do
  @moduledoc """
  HTTP client behaviour for `Arangox`. Arangox uses client implementations to
  perform all it's connection and execution operations.

  To use an http library other than `:gun` or `:mint`, implement this behaviour
  in a module and pass that module to the `:client` start option.
  """

  alias Arangox.{
    Connection,
    Request,
    Response
  }

  @type socket :: any
  @type exception_or_reason :: any

  @doc """
  Receives an `Arangox.Endpoint` struct and all the start options from `Arangox.start_link/1`.

  The `socket` returned from this callback gets placed in the `:socket` field
  of an `Arango.Connection` struct (a connection's state) to be used by the
  other callbacks as needed. It can be anything, a tuple, another struct, whatever
  the client needs.

  It's up to the client to consolidate the `:connect_timeout`, `:transport_opts`
  and `:client_opts` options.
  """
  @callback connect(endpoint :: Endpoint.t(), start_options :: [Arangox.start_option()]) ::
              {:ok, socket} | {:error, exception_or_reason}

  @callback alive?(state :: Connection.t()) :: boolean

  @doc """
  Receives a `Arangox.Request` struct and a connection's state (an `Arangox.Connection`
  struct), and returns an `Arangox.Response` struct or error (or exception struct),
  along with the new state (which doesn't necessarily need to change).

  Arangox handles the encoding and decoding of request and response bodies, and merging headers.

  If a connection is lost, this may return `{:error, :noproc, state}` to force a disconnect,
  otherwise an attempt to reconnect may not be made until the next request hitting this process
  fails.
  """
  @callback request(request :: Request.t(), state :: Connection.t()) ::
              {:ok, Response.t(), Connection.t()} | {:error, exception_or_reason, Connection.t()}

  @callback close(state :: Connection.t()) :: :ok

  # API

  @spec connect(module, Endpoint.t(), [Arangox.start_option()]) ::
          {:ok, socket} | {:error, exception_or_reason}
  def connect(client, endpoint, start_options), do: client.connect(endpoint, start_options)

  @spec alive?(Connection.t()) :: boolean
  def alive?(%Connection{client: client} = state), do: client.alive?(state)

  @spec request(Request.t(), Connection.t()) ::
          {:ok, Response.t(), Connection.t()} | {:error, exception_or_reason, Connection.t()}
  def request(%Request{} = request, %Connection{client: client} = state),
    do: client.request(request, state)

  @spec close(Connection.t()) :: :ok
  def close(%Connection{client: client} = state), do: client.close(state)
end
