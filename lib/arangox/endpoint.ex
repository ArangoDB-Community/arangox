defmodule Arangox.Endpoint do
  @moduledoc """
  Utilities for parsing _ArangoDB_ endpoints.

      iex> Endpoint.new("http://localhost:8529")
      %Arangox.Endpoint{addr: {:tcp, "localhost", 8529}, ssl?: false}

      iex> Endpoint.new("https://localhost:8529")
      %Arangox.Endpoint{addr: {:tcp, "localhost", 8529}, ssl?: true}

      iex> Endpoint.new("http://unix:/tmp/arangodb.sock")
      %Arangox.Endpoint{addr: {:unix, "/tmp/arangodb.sock"}, ssl?: false}

  `new/1` raises on a malformed endpoint. `parse/1` is the same parser
  returning `{:ok, endpoint} | {:error, message}`, and is what
  the connection's connect callback uses: a raise from there escapes the
  `DBConnection` callback and gives a supervisor crash loop with no backoff,
  where an error tuple gives an orderly retry.

  Neither the struct nor any error message either function produces carries the
  endpoint's userinfo. The struct never did — parsing consumes the
  URI (Uniform Resource Identifier) into `:addr` and `:ssl?` and drops
  everything else — but the *configured binary* did reach logs verbatim. Use
  `redact/1` on any endpoint binary before storing or reporting it.
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

  Raises `ArgumentError` when the endpoint is malformed. Use `parse/1` on any
  path that must not raise.
  """
  @spec new(Arangox.endpoint()) :: t
  def new(endpoint) do
    case parse(endpoint) do
      {:ok, %__MODULE__{} = parsed} -> parsed
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Parses an endpoint, returning `{:ok, %Arangox.Endpoint{}}` or
  `{:error, message}`. Never raises.
  """
  @spec parse(Arangox.endpoint()) :: {:ok, t} | {:error, binary}
  def parse(endpoint) when is_binary(endpoint) do
    uri =
      endpoint
      |> URI.parse()
      |> Map.update!(:port, &do_port(&1, endpoint))

    case unix?(uri) do
      {:ok, true} -> build(do_unix(uri), uri, endpoint, :unix)
      {:ok, false} -> build(do_tcp(uri), uri, endpoint, :tcp)
      :error -> {:error, "Invalid protocol in endpoint configuration: #{shown(endpoint)}"}
    end
  end

  def parse(endpoint) do
    {:error, "Expected an endpoint binary, got: #{shown(endpoint)}"}
  end

  @doc """
  Redacts an endpoint binary that could carry a credential.

      iex> Arangox.Endpoint.redact("http://root:hunter2@localhost:8529")
      "http://[redacted]"

      iex> Arangox.Endpoint.redact("http://localhost:8529")
      "http://localhost:8529"

  This is the driver's single redaction point for endpoints.
  `Arangox.Connection` applies it where the configured endpoint is **stored**,
  not only where it is rendered, so the same call covers
  `Exception.message/1` on an `Arangox.Error`, `inspect/1` on connection state, and the
  `failed to connect` line `DBConnection` logs on every backoff cycle.

  The rule never looks for the userinfo, only for what could hide one: an
  endpoint containing an `@` **anywhere** keeps its scheme and loses the rest,
  and a value without a scheme separator is replaced entirely. Locating the
  userinfo would mean trusting the value to be a well-formed URL, and the
  values most likely to carry a password into a log are exactly the typo'd
  ones that are not.

  An endpoint with a scheme and no `@` has no userinfo to lose and passes
  through unchanged — which is what keeps host and port visible in error
  messages and logs for the ordinary, credential-free configuration. A
  redacted value does **not** parse; nothing that needs the origin may read it
  back out of a redacted binary.

  Never raises, and returns anything that is not a binary unchanged.
  """
  @spec redact(Arangox.endpoint() | term) :: Arangox.endpoint() | term
  def redact(endpoint) when is_binary(endpoint) do
    case {:binary.match(endpoint, "://"), :binary.match(endpoint, "@")} do
      {{_scheme_at, 3}, :nomatch} ->
        endpoint

      # The scheme prefix is kept only when the `@` follows it. An `@` before
      # the scheme separator means the value is not a URL whose userinfo sits
      # in the userinfo position, so no prefix of it is known to be
      # credential-free and the whole value goes.
      {{scheme_at, 3}, {at, 1}} when at > scheme_at ->
        binary_part(endpoint, 0, scheme_at + 3) <> "[redacted]"

      {_scheme, _at} ->
        "[redacted]"
    end
  end

  def redact(endpoint), do: endpoint

  # Every endpoint that reaches a message goes through here, so a malformed
  # endpoint carrying credentials cannot leak them into a connect-failure log.
  defp shown(endpoint), do: endpoint |> redact() |> inspect()

  defp build({:ok, addr}, uri, _endpoint, _kind),
    do: {:ok, %__MODULE__{addr: addr, ssl?: ssl?(uri)}}

  defp build(:error, _uri, endpoint, :unix),
    do: {:error, "Missing path in unix endpoint configuration: #{shown(endpoint)}"}

  defp build(:error, _uri, endpoint, :tcp),
    do: {:error, "Missing host or port in endpoint configuration: #{shown(endpoint)}"}

  # 80 and 443 are the two ports `URI.parse/1` fills in from the scheme, so
  # for exactly these the difference between "the user wrote it" and "the
  # parser assumed it" has to be read back off the endpoint — and only from
  # the authority: `:80` in a path or userinfo is not a port.
  defp do_port(80 = port, endpoint), do: maybe_do_port(port, endpoint)
  defp do_port(443 = port, endpoint), do: maybe_do_port(port, endpoint)
  defp do_port(port, _endpoint), do: port

  defp maybe_do_port(port, endpoint) do
    if String.ends_with?(authority(endpoint), ":" <> Integer.to_string(port)),
      do: port,
      else: nil
  end

  defp authority(endpoint) do
    case :binary.match(endpoint, "://") do
      {scheme_len, 3} ->
        rest = binary_part(endpoint, scheme_len + 3, byte_size(endpoint) - scheme_len - 3)

        case :binary.match(rest, ["/", "?", "#"]) do
          {pos, _len} -> binary_part(rest, 0, pos)
          :nomatch -> rest
        end

      :nomatch ->
        endpoint
    end
  end

  defp do_unix(%URI{path: nil}), do: :error
  defp do_unix(%URI{path: path}), do: {:ok, {:unix, path}}

  defp do_tcp(%URI{host: nil}), do: :error
  defp do_tcp(%URI{port: nil}), do: :error
  defp do_tcp(%URI{host: ""}), do: :error
  defp do_tcp(%URI{host: host, port: port}), do: {:ok, {:tcp, host, port}}

  defp ssl?(%URI{scheme: "https" <> _}), do: true
  defp ssl?(%URI{scheme: "ssl" <> _}), do: true
  defp ssl?(%URI{scheme: "tls" <> _}), do: true
  defp ssl?(_uri), do: false

  defp unix?(%URI{scheme: "http", host: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "https", host: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "tcp", host: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "ssl", host: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "tls", host: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "http+unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "https+unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "tcp+unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "ssl+unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "tls+unix"}), do: {:ok, true}
  defp unix?(%URI{scheme: "http"}), do: {:ok, false}
  defp unix?(%URI{scheme: "https"}), do: {:ok, false}
  defp unix?(%URI{scheme: "tcp"}), do: {:ok, false}
  defp unix?(%URI{scheme: "ssl"}), do: {:ok, false}
  defp unix?(%URI{scheme: "tls"}), do: {:ok, false}
  defp unix?(_uri), do: :error
end
