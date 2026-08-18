defmodule Arangox.Response do
  @moduledoc """
  A response from _ArangoDB_.

  `body` is the decoded body when the pool has a JSON library configured, which
  is the default, and the raw binary otherwise.

  `headers` is a list of `{name, value}` tuples, as the client delivered them.
  The HTTP clients hand the parsed lines through — names lowercased, order and
  repeats as received. The VelocyStream client is different by wire format:
  VelocyStream carries response headers as a map, so its list can hold no
  repeated name, its order is the map's key order rather than the server's,
  and names keep the server's casing.
  """

  @type t :: %__MODULE__{
          status: pos_integer,
          headers: Arangox.headers(),
          body: Arangox.body()
        }

  @enforce_keys [:status, :headers]
  defstruct [
    :status,
    :headers,
    :body
  ]

  @plan_cache_key "planCacheKey"

  @doc """
  The key of the plan-cache entry that served this response, if one did.

  Present only when a query asked for the plan cache with `use_plan_cache: true`
  **and** the server had a cached plan to serve it from — which means the first
  execution of a statement answers `nil` and later ones answer the key, since
  the first is what populates the entry.

  The same key identifies the entry in `Arangox.plan_cache/2`, under `"hash"`.

  Answers `nil` for any response that carries no key, including one whose body
  was never decoded.

      iex> Arangox.Response.plan_cache_key(%Arangox.Response{
      ...>   status: 201,
      ...>   headers: [],
      ...>   body: %{"planCacheKey" => "11696445063967996394"}
      ...> })
      "11696445063967996394"

      iex> Arangox.Response.plan_cache_key(%Arangox.Response{
      ...>   status: 200,
      ...>   headers: [],
      ...>   body: %{"result" => []}
      ...> })
      nil
  """
  @spec plan_cache_key(t) :: binary | nil
  def plan_cache_key(%__MODULE__{body: %{@plan_cache_key => key}}) when is_binary(key), do: key
  def plan_cache_key(%__MODULE__{}), do: nil
end
