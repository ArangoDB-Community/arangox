defmodule TestClient do
  alias Arangox.{
    Connection,
    Request,
    Response
  }

  @behaviour Arangox.Client

  @impl true
  def connect(_endpoint, _opts), do: {:ok, :socket}

  @impl true
  def alive?(%Connection{client: __MODULE__}), do: true

  @impl true
  def request(%Request{}, opts, %Connection{client: __MODULE__} = state) when is_list(opts),
    do: {:ok, struct(Response, []), state}

  @impl true
  def close(%Connection{client: __MODULE__}), do: :ok
end
