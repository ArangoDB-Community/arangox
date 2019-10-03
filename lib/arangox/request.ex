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
    headers: %{},
    body: ""
  ]

  defimpl DBConnection.Query do
    def parse(request, _opts), do: request

    def describe(request, _opts), do: request

    def encode(%Request{path: "/" <> _path} = request, _params, _opts), do: request

    def encode(%Request{path: path} = request, params, opts),
      do: encode(%Request{request | path: "/" <> path}, params, opts)

    def decode(_query, %Response{} = response, _opts), do: response
  end
end
