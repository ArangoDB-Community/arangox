defmodule TestHelper do
  @moduledoc """
  Shared helpers and the named endpoints the integration tier connects to.

  The endpoints below map onto the services in `docker-compose.yml`. Always go
  through these accessors rather than inlining URLs — the ports move as the
  compose topology changes.
  """

  def opts(opts \\ []) do
    default_opts = [
      pool_size: 10,
      show_sensitive_data_on_connection_error: true
    ]

    Keyword.merge(default_opts, opts)
  end

  def unreachable, do: "http://fake_endpoint:1234"
  # default is pointing to instance with disabled authentication
  def default, do: "http://localhost:8529"
  def auth, do: "http://localhost:8001"
  def ssl, do: "ssl://localhost:8002"
  # The VelocyStream endpoint. It is the `resilient_single` container, which is
  # pinned to 3.11 for exactly this reason: 3.12 removed the protocol, so a
  # VelocyStream test aimed at the 3.12 services tests nothing but the removal.
  # Any of the three ports serves — these tests read and authenticate, and
  # neither needs the active-failover leader.
  def vst, do: "http://localhost:8003"

  def failover_1, do: "http://localhost:8003"
  def failover_2, do: "http://localhost:8004"
  def failover_3, do: "http://localhost:8005"
  # The three coordinators of the `cluster` compose service, no auth. Their
  # server IDs are distinct; a transaction begun through one is addressable
  # through the others.
  def cluster_1, do: "http://localhost:8006"
  def cluster_2, do: "http://localhost:8007"
  def cluster_3, do: "http://localhost:8008"

  def failover_callback(exception, self) do
    send(self, {:tuple, exception})
  end

  @doc """
  Stops a pool started with `Arangox.start_link/1`.

  The pool is linked to the test process, so by the time an `on_exit` runs it
  may already be shutting down on its own; `GenServer.stop/1` then exits, and
  that exit means the shutdown already happened.
  """
  def stop_pool(pool) do
    if Process.alive?(pool), do: GenServer.stop(pool)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Waits, bounded, for a unix socket file to appear.

  The listener binding it is a separate OS process, so the file appearing is
  the only signal that a connect can succeed; a fixed sleep either wastes the
  whole wait or loses the race on a slow machine.
  """
  def await_unix_socket!(path, attempts \\ 100)

  def await_unix_socket!(path, 0) do
    raise "#{path} never appeared; is a unix-socket-capable nc on PATH?"
  end

  def await_unix_socket!(path, attempts) do
    unless File.exists?(path) do
      Process.sleep(20)
      await_unix_socket!(path, attempts - 1)
    end

    :ok
  end

  @doc """
  Cheap TCP probe of the primary endpoint, used to fail the integration tier
  fast when the containers aren't up.
  """
  def integration_endpoint_reachable? do
    uri = URI.parse(default())
    host = String.to_charlist(uri.host || "localhost")
    port = uri.port || 8529

    case :gen_tcp.connect(host, port, [:binary, active: false], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end
end

{os_type, _} = :os.type()

# The suite has three tiers:
#
#   * unit      — no network at all, `async: true`
#   * protocol  — real clients against `Arangox.ProtocolServer` on an ephemeral
#                 local port, `async: true`
#   * integration — real ArangoDB from `docker-compose.yml`, tagged
#                 `:integration` and excluded here so a fresh clone is green
#                 without Docker. `mix test.integration` opts back in.
excludes = [:integration] ++ List.delete([:unix], os_type)

assert_timeout = String.to_integer(System.get_env("ELIXIR_ASSERT_TIMEOUT") || "15000")

ExUnit.start(
  exclude: excludes,
  assert_receive_timeout: assert_timeout,
  capture_log: true
)

# `mix test` merges the CLI's `--include`/`--only` into the config before this
# file finishes, so this sees the tier the caller actually asked for. When the
# integration tier is requested but nothing is listening on the primary
# endpoint, say so plainly instead of emitting a wall of connection failures.
#
# Set ARANGOX_SKIP_DOCKER_CHECK=1 to bypass (e.g. counting tests, or pointing
# the suite at a database that isn't on localhost).
if :integration in List.wrap(ExUnit.configuration()[:include]) and
     System.get_env("ARANGOX_SKIP_DOCKER_CHECK") in [nil, "", "0"] and
     not TestHelper.integration_endpoint_reachable?() do
  IO.puts(:stderr, """

  The integration tier needs ArangoDB running, but nothing is listening on \
  #{TestHelper.default()}.

  Start the containers from docker-compose.yml first:

      docker compose up --detach --wait

  Then re-run `mix test.integration`. To tear them down afterwards:

      docker compose down

  (Set ARANGOX_SKIP_DOCKER_CHECK=1 to skip this check.)
  """)

  System.halt(1)
end
