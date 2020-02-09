defmodule Arangox.Endpoint do
  @moduledoc """
  Utilities for parsing _ArangoDB_ endpoints.

      iex> Endpoint.new("http://localhost:8529")
      %Arangox.Endpoint{addr: {:tcp, "localhost", 8529}, ssl?: false}

      iex> Endpoint.new("https://localhost:8529")
      %Arangox.Endpoint{addr: {:tcp, "localhost", 8529}, ssl?: true}

      iex> Endpoint.new("http://unix:/tmp/arangodb.sock")
      %Arangox.Endpoint{addr: {:unix, "/tmp/arangodb.sock"}, ssl?: false}
  """

  @type addr ::
          {:unix, path :: binary}
          | {:tcp, host :: binary, port :: non_neg_integer}

  @type t :: %__MODULE__{
          addr: addr,
          ssl?: boolean
        }

  @keys [:addr, :ssl?]

  @enforce_keys @keys
  defstruct @keys

  @doc """
  Parses an endpoint and returns an `%Arangox.Endpoint{}` struct.
  """
  @spec new(Arangox.endpoint()) :: %__MODULE__{addr: addr, ssl?: boolean}
  def new(endpoint) do
    uri =
      endpoint
      |> URI.parse()
      |> Map.update!(:port, &do_port(&1, endpoint))

    %__MODULE__{addr: do_addr(uri, endpoint), ssl?: ssl?(uri, endpoint)}
  end

  defp do_port(80 = port, endpoint), do: maybe_do_port(port, endpoint)
  defp do_port(443 = port, endpoint), do: maybe_do_port(port, endpoint)
  defp do_port(port, _endpoint), do: port

  defp maybe_do_port(port, endpoint) do
    if String.contains?(endpoint, ":" <> Integer.to_string(port)), do: port, else: nil
  end

  defp do_addr(uri, endpoint) do
    if unix?(uri, endpoint), do: do_unix(uri, endpoint), else: do_tcp(uri, endpoint)
  end

  defp do_unix(%URI{path: nil}, endpoint) do
    raise ArgumentError, """
    Missing path in unix endpoint configuration: #{inspect(endpoint)}\
    """
  end

  defp do_unix(%URI{path: path}, _endpoint), do: {:unix, path}

  defp do_tcp(%URI{host: nil}, endpoint) do
    raise ArgumentError, """
    Missing host or port in endpoint configuration: #{inspect(endpoint)}\
    """
  end

  defp do_tcp(%URI{port: nil}, endpoint) do
    raise ArgumentError, """
    Missing host or port in endpoint configuration: #{inspect(endpoint)}\
    """
  end

  defp do_tcp(%URI{host: host, port: port}, _endpoint), do: {:tcp, host, port}

  defp ssl?(%URI{scheme: "https" <> _}, _endpoint), do: true
  defp ssl?(%URI{scheme: "ssl" <> _}, _endpoint), do: true
  defp ssl?(%URI{scheme: "tls" <> _}, _endpoint), do: true
  defp ssl?(_, _endpoint), do: false

  defp unix?(%URI{scheme: "http", host: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "https", host: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "tcp", host: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "ssl", host: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "tls", host: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "http+unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "https+unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "tcp+unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "ssl+unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "tls+unix"}, _endpoint), do: true
  defp unix?(%URI{scheme: "http"}, _endpoint), do: false
  defp unix?(%URI{scheme: "https"}, _endpoint), do: false
  defp unix?(%URI{scheme: "tcp"}, _endpoint), do: false
  defp unix?(%URI{scheme: "ssl"}, _endpoint), do: false
  defp unix?(%URI{scheme: "tls"}, _endpoint), do: false

  defp unix?(_, endpoint) do
    raise ArgumentError, """
    Invalid protocol in endpoint configuration: #{inspect(endpoint)}\
    """
  end
end
