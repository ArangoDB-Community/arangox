defmodule Arangox.Api.Client do
  @moduledoc """
  The adapter every `Arangox.Api.*` operation calls.

  Operations end in `client.request/1` with a request map; this module
  translates that map into `Arangox.request/6`, so the driver's pool,
  timeout budget, transaction handling, and error contract apply to
  `Arangox.Api` calls exactly as they do to hand-written ones. It holds no
  connection state and opens no socket of its own — a transport change
  touches this module, not the 243 operations above it.

  ## Options

  The `opts` keyword list of every operation accepts:

    * `:conn` (required) - the pool or connection to run the request on
    * `:headers` - a list of `{name, value}` tuples of extra request headers,
      for the header parameters the surface does not expose (`if-match`,
      `if-none-match`, ...), appended after the pool's own headers
    * every per-request option `Arangox.request/6` accepts - `:database`,
      `:transaction`, `:timeout`, and the rest are forwarded as given

  An operation that declares exactly one non-JSON request media type
  (`/_api/import` takes `text/plain` JSON lines) gets it set as the request's
  `content-type`, which routes its body past the JSON codec and onto the wire
  raw; a caller-supplied `content-type` still wins. An operation declaring
  several types leaves the choice to the caller, whose value may need more
  than the bare type (a multipart boundary, say).

  ## Bounds

  Every value a caller can influence is bounded here, because every
  `Arangox.Api` call passes through here:

    * a path parameter whose value could alter the path — `/`, `?`, `#`, `%`
      or a control character — is refused before a request is built. The
      operation's url already carries the value interpolated, so re-encoding it
      after the fact cannot be done soundly; refusal matches the rule the
      driver applies to `:database`. Every other value is percent-encoded per path segment.
    * query and header names and values must not carry CR, LF, or NUL.
    * a refusal names the field and the rule, never the value: a rejected
      header or path segment may be a credential or a transaction capability
  .
    * the url must be a rooted path: an operation-supplied scheme or host is
      refused, and so is an `authorization` or `host` header — the pool's
      endpoint and credentials are not an operation's to override.
  """

  alias Arangox.{Client, Error, Response}

  @header_denylist ["authorization", "host"]

  @spec request(map) :: {:ok, Response.t()} | {:error, any}
  def request(%{url: url, method: method} = request_map)
      when is_binary(url) and is_atom(method) do
    opts = Map.get(request_map, :opts, [])

    conn =
      Keyword.get(opts, :conn) ||
        raise ArgumentError,
              "Arangox.Api operations need a :conn option naming the pool, " <>
                "e.g. Arangox.Api.Administration.get_version(conn: conn)"

    headers = Keyword.get(opts, :headers, [])
    forward_opts = Keyword.drop(opts, [:conn, :client, :headers])

    with {:ok, path} <- bound_path(url, Map.get(request_map, :args, [])),
         {:ok, path} <- append_query(path, Map.get(request_map, :query, [])),
         :ok <- bound_headers(headers) do
      case Arangox.request(
             conn,
             method,
             path,
             Map.get(request_map, :body, ""),
             with_declared_media(headers, Map.get(request_map, :request, [])),
             forward_opts
           ) do
        {:ok, _request, %Response{} = response} -> {:ok, response}
        {:error, _reason} = error -> error
      end
    end
  end

  # The pool's scheme and host are not an operation's to override, so the
  # url must be a rooted path. `//host/path` is scheme-relative, not rooted.
  defp bound_path("/" <> rest, args) when binary_part(rest, 0, min(byte_size(rest), 1)) != "/" do
    with :ok <- check_path_args(args) do
      {:ok, encode_segments("/" <> rest)}
    end
  end

  defp bound_path(url, _args) do
    {:error,
     %Error{
       message:
         "an Arangox.Api operation's url must be a rooted path; the pool's scheme and host " <>
           "cannot be overridden, got: #{inspect(url)}"
     }}
  end

  # A path parameter is already interpolated into the url by the operation,
  # so its position cannot be recovered; a value that could alter path
  # structure is therefore refused rather than encoded, and everything else is
  # safe to encode segment-wise because it cannot cross a segment boundary.
  defp check_path_args([]), do: :ok
  defp check_path_args([{:body, _value} | rest]), do: check_path_args(rest)

  defp check_path_args([{name, value} | rest]) do
    if path_altering_byte?(to_string(value)) do
      {:error,
       %Error{
         message:
           "the #{name} path parameter cannot contain \"/\", \"?\", \"#\", \"%\" or " <>
             "control characters, since they would alter the request path"
       }}
    else
      check_path_args(rest)
    end
  end

  defp path_altering_byte?(value), do: Client.path_altering_byte?(value)

  # Percent-encodes everything outside RFC 3986's unreserved set, segment by
  # segment: static segments come out unchanged, interpolated values carrying
  # spaces or unicode become legal path bytes. The same encoder the request
  # seam applies to `:database` and cursor identifiers.
  defp encode_segments(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)
  end

  defp append_query(path, []), do: {:ok, path}

  defp append_query(path, query) do
    case Enum.find(query, fn {name, value} ->
           smuggling_byte?(to_string(name)) or smuggling_byte?(to_string(value))
         end) do
      nil ->
        {:ok, path <> "?" <> URI.encode_query(query)}

      {name, _value} ->
        {:error,
         %Error{
           message:
             "the #{name} query parameter cannot contain carriage return, line feed, " <>
               "or null"
         }}
    end
  end

  defp bound_headers(headers) when is_list(headers) do
    Enum.find_value(headers, :ok, fn
      {name, header_value} ->
        name = to_string(name)

        cond do
          String.downcase(name) in @header_denylist ->
            {:error,
             %Error{
               message:
                 "the #{String.downcase(name)} header belongs to the pool and cannot be " <>
                   "set by an Arangox.Api operation"
             }}

          smuggling_byte?(name) or smuggling_byte?(to_string(header_value)) ->
            {:error,
             %Error{
               message: "the #{name} header cannot contain carriage return, line feed, or null"
             }}

          true ->
            nil
        end

      _other ->
        {:error,
         %Error{
           message: "the :headers option must be a list of {name, value} tuples since 0.8"
         }}
    end)
  end

  defp bound_headers(_headers) do
    {:error,
     %Error{message: "the :headers option must be a list of {name, value} tuples since 0.8"}}
  end

  defp smuggling_byte?(value), do: Client.smuggling_byte?(value)

  # An operation declares its request media in the request map
  # (`request: [{"text/plain; charset=utf-8", :map}]`). A non-JSON type is
  # what routes the body past the JSON codec at the encode seam, so it is set
  # as the request's content type — only when the operation declares exactly
  # one type and the caller has not chosen their own. JSON is never injected:
  # the pool's `:content_type` must keep deciding the default codec. Several
  # declared types leave the choice to the caller, whose value may need more
  # than the bare type (a multipart boundary, say).
  defp with_declared_media(headers, [{media, _schema}]) do
    cond do
      media |> media_type() |> json_media?() -> headers
      Enum.any?(headers, fn {name, _value} -> content_type?(name) end) -> headers
      true -> headers ++ [{"content-type", media}]
    end
  end

  defp with_declared_media(headers, _zero_or_many), do: headers

  defp media_type(value) do
    value
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp json_media?(media), do: Client.json_media?(media)

  defp content_type?(name), do: String.downcase(to_string(name)) == "content-type"
end
