defmodule Arangox.Request do
  @moduledoc nil

  alias __MODULE__
  alias Arangox.Response

  @type t :: %__MODULE__{
          method: Arangox.method(),
          path: Arangox.path(),
          headers: Arangox.headers(),
          body: Arangox.body()
        }

  @enforce_keys [:method, :path]

  defstruct [
    :method,
    :path,
    headers: [],
    body: ""
  ]

  @doc false
  # The header values treated as secrets everywhere one is rendered: the
  # authorization value is the credential itself, and the transaction
  # identifier is a bearer capability handled the same way. The
  # `Inspect` implementations for this struct and `Arangox.Connection`, and
  # the echoed-request sanitizer, all read this one list.
  @spec sensitive_headers() :: [binary]
  def sensitive_headers, do: ["authorization", "x-arango-trx-id"]

  @doc false
  # HTTP header names are case-insensitive, and a caller may set
  # `"Authorization"` on a request as legitimately as `"authorization"`. An
  # exact-key match would leave the credential visible in the one place this
  # rule exists to cover.
  @spec sensitive_header?(term) :: boolean
  def sensitive_header?(name), do: String.downcase(to_string(name)) in sensitive_headers()

  defimpl DBConnection.Query do
    def parse(request, _opts), do: request

    def describe(request, _opts), do: request

    def encode(%Request{path: "/" <> _path} = request, _params, _opts), do: request

    def encode(%Request{path: path} = request, params, opts),
      do: encode(%Request{request | path: "/" <> path}, params, opts)

    def decode(_query, %Response{} = response, _opts), do: response
  end
end

# By the time `DBConnection` can log a request — it logs the in-flight query
# on failures — the pool's authorization header and any transaction identifier
# are already merged in, so redaction has to live on `inspect/1` itself. The
# echoed request is additionally sanitized in place; this covers every other
# render.
defimpl Inspect, for: Arangox.Request do
  import Inspect.Algebra

  @redacted "[redacted]"

  def inspect(%Arangox.Request{} = request, opts) do
    fields =
      request
      |> Map.from_struct()
      |> Map.update!(:headers, &redact_headers/1)
      |> Map.to_list()

    container_doc("%Arangox.Request{", fields, "}", opts, &field/2,
      separator: ",",
      break: :strict
    )
  end

  @spec field({atom, term}, Inspect.Opts.t()) :: Inspect.Algebra.t()
  defp field({key, value}, opts) do
    concat([Atom.to_string(key), ": ", to_doc(value, opts)])
  end

  @spec redact_headers(term) :: term
  defp redact_headers(headers) when is_map(headers) do
    Map.new(headers, fn {name, value} ->
      if Arangox.Request.sensitive_header?(name), do: {name, @redacted}, else: {name, value}
    end)
  end

  defp redact_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, _value} = pair ->
        if Arangox.Request.sensitive_header?(name), do: {name, @redacted}, else: pair

      other ->
        other
    end)
  end

  defp redact_headers(headers), do: headers
end
