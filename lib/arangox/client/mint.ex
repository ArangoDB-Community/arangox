if Code.ensure_compiled?(Mint.HTTP) do
  defmodule Arangox.Client.Mint do
    @moduledoc """
    An HTTP client implementation for arangox.

    Implements the \
    [`Mint`](https://hexdocs.pm/mint/Mint.HTTP.html "documentation") \
    library. Add [`:mint`](https://hex.pm/packages/mint "hex.pm") to your deps and
    pass this module to the `:client` start option to use it:

        Arangox.start_link(client: Arangox.Client.Mint)

    [documentation](https://hexdocs.pm/mint/Mint.HTTP.html)

    [hex.pm](https://hex.pm/packages/mint)
    """

    import Arangox.Endpoint
    alias Mint.HTTP

    alias Arangox.{
      Client,
      Request,
      Response,
      Connection
    }

    @behaviour Client

    @impl true
    def connect(endpoint, opts) do
      uri = parse(endpoint)
      connect_timeout = Keyword.get(opts, :connect_timeout, 15_000)
      transport_opts = if ssl?(uri), do: :ssl_opts, else: :tcp_opts
      transport_opts = Keyword.get(opts, transport_opts, [])
      transport_opts = Keyword.merge([timeout: connect_timeout], transport_opts)

      transport_opts =
        if ssl?(uri),
          do: Keyword.put_new(transport_opts, :verify, :verify_none),
          else: transport_opts

      client_opts = Keyword.get(opts, :client_opts, [])
      options = Keyword.merge([transport_opts: transport_opts], client_opts)
      options = Keyword.merge(options, mode: :passive)

      with(
        {:ok, conn} <- open_unix_or_tcp(uri, options),
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

    defp open_unix_or_tcp(%URI{host: host, port: port} = uri, options) do
      if unix?(uri) do
        {:error, ":mint doesn't accept paths to unix sockets :("}
      else
        scheme = if ssl?(uri), do: :https, else: :http

        HTTP.connect(scheme, host, port, options)
      end
    end

    @impl true
    def request(%Request{} = request, %Connection{} = state) do
      {:ok, conn, ref} =
        HTTP.request(
          state.socket,
          request.method |> Atom.to_string() |> String.upcase(),
          request.path,
          request.headers,
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
            {:ok, %Response{status: status, headers: headers}, new_state}

          [
            {:status, ^ref, status},
            {:headers, ^ref, headers},
            {:data, ^ref, body},
            {:done, ^ref}
          ] ->
            {:ok, %Response{status: status, headers: headers, body: body}, new_state}

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
