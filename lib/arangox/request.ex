defmodule Arangox.Request do
  @moduledoc nil

  alias __MODULE__
  alias Arangox.Response

  @type t :: %__MODULE__{
          method: Arangox.method(),
          path: Arangox.path(),
          headers: [Arangox.header()],
          body: Arangox.body()
        }

  @enforce_keys [:method, :path]

  defstruct [
    :method,
    :path,
    headers: [],
    body: ""
  ]

  defimpl DBConnection.Query do
    def parse(request, _opts), do: request

    def describe(request, _opts), do: request

    def encode(%Request{path: "/" <> _path, body: ""} = request, _params, _opts), do: request

    def encode(%Request{path: "/" <> _path, body: body} = request, _params, _opts) do
      %Request{request | body: Arangox.json_library().encode!(body)}
    end

    def encode(%Request{path: path} = request, params, opts) do
      encode(%Request{request | path: "/" <> path}, params, opts)
    end

    def decode(_query, %Response{body: nil} = response, _opts), do: response

    def decode(_query, %Response{body: body} = response, _opts) do
      %Response{response | body: Arangox.json_library().decode!(body)}
    end
  end
end
