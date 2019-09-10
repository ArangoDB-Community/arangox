defmodule Arangox.Endpoint do
  @moduledoc """
  Utilities for parsing _ArangoDB_ endpoints.

  See the \
  [arangosh](https://www.arangodb.com/docs/stable/programs-arangosh-examples.html) or \
  [arangojs](https://www.arangodb.com/docs/stable/drivers/js-reference-database.html) \
  documentation for examples of supported endpoint formats.
  """

  @doc """
  Parses an endpoint uri and returns a `%URI{}` struct. This is identical to
  `URI.parse/1` with the exception that the host defaults to `localhost`
  and the port to `8529`.
  """
  @spec parse(binary) :: URI.t()
  def parse(endpoint) do
    endpoint
    |> URI.parse()
    |> Map.update!(:host, &(&1 || "localhost"))
    |> Map.update!(:port, &port_for/1)
  end

  defp port_for(80), do: 8529
  defp port_for(443), do: 8529
  defp port_for(nil), do: 8529
  defp port_for(port), do: port

  @doc """
  Determines wether a binary or `%URI{}` struct is a ssl/tls endpoint.
  """
  @spec ssl?(binary | URI.t()) :: boolean
  def ssl?(%URI{scheme: nil}), do: false

  def ssl?(%URI{scheme: scheme}) do
    schemes = String.split(scheme, "+")

    "ssl" in schemes or "https" in schemes
  end

  def ssl?(endpoint) when is_binary(endpoint) do
    endpoint
    |> parse()
    |> ssl?()
  end

  @doc """
  Determines wether a binary or `%URI{}` struct is a unix endpoint.
  """
  @spec unix?(binary | URI.t()) :: boolean
  def unix?(%URI{host: host, scheme: nil}), do: host == "unix"

  def unix?(%URI{host: host, scheme: scheme}) do
    "unix" in [host | String.split(scheme, "+")]
  end

  def unix?(endpoint) when is_binary(endpoint) do
    endpoint
    |> parse()
    |> unix?()
  end
end
