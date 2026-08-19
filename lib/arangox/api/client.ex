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

  @doc false
  @spec request(Arangox.conn(), keyword) :: {:ok, term} | {:error, Exception.t()}
  def request(conn, spec) do
    opts = Keyword.get(spec, :opts, [])

    with {:ok, path} <- path(Keyword.fetch!(spec, :segments)),
         {:ok, path} <-
           with_query(path, Keyword.get(spec, :query, []), Keyword.get(spec, :forced, []), opts),
         headers = Keyword.get(opts, :headers, []),
         :ok <- check_headers(headers) do
      conn
      |> Arangox.request(
        Keyword.fetch!(spec, :method),
        path,
        Keyword.get(spec, :body, ""),
        media(headers, Keyword.get(spec, :media)),
        forwarded(opts, Keyword.get(spec, :query, []))
      )
      |> answer(Keyword.get(spec, :response, :body))
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

  defp answer({:ok, _request, %Response{body: body}}, :body), do: {:ok, body}

  # A `HEAD` request has no body at all; its answer is the document revision,
  # which the server returns as a quoted `etag`. Handing back an empty body
  # would make the operation useless.
  defp answer({:ok, _request, %Response{headers: headers}}, :revision) do
    {:ok,
     headers
     |> Enum.find_value(fn {name, value} ->
       if String.downcase(to_string(name)) == "etag", do: value
     end)
     |> unquote_etag()}
  end

  defp answer({:error, exception}, _response), do: {:error, exception}

  defp unquote_etag(nil), do: nil
  defp unquote_etag(<<?", rest::binary>>), do: String.trim_trailing(rest, "\"")
  defp unquote_etag(value), do: value

  # Segments are encoded one at a time, so an interpolated value can never
  # introduce a separator: a `/` inside a collection name becomes `%2F` and
  # stays inside its own segment. Control characters are refused instead,
  # because no ArangoDB name may contain one and encoding them would only
  # move the rejection to the server.
  defp path(segments) do
    Enum.reduce_while(segments, {:ok, ""}, fn segment, {:ok, acc} ->
      {value, encode} =
        case segment do
          {:path, v} -> {to_string(v), &encode_path/1}
          v -> {to_string(v), &encode_segment/1}
        end

      if control_byte?(value) do
        {:halt,
         {:error,
          %Error{
            message:
              "a path segment cannot contain control characters; the value is not " <>
                "echoed here because it may be a credential or a transaction identifier"
          }}}
      else
        {:cont, {:ok, acc <> "/" <> encode.(value)}}
      end
    end)
  end

  defp encode_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  # Separators are kept, each part between them encoded.
  defp encode_path(value), do: value |> String.split("/") |> Enum.map_join("/", &encode_segment/1)

  defp control_byte?(<<byte, _rest::binary>>) when byte < 0x20 or byte == 0x7F, do: true
  defp control_byte?(<<_byte, rest::binary>>), do: control_byte?(rest)
  defp control_byte?(<<>>), do: false

  # An operation declares the query parameters it accepts as
  # `[snake_case_name: "wireName"]`. A caller writes the snake_case name; the
  # wire name is what ArangoDB reads. Anything the operation does not declare
  # is left in `opts` for the driver.
  #
  # `forced` pairs are the operation's own and are always sent. They carry the
  # values ArangoDB requires but a caller must not choose — the flag that
  # decides whether `PUT /_api/document/{collection}` reads or replaces, for
  # one, where the wrong value silently overwrites a collection.
  defp with_query(path, declared, forced, opts) do
    pairs =
      forced ++
        for {name, wire} <- declared, Keyword.has_key?(opts, name) do
          {wire, Keyword.fetch!(opts, name)}
        end

    case Enum.find(pairs, fn {name, value} ->
           Client.smuggling_byte?(to_string(name)) or Client.smuggling_byte?(to_string(value))
         end) do
      nil ->
        {:ok, if(pairs == [], do: path, else: path <> "?" <> URI.encode_query(pairs))}

      {name, _value} ->
        {:error,
         %Error{
           message:
             "the #{name} query parameter cannot contain carriage return, line feed, or null"
         }}
    end
  end

  defp check_headers(headers) when is_list(headers) do
    Enum.find_value(headers, :ok, fn
      {name, value} ->
        name = to_string(name)

        cond do
          String.downcase(name) in @denied_headers ->
            {:error,
             %Error{
               message:
                 "the #{String.downcase(name)} header belongs to the pool and cannot be " <>
                   "set by an Arangox.Api operation"
             }}

          Client.smuggling_byte?(name) or Client.smuggling_byte?(to_string(value)) ->
            {:error,
             %Error{
               message: "the #{name} header cannot contain carriage return, line feed, or null"
             }}

          true ->
            nil
        end

      _other ->
        {:error, %Error{message: "the :headers option must be a list of {name, value} tuples"}}
    end)
  end

  defp check_headers(_headers),
    do: {:error, %Error{message: "the :headers option must be a list of {name, value} tuples"}}

  # An operation declaring exactly one non-JSON request media gets it set as
  # the content type, which routes its body past the JSON codec and onto the
  # wire as given. JSON is never injected: the pool's `:content_type` decides
  # the default codec. A caller-supplied content type always wins.
  defp media(headers, nil), do: headers

  defp media(headers, declared) do
    if Enum.any?(headers, fn {name, _value} ->
         String.downcase(to_string(name)) == "content-type"
       end) do
      headers
    else
      headers ++ [{"content-type", declared}]
    end
  end

  # The operation's own query parameters are consumed here; everything else —
  # `:database`, `:transaction`, `:timeout` — belongs to the driver.
  defp forwarded(opts, declared) do
    Keyword.drop(opts, [:headers | Keyword.keys(declared)])
  end
end
