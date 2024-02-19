defmodule TestHelper do
  def opts(opts \\ []) do
    default_opts = [
      show_sensitive_data_on_connection_error: true,
      auth: :off,
      endpoints: [default()]
    ]

    opts_with_defaults = Keyword.merge(default_opts, opts)

    # Case if our test code has provided username and password
    if Keyword.has_key?(opts_with_defaults, :username) and
         Keyword.has_key?(opts_with_defaults, :password) do
      Keyword.put(
        opts_with_defaults,
        :auth,
        {:basic, opts_with_defaults[:username], opts_with_defaults[:password]}
      )
    else
      opts_with_defaults
    end
  end

  def unreachable, do: "http://fake_endpoint:1234"
  # default is pointing to instance with disabled authentication
  def default, do: "http://localhost:8001"
  def auth, do: "http://localhost:8529"
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
