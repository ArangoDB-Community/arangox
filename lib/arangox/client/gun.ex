if Code.ensure_compiled?(:gun) do
  defmodule Arangox.Client.Gun do
    @moduledoc """
    Default HTTP client implementation for arangox.

    Implements the \
    [`:gun`](https://ninenines.eu/docs/en/gun/1.3/guide "documentation") \
    library. [`:gun`](https://hex.pm/packages/gun "hex.pm") must be present in your \
    deps in order for it to work.

    [documentation](https://ninenines.eu/docs/en/gun/1.3/guide)

    [hex.pm](https://hex.pm/packages/gun)
    """

    import Arangox.Endpoint
    alias :gun, as: Gun

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
      transport = if ssl?(uri), do: :tls, else: :tcp
      connect_timeout = Keyword.get(opts, :connect_timeout, 15_000)
      transport_opts = if ssl?(uri), do: :ssl_opts, else: :tcp_opts
      transport_opts = Keyword.get(opts, transport_opts, [])
      client_opts = Keyword.get(opts, :client_opts, %{})

      options = %{
        protocols: [:http],
        http_opts: %{keepalive: :infinity},
        retry: 0,
        transport: transport,
        transport_opts: transport_opts,
        connect_timeout: connect_timeout
      }

      options = Map.merge(options, client_opts)

      with(
        {:ok, pid} <- open_unix_or_tcp(uri, options),
        {:ok, _protocol} <- Gun.await_up(pid, connect_timeout)
      ) do
        {:ok, pid}
      else
        {:error, {:options, options}} ->
          exit(options)

        {:error, {:badarg, _}} ->
          exit(:badarg)

        {:error, {:shutdown, reason}} ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp open_unix_or_tcp(%URI{} = uri, options) do
      if unix?(uri) do
        uri.path
        |> String.to_charlist()
        |> Gun.open_unix(options)
      else
        uri.host
        |> String.to_charlist()
        |> Gun.open(uri.port, options)
      end
    end

    @impl true
    def request(%Request{} = request, %Connection{socket: pid} = state) do
      ref =
        Gun.request(
          pid,
          request.method |> Atom.to_string() |> String.upcase(),
          request.path,
          request.headers,
          request.body
        )

      if alive?(state) do
        do_await(pid, ref, state)
      else
        {:error, :noproc, state}
      end
    end

    defp do_await(pid, ref, state) do
      case Gun.await(pid, ref, :infinity) do
        {:response, :fin, status, headers} ->
          {:ok, %Response{status: status, headers: headers}, state}

        {:response, :nofin, status, headers} ->
          case Gun.await_body(pid, ref, :infinity) do
            {:ok, body} ->
              {:ok, %Response{status: status, headers: headers, body: body}, state}

            {:error, reason} ->
              {:error, reason, state}
          end

        {:error, reason} ->
          {:error, reason, state}
      end
    end

    @impl true
    def alive?(%Connection{socket: pid}), do: Process.alive?(pid)

    @impl true
    def close(%Connection{socket: pid}), do: Gun.close(pid)
  end
end
