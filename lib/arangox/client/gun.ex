if Code.ensure_loaded?(:gun) do
  defmodule Arangox.GunClient do
    @moduledoc """
    An HTTP client implementation of the \
    [`:gun`](https://ninenines.eu/docs/en/gun/1.3/guide "documentation") \
    library. Requires [`:gun`](https://hex.pm/packages/gun "hex.pm") to be added
    as a dependency.

    [__Hex.pm__](https://hex.pm/packages/gun)

    [__Documentation__](https://ninenines.eu/docs/en/gun/1.3/guide)
    """

    alias :gun, as: Gun

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
      transport = if ssl?, do: :tls, else: :tcp
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
      transport_opts = if ssl?, do: :ssl_opts, else: :tcp_opts
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
        {:ok, pid} <- open(addr, options),
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

    defp open({:unix, path}, options) do
      path
      |> to_charlist()
      |> Gun.open_unix(options)
    end

    defp open({:tcp, host, port}, options) do
      host
      |> to_charlist()
      |> Gun.open(port, options)
    end

    @impl true
    def request(%Request{} = request, %Connection{socket: pid} = state) do
      ref =
        Gun.request(
          pid,
          request.method |> Atom.to_string() |> String.upcase(),
          request.path,
          Enum.into(request.headers, [], fn {k, v} -> {k, v} end),
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
          {:ok, %Response{status: status, headers: Map.new(headers)}, state}

        {:response, :nofin, status, headers} ->
          case Gun.await_body(pid, ref, :infinity) do
            {:ok, body} ->
              {:ok, %Response{status: status, headers: Map.new(headers), body: body}, state}

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
