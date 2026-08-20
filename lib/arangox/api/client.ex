defmodule Arangox.Api.Client do
  @moduledoc """
  The adapter every `Arangox.Api.*` operation calls.

  An operation names a method, a list of path segments, and the query
  parameters it accepts. This module turns that into a driver request, so the
  pool, timeout budget, transaction handling and error contract apply to
  `Arangox.Api` calls exactly as they do to hand-written ones. It holds no
  connection state and opens no socket: a transport change touches this
  module, never the operations above it.

  ## Options every operation accepts

    * `:database` - the database to run against. Falls back to the pool's own
      `:database`, and then to `_system`.
    * `:headers` - extra request headers as `{name, value}` tuples, for the
      header parameters an operation does not expose (`if-match`, and so on).
    * any query parameter the operation declares, written in snake_case
    * every per-request option `Arangox.request/6` accepts, such as
      `:transaction`, `:timeout` and `:request_timeout`

  ## What comes back

  A successful call answers `{:ok, body}` — the decoded response body, not a
  response struct. A success that carries no body (`204 No Content`) answers
  `{:ok, nil}`.

  Any error status answers `{:error, %Arangox.Error{}}`, carrying the HTTP
  status and ArangoDB's own `errorNum`. A `404` is an error like any other:
  ask for a document that is not there and you get
  `{:error, %Arangox.Error{status: 404}}`.

  The `!` form of each operation returns the body directly and raises on any
  error.

  ## Bounds

  Every value a caller can influence is bounded here, because every
  `Arangox.Api` call passes through:

    * path segments are percent-encoded one segment at a time, so a value
      carrying `/` or `?` becomes part of that segment instead of altering the
      path. A control character is refused outright — it is never a legitimate
      part of a name.
    * a few parameters are themselves paths — an index identifier is
      `collection/number` — and are declared as such by the operation. Their
      separators survive; everything between them is still encoded, so such a
      value can add path depth but cannot introduce a query or a fragment.
    * query and header names and values must not carry carriage return, line
      feed, or null.
    * an `authorization` or `host` header is refused: the pool's endpoint and
      credentials are not an operation's to override.
    * a refusal names the field and the rule, never the value, because a
      rejected header or path segment may be a credential or a transaction
      identifier.
  """

  alias Arangox.{Client, Error, Response}

  @denied_headers ["authorization", "host"]

  @headers_shape "the :headers option must be a list of {name, value} tuples"

  # The spec is an operation's whole description of itself:
  #
  #   * `:method` (required) — the HTTP method atom
  #   * `:segments` (required) — the path, one entry per segment: a literal
  #     binary, a caller argument, or `{:path, value}` for an argument that
  #     is itself a path (an index identifier is `collection/number`)
  #   * `:query` — the query parameters the operation offers, as
  #     `[snake_case_name: "wireName"]`; a caller passes the snake_case name
  #     in the options, and the wire name is what ArangoDB reads
  #   * `:forced` — `{"wireName", value}` pairs sent unconditionally, for
  #     parameters ArangoDB requires but a caller must not choose
  #   * `:body` — the request body, default `""`
  #   * `:media` — a non-JSON request media type, set as the content type
  #     when the caller supplies none of their own
  #   * `:response` — `:body` (default), or `:revision` for a HEAD operation
  #     whose answer is the `etag` header
  #   * `:opts` — the caller's options: `:headers`, the offered query
  #     parameters, and everything the driver accepts per request
  #
  # `test/support/api_surface.ex` parses these same keys out of the operation
  # sources for the surface gates; a key added here needs reading there too.
  @doc false
  @spec request(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def request(conn, spec) do
    method = Keyword.fetch!(spec, :method)
    segments = Keyword.fetch!(spec, :segments)
    declared = Keyword.get(spec, :query, [])
    forced = Keyword.get(spec, :forced, [])
    body = Keyword.get(spec, :body, "")
    media = Keyword.get(spec, :media)
    response = Keyword.get(spec, :response, :body)
    opts = Keyword.get(spec, :opts, [])
    headers = Keyword.get(opts, :headers, [])

    with {:ok, path} <- path(segments),
         {:ok, path} <- with_query(path, declared, forced, opts),
         :ok <- check_headers(headers) do
      conn
      |> Arangox.request(
        method,
        path,
        body,
        headers_with_media(headers, media),
        forwarded(opts, declared)
      )
      |> answer(response)
    end
  end

  @doc false
  @spec request!(Arangox.conn(), keyword) :: term
  def request!(conn, spec) do
    case request(conn, spec) do
      {:ok, body} -> body
      {:error, exception} -> raise exception
    end
  end

  ## The path

  defp path(segments) do
    Enum.reduce_while(segments, {:ok, ""}, fn segment, {:ok, acc} ->
      case encode(segment) do
        {:ok, encoded} -> {:cont, {:ok, acc <> "/" <> encoded}}
        {:error, _exception} = refusal -> {:halt, refusal}
      end
    end)
  end

  # A segment declared `{:path, value}` keeps its separators, because such a
  # value is itself a path — an index identifier is `collection/number`. The
  # parts between the separators are escaped like any other segment, so the
  # value can add path depth but cannot introduce a query or a fragment.
  defp encode({:path, value}) do
    with {:ok, value} <- checked(value) do
      {:ok, value |> String.split("/") |> Enum.map_join("/", &escape/1)}
    end
  end

  # Every other segment has its separators escaped, so an interpolated value
  # cannot alter the address: a `/` inside a collection name becomes `%2F` and
  # stays inside its own segment.
  defp encode(value) do
    with {:ok, value} <- checked(value), do: {:ok, escape(value)}
  end

  # Control characters are refused rather than escaped: no ArangoDB name may
  # contain one, so escaping would only move the rejection to the server.
  defp checked(value) do
    value = to_string(value)

    if control_byte?(value) do
      refuse(
        "a path segment cannot contain control characters; the value is not " <>
          "echoed here because it may be a credential or a transaction identifier"
      )
    else
      {:ok, value}
    end
  end

  defp escape(value), do: URI.encode(value, &URI.char_unreserved?/1)

  defp control_byte?(<<byte, _rest::binary>>) when byte < 0x20 or byte == 0x7F, do: true
  defp control_byte?(<<_byte, rest::binary>>), do: control_byte?(rest)
  defp control_byte?(<<>>), do: false

  ## The query string

  defp with_query(path, declared, forced, opts) do
    pairs = forced ++ offered(declared, opts)

    case Enum.find(pairs, fn {name, value} -> smuggles?(name) or smuggles?(value) end) do
      nil ->
        {:ok, append_query(path, pairs)}

      # Echoing the name is safe here, unlike in `check_header/1`: query wire
      # names are operation-authored literals, never caller input.
      {name, _value} ->
        refuse("the #{name} query parameter cannot contain carriage return, line feed, or null")
    end
  end

  # An operation declares the query parameters it accepts as
  # `[snake_case_name: "wireName"]`. A caller writes the snake_case name; the
  # wire name is what ArangoDB reads. Anything the operation does not declare
  # is left in `opts` for the driver.
  defp offered(declared, opts) do
    for {name, wire} <- declared,
        Keyword.has_key?(opts, name),
        do: {wire, Keyword.fetch!(opts, name)}
  end

  defp append_query(path, []), do: path
  defp append_query(path, pairs), do: path <> "?" <> URI.encode_query(pairs)

  # The operation's own query parameters are consumed here; everything else —
  # `:database`, `:transaction`, `:timeout` — belongs to the driver.
  defp forwarded(opts, declared) do
    Keyword.drop(opts, [:headers | Keyword.keys(declared)])
  end

  ## The headers

  defp check_headers(headers) when is_list(headers) do
    Enum.reduce_while(headers, :ok, fn header, :ok ->
      case check_header(header) do
        :ok -> {:cont, :ok}
        {:error, _exception} = refusal -> {:halt, refusal}
      end
    end)
  end

  defp check_headers(_headers), do: refuse(@headers_shape)

  defp check_header({name, value}) do
    name = name |> to_string() |> String.downcase()

    cond do
      name in @denied_headers ->
        refuse(
          "the #{name} header belongs to the pool and cannot be " <>
            "set by an Arangox.Api operation"
        )

      # The offending name cannot be named without repeating the refused
      # bytes into the message, and from there into whatever logs it.
      smuggles?(name) ->
        refuse("a header name cannot contain carriage return, line feed, or null")

      smuggles?(value) ->
        refuse("the #{name} header cannot contain carriage return, line feed, or null")

      true ->
        :ok
    end
  end

  defp check_header(_other), do: refuse(@headers_shape)

  # An operation declaring exactly one non-JSON request media gets it set as
  # the content type, which routes its body past the JSON codec and onto the
  # wire as given. JSON is never injected: the pool's `:content_type` decides
  # the default codec. A caller-supplied content type always wins.
  defp headers_with_media(headers, nil), do: headers

  defp headers_with_media(headers, declared) do
    if has_header?(headers, "content-type"),
      do: headers,
      else: headers ++ [{"content-type", declared}]
  end

  # HTTP does not distinguish header name case, and a caller may write either
  # form, so a name is matched case-insensitively wherever one is looked up.
  # Only the caller-written key is normalised: the sought `name` must already
  # be lowercase.
  defp header(headers, name) do
    Enum.find_value(headers, fn {key, value} -> if named?(key, name), do: value end)
  end

  defp has_header?(headers, name) do
    Enum.any?(headers, fn {key, _value} -> named?(key, name) end)
  end

  defp named?(key, name), do: String.downcase(to_string(key)) == name

  ## The answer

  defp answer({:ok, _request, %Response{body: body}}, :body), do: {:ok, body}

  # A `HEAD` request has no body at all; its answer is the document revision,
  # which the server returns as a quoted `etag`. Handing back an empty body
  # would make the operation useless.
  defp answer({:ok, _request, %Response{headers: headers}}, :revision) do
    {:ok, headers |> header("etag") |> unquote_etag()}
  end

  defp answer({:error, exception}, _response), do: {:error, exception}

  defp unquote_etag(nil), do: nil
  defp unquote_etag(<<?", rest::binary>>), do: String.trim_trailing(rest, "\"")
  defp unquote_etag(value), do: value

  ## Refusals

  # A refusal names the field and the rule, never the value: a rejected header
  # or path segment may be a credential or a transaction identifier.
  defp refuse(message), do: {:error, %Error{message: message}}

  defp smuggles?(value), do: Client.smuggling_byte?(to_string(value))
end
