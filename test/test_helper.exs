defmodule TestHelper do
  def opts(opts \\ []) do
    opts_with_defaults = Keyword.merge([show_sensitive_data_on_connection_error: true], opts)

    case Keyword.get(opts_with_defaults, :auth_mode, :not_present) do
      :not_present ->
        Keyword.put(opts_with_defaults, :auth, Arangox.Auth.off())

      _ ->
        opts_with_defaults
    end
  end

  def unreachable, do: "http://fake_endpoint:1234"
  def default, do: "http://localhost:8529"
  def no_auth, do: "http://localhost:8001"
  def ssl, do: "ssl://localhost:8002"
  def failover_1, do: "http://localhost:8003"
  def failover_2, do: "http://localhost:8004"
  def failover_3, do: "http://localhost:8005"

  def failover_callback(exception, self) do
    send(self, {:tuple, exception})
  end
end

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
  def request(%Request{}, %Connection{client: __MODULE__} = state),
    do: {:ok, struct(Response, []), state}

  @impl true
  def close(%Connection{client: __MODULE__}), do: :ok
end

{os_type, _} = :os.type()

excludes = List.delete([:unix], os_type)

assert_timeout = String.to_integer(System.get_env("ELIXIR_ASSERT_TIMEOUT") || "15000")

ExUnit.start(
  exclude: excludes,
  assert_receive_timeout: assert_timeout,
  capture_log: true
)
