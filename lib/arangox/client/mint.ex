if Code.ensure_compiled?(Mint.HTTP) do
  defmodule Arangox.MintClient do
    @moduledoc """
    An HTTP client implementation of the \
    [`:mint`](https://hexdocs.pm/mint/Mint.HTTP.html "documentation") \
    library. Requires [`:mint`](https://hex.pm/packages/mint "hex.pm") to be
    added as a dependency.

    [__Hex.pm__](https://hex.pm/packages/mint)

    [__Documentation__](https://hexdocs.pm/mint/Mint.HTTP.html)
    """

    alias Mint.HTTP

    alias Arangox.{
      Client,
      Connection,
      Endpoint,
      Request,
      Response
    }

    @behaviour Client

    @impl true
    def connect(%Endpoint{addr: addr, ssl?: ssl?}, opts) do
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
      transport_opts = if ssl?, do: :ssl_opts, else: :tcp_opts
      transport_opts = Keyword.get(opts, transport_opts, [])
      transport_opts = Keyword.merge([timeout: connect_timeout], transport_opts)

      transport_opts =
        if ssl?,
          do: Keyword.put_new(transport_opts, :verify, :verify_none),
          else: transport_opts

      client_opts = Keyword.get(opts, :client_opts, [])
      options = Keyword.merge([transport_opts: transport_opts], client_opts)
      options = Keyword.merge(options, mode: :passive)

      with(
        {:ok, conn} <- open(addr, ssl?, options),
        true <- HTTP.open?(conn)
      ) do
        {:ok, conn}
      else
        {:error, exception} ->
          {:error, exception}

        false ->
          {:error, "connection lost"}
      end
    end

    defp open({:unix, _path}, _ssl?, _options) do
      raise ArgumentError, """
      Mint doesn't accept unix sockets yet :(
      """
    end

    defp open({:tcp, host, port}, ssl?, options) do
      scheme = if ssl?, do: :https, else: :http

      HTTP.connect(scheme, host, port, options)
    end

    @impl true
    def request(%Request{} = request, %Connection{} = state) do
      {:ok, conn, ref} =
        HTTP.request(
          state.socket,
          request.method |> Atom.to_string() |> String.upcase(),
          request.path,
          Enum.into(request.headers, [], fn {k, v} -> {k, v} end),
          request.body
        )

      {new_conn, result} =
        case HTTP.recv(conn, 0, :infinity) do
          {:ok, new_conn, stream} ->
            {new_conn, stream}

          {:error, new_conn, exception, _stream} ->
            {new_conn, exception}
        end

      new_state = %{state | socket: new_conn}

      if alive?(new_state) do
        case result do
          [
            {:status, ^ref, status},
            {:headers, ^ref, headers},
            {:done, ^ref}
          ] ->
            {:ok, %Response{status: status, headers: Map.new(headers)}, new_state}

          [
            {:status, ^ref, status},
            {:headers, ^ref, headers},
            {:data, ^ref, body},
            {:done, ^ref}
          ] ->
            {:ok, %Response{status: status, headers: Map.new(headers), body: body}, new_state}

          %_{} = exception ->
            {:error, exception, new_state}
        end
      else
        {:error, :noproc, new_state}
      end
    end

    @impl true
    def alive?(%Connection{socket: conn}), do: HTTP.open?(conn)

    @impl true
    def close(%Connection{socket: conn}) do
      HTTP.close(conn)

      :ok
    end
  end
end
