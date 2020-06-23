if Code.ensure_loaded?(Mint.HTTP1) do
  defmodule Arangox.MintClient do
    @moduledoc """
    An HTTP client implementation of the \
    [`:mint`](https://hexdocs.pm/mint/Mint.HTTP.html "documentation") \
    library. Requires [`:mint`](https://hex.pm/packages/mint "hex.pm") to be
    added as a dependency.

    [__Hex.pm__](https://hex.pm/packages/mint)

    [__Documentation__](https://hexdocs.pm/mint/Mint.HTTP.html)
    """

    alias Mint.HTTP1, as: Mint

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
        true <- Mint.open?(conn)
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
      Mint doesn't support unix sockets :(
      """
    end

    defp open({:tcp, host, port}, ssl?, options) do
      scheme = if ssl?, do: :https, else: :http

      Mint.connect(scheme, host, port, options)
    end

    @impl true
    def request(
          %Request{method: method, path: path, headers: headers, body: body},
          %Connection{socket: socket} = state
        ) do
      with(
        {:ok, new_socket, ref} <-
          Mint.request(
            socket,
            method
            |> to_string()
            |> String.upcase(),
            path,
            Enum.into(headers, []),
            body
          ),
        {:ok, new_socket, buffer} <-
          do_recv(new_socket, ref)
      ) do
        do_response(ref, buffer, %{state | socket: new_socket})
      else
        {:error, new_socket, %_{reason: :closed}} ->
          {:error, :noproc, %{state | socket: new_socket}}

        {:error, new_socket, %_{reason: :closed}, _} ->
          {:error, :noproc, %{state | socket: new_socket}}

        {:error, new_socket, exception} ->
          {:error, exception, %{state | socket: new_socket}}

        {:error, new_socket, exception, _} ->
          {:error, exception, %{state | socket: new_socket}}
      end
    end

    defp do_recv(conn, ref, buffer \\ []) do
      case Mint.recv(conn, 0, :infinity) do
        {:ok, new_conn, next_buffer} ->
          if {:done, ref} in next_buffer do
            {:ok, new_conn, buffer ++ next_buffer}
          else
            do_recv(new_conn, ref, buffer ++ next_buffer)
          end

        {:error, _, _, _} = error ->
          error
      end
    end

    defp do_response(ref, buffer, state) do
      case buffer do
        [{:status, ^ref, status}, {:headers, ^ref, headers}, {:done, ^ref}] ->
          {:ok, %Response{status: status, headers: Map.new(headers)}, state}

        [{:status, ^ref, status}, {:headers, ^ref, headers}, {:data, ^ref, body}, {:done, ^ref}] ->
          {:ok, %Response{status: status, headers: Map.new(headers), body: body}, state}

        [{:status, ^ref, status}, {:headers, ^ref, headers} | rest_buffer] ->
          body =
            for kv <- rest_buffer, into: "" do
              case kv do
                {:data, ^ref, data} ->
                  data

                {:done, ^ref} ->
                  ""
              end
            end

          {:ok, %Response{status: status, headers: Map.new(headers), body: body}, state}
      end
    end

    @impl true
    def alive?(%Connection{socket: conn}), do: Mint.open?(conn)

    @impl true
    def close(%Connection{socket: conn}) do
      Mint.close(conn)

      :ok
    end
  end
end
