defmodule Arangox.ConnectionTest.ScriptClient do
  @moduledoc """
  A scripted `Arangox.Client` for connect-pipeline tests.

  Keyed by the endpoint's host, so `"http://a:1"` is scripted under `"a"`:

      %{
        "a" => %{connect: {:error, :econnrefused}},
        "b" => %{responses: %{"/_admin/server/availability" => {503, "{}"}}},
        "c" => %{responses: %{"/_api/version" => {200, ~s({"version":"3.12.5"})}}}
      }

  A response is `{status, body}`, or `{status, headers, body}` when the test
  needs response headers (the leader-redirect header, for instance).

  Anything unscripted answers `200 {}`. Every socket handed out is unique and
  every open, request and close is recorded, so a test can assert exactly which
  sockets the pipeline still owns when it returns.

  Deliberately returns **bare reasons** rather than `%Arangox.Error{}` from
  `connect/2` and `request/3`. It is the standing regression test for the legacy
  adapter in `Arangox.Connection`: a third-party client written before the
  one-error contract must still degrade to a usable error rather than
  to a `BadMapError`. Everything arangox ships returns the struct.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Endpoint, Request, Response}

  @name __MODULE__.Agent

  def start(script) do
    # Supervised rather than linked: ExUnit waits for a supervised child to
    # terminate before finishing the test, so the registered name is free
    # before the next test calls this.
    ExUnit.Callbacks.start_supervised!(%{
      id: @name,
      start: {Agent, :start_link, [fn -> %{script: script, events: []} end, [name: @name]]}
    })

    :ok
  end

  def events, do: @name |> Agent.get(& &1.events) |> Enum.reverse()
  def opened, do: for({:open, socket} <- events(), do: socket)
  def closed, do: for({:close, socket} <- events(), do: socket)
  def requests, do: for({:request, host, path} <- events(), do: {host, path})

  defp record(event), do: Agent.update(@name, &%{&1 | events: [event | &1.events]})
  defp entry(host), do: Agent.get(@name, &Map.get(&1.script, host, %{}))

  @impl true
  def connect(%Endpoint{addr: {:tcp, host, _port}}, _opts) do
    case Map.get(entry(host), :connect, :ok) do
      :ok ->
        socket = {host, System.unique_integer([:positive])}
        record({:open, socket})
        {:ok, socket}

      {:error, reason} ->
        record({:refused, host})
        {:error, reason}
    end
  end

  @impl true
  def alive?(%Connection{}), do: true

  @impl true
  def request(%Request{path: path}, _opts, %Connection{socket: {host, _id}} = state) do
    record({:request, host, path})

    case host |> entry() |> Map.get(:responses, %{}) |> Map.get(path, {200, "{}"}) do
      {:error, reason} ->
        {:error, reason, state}

      {status, body} ->
        {:ok, %Response{status: status, headers: [], body: body}, state}

      {status, headers, body} ->
        {:ok, %Response{status: status, headers: Map.new(headers), body: body}, state}
    end
  end

  @impl true
  def close(%Connection{socket: socket}) do
    record({:close, socket})
    :ok
  end
end

defmodule Arangox.ConnectionTest.RaisingJson do
  @moduledoc """
  A `:json_library` whose decode raises, for the guard around the connect
  probes: the library is user-pluggable code running inside `connect/1`.
  """

  def decode(_binary), do: raise("this library cannot decode")
  def decode!(_binary), do: raise("this library cannot decode")
  def encode!(_term), do: raise("this library cannot encode")
end

defmodule Arangox.ConnectionTest do
  @moduledoc """
  The connect pipeline: socket ownership, the failover walk, and
  server-version discovery.

  `async: false` throughout — the real-socket tests count VM ports, which is
  global state, and the scripted client registers itself under a fixed name.

  The real-socket tests run against `Arangox.ProtocolServer` on an ephemeral
  local port; the rest run against `ScriptClient`, which records every socket it
  opens and closes. Neither needs Docker.

  The one exception is the last describe block, which verifies the leader
  redirect against the real active-failover cluster in `docker-compose.yml` and
  is tagged `:integration`.
  """

  use ExUnit.Case, async: false

  alias Arangox.{Connection, Error, ProtocolServer}
  alias Arangox.ConnectionTest.ScriptClient

  @availability "/_admin/server/availability"
  @mode "/_admin/server/mode"
  @version "/_api/version"

  @ok_body ~s({"error":false,"code":200})
  @version_body ~s({"server":"arango","license":"community","version":"3.12.5"})

  ## Real-socket harness helpers

  # Routes for a server that passes every connect probe.
  defp healthy_routes do
    %{
      @availability => {200, [{"content-type", "application/json"}], @ok_body},
      @version => {200, [{"content-type", "application/json"}], @version_body}
    }
  end

  # A server that completes the TCP handshake and then refuses the availability
  # check. The socket exists before the attempt fails.
  defp unavailable_routes do
    %{@availability => {503, [{"content-type", "application/json"}], @ok_body}}
  end

  # A follower in an active-failover setup: 503 on the availability probe, with
  # the current leader named in `x-arango-endpoint`.
  defp redirect_routes(advertised) do
    %{
      @availability =>
        {503, [{"content-type", "application/json"}, {"x-arango-endpoint", advertised}], @ok_body}
    }
  end

  defp start_server(routes) do
    {port, url, _server} = start_server!(routes)
    {port, url}
  end

  # Same, keeping the server handle so a test can ask what reached it.
  defp start_server!(routes) do
    {:ok, port, server} = ProtocolServer.start(routes: routes)
    on_exit(fn -> ProtocolServer.stop(server) end)
    {port, "http://127.0.0.1:#{port}", server}
  end

  # Requests that reached a server carrying credentials — asserted empty for
  # a refused redirect target.
  defp authorized_requests(server) do
    Enum.filter(ProtocolServer.requests(server), fn request ->
      Enum.any?(request["headers"], fn [name, _value] ->
        String.downcase(name) == "authorization"
      end)
    end)
  end

  # Client-side sockets currently connected to `port_number`. The harness's own
  # accepted sockets are excluded: their peer is the client's ephemeral port,
  # not the listen port.
  defp sockets_to(port_number) do
    Enum.filter(Port.list(), fn port ->
      with ~c"tcp_inet" <- port_name(port),
           {:ok, {_ip, ^port_number}} <- :inet.peername(port) do
        true
      else
        _other -> false
      end
    end)
  end

  defp port_name(port) do
    case :erlang.port_info(port, :name) do
      {:name, name} -> name
      _other -> nil
    end
  end

  defp stop_pool(pool) do
    if Process.alive?(pool), do: GenServer.stop(pool)
    :ok
  catch
    :exit, _reason -> :ok
  end

  ## Scripted-client helpers

  defp connect(script, opts) do
    :ok = ScriptClient.start(script)
    Connection.connect(Keyword.put(opts, :client, ScriptClient))
  end

  defp healthy, do: %{responses: %{@version => {200, @version_body}}}

  describe "socket ownership" do
    test "a pool retrying against an unavailable endpoint does not accumulate sockets" do
      {port, url} = start_server(unavailable_routes())

      # backoff is squeezed so DBConnection runs many connect attempts inside
      # the sleep below. Every attempt opens a socket, gets a 503 from the
      # availability check and gives up on the endpoint. DBConnection retries
      # connect/1 *in the same process*, so a socket left open by a failed
      # attempt is not reclaimed by the process dying — it just accumulates.
      {:ok, pool} =
        Arangox.start_link(
          endpoints: [url],
          client: Arangox.MintClient,
          pool_size: 2,
          backoff_min: 10,
          backoff_max: 20,
          show_sensitive_data_on_connection_error: true
        )

      on_exit(fn -> stop_pool(pool) end)

      Process.sleep(1_000)

      open = sockets_to(port)

      assert length(open) <= 2,
             "pool of 2 accumulated #{length(open)} sockets against an unavailable endpoint"
    end

    test "walking to a healthy endpoint leaves exactly one socket open" do
      {dead_port, dead_url} = start_server(unavailable_routes())
      {good_port, good_url} = start_server(healthy_routes())

      # 127.0.0.1:1 is not listening: the connect fails before a socket exists.
      endpoints = ["http://127.0.0.1:1", dead_url, good_url]

      assert {:ok, %Connection{} = state} =
               Connection.connect(endpoints: endpoints, client: Arangox.MintClient)

      assert state.endpoint == good_url
      assert sockets_to(dead_port) == []
      assert length(sockets_to(good_port)) == 1

      :ok = Connection.disconnect(:normal, state)
      assert sockets_to(good_port) == []
    end

    test "an endpoint that fails the availability check has its socket closed" do
      script = %{"a" => %{responses: %{@availability => {503, "{}"}}}, "b" => healthy()}

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script, endpoints: ["http://a:1", "http://b:2"])

      assert [{"a", _}, {"b", _}] = ScriptClient.opened()
      assert [{"a", _}] = ScriptClient.closed()
    end

    test "a single endpoint that fails the availability check has its socket closed" do
      script = %{"a" => %{responses: %{@availability => {503, "{}"}}}}

      assert {:error, %Error{message: "service unavailable", endpoint: "http://a:1"}} =
               connect(script, endpoints: "http://a:1")

      assert ScriptClient.opened() == ScriptClient.closed()
      assert length(ScriptClient.closed()) == 1
    end
  end

  describe "the failover walk" do
    test "a transport error while checking availability continues the walk" do
      script = %{
        "a" => %{responses: %{@availability => {:error, :closed}}},
        "b" => healthy()
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script, endpoints: ["http://a:1", "http://b:2"])

      assert [{"a", _}] = ScriptClient.closed()
    end

    test "an empty endpoint list returns a structured exhaustion error" do
      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(%{}, endpoints: [])
    end

    test "an unparseable endpoint returns a structured error instead of raising" do
      assert {:error, %Error{} = error} = connect(%{}, endpoints: "nonsense://host:1")

      assert error.endpoint == "nonsense://host:1"
      assert error.message =~ "Invalid protocol in endpoint configuration"

      # Nothing was opened, so there is nothing to leak.
      assert ScriptClient.opened() == []
    end

    test "an unparseable endpoint in a list is walked past" do
      script = %{"b" => healthy()}

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script, endpoints: ["nonsense://host:1", "http://b:2"])
    end

    test "a list of unparseable endpoints exhausts instead of raising" do
      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(%{}, endpoints: ["nonsense://a:1", "http://"])
    end

    test "failover_callback fires once per failed endpoint per connect attempt" do
      pid = self()

      script =
        Map.new(["a", "b", "c"], fn host -> {host, %{connect: {:error, :econnrefused}}} end)

      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(script,
                 endpoints: ["http://a:1", "http://b:2", "http://c:3"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "http://a:1"}}
      assert_receive {:failover, %Error{endpoint: "http://b:2"}}
      assert_receive {:failover, %Error{endpoint: "http://c:3"}}
      refute_receive {:failover, _exception}, 50
    end

    test "failover_callback is not invoked for a single binary endpoint" do
      pid = self()
      script = %{"a" => %{connect: {:error, :econnrefused}}}

      assert {:error, %Error{endpoint: "http://a:1", message: :econnrefused}} =
               connect(script,
                 endpoints: "http://a:1",
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      refute_receive {:failover, _exception}, 50
    end

    # An endpoint that answers and declares itself unusable is the same class of
    # failure as one whose socket never opened. Every official ArangoDB driver
    # classifies it that way, so the callback reports both.
    test "failover_callback fires when an endpoint is reachable but unavailable" do
      pid = self()

      script = %{
        "a" => %{responses: %{@availability => {503, "{}"}}},
        "b" => healthy()
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script,
                 endpoints: ["http://a:1", "http://b:2"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "http://a:1", message: "service unavailable"}}
      refute_receive {:failover, _exception}, 50
    end

    test "failover_callback fires on a transport error during the availability check" do
      pid = self()

      script = %{
        "a" => %{responses: %{@availability => {:error, :closed}}},
        "b" => healthy()
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script,
                 endpoints: ["http://a:1", "http://b:2"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "http://a:1", message: :closed}}
      refute_receive {:failover, _exception}, 50
    end

    test "failover_callback reports unreachable and unhealthy endpoints alike" do
      pid = self()

      script = %{
        "a" => %{connect: {:error, :econnrefused}},
        "b" => %{responses: %{@availability => {503, "{}"}}},
        "c" => healthy()
      }

      assert {:ok, %Connection{endpoint: "http://c:3"}} =
               connect(script,
                 endpoints: ["http://a:1", "http://b:2", "http://c:3"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "http://a:1", message: :econnrefused}}
      assert_receive {:failover, %Error{endpoint: "http://b:2", message: "service unavailable"}}
      refute_receive {:failover, _exception}, 50
    end

    test "failover_callback is not invoked when a single endpoint is unavailable" do
      pid = self()
      script = %{"a" => %{responses: %{@availability => {503, "{}"}}}}

      assert {:error, %Error{endpoint: "http://a:1"}} =
               connect(script,
                 endpoints: "http://a:1",
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      refute_receive {:failover, _exception}, 50
    end

    test "failover_callback fires when a read-only pool rejects a default-mode server" do
      pid = self()

      script = %{
        "a" => %{responses: %{@mode => {200, ~s({"mode":"default"})}}},
        "b" => %{
          responses: %{
            @mode => {200, ~s({"mode":"readonly"})},
            @version => {200, @version_body}
          }
        }
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script,
                 endpoints: ["http://a:1", "http://b:2"],
                 read_only?: true,
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "http://a:1", message: "not a readonly server"}}
      refute_receive {:failover, _exception}, 50
    end
  end

  # The probe stages run user-pluggable code — `:json_library` decodes their
  # responses — inside `connect/1` while holding the only reference to
  # the open socket. A crash must become an orderly error that has
  # closed it, not an escape that costs the process its backoff.
  describe "a probe stage that crashes" do
    test "fails the connect in order and closes the socket" do
      script = %{"a" => healthy()}

      assert {:error, %Error{}} =
               connect(script,
                 endpoints: "http://a:1",
                 json_library: Arangox.ConnectionTest.RaisingJson
               )

      assert ScriptClient.opened() == ScriptClient.closed(),
             "a crashing probe stage leaked its socket"
    end
  end

  describe "leader redirects" do
    # The advertised leader is genuinely reachable at the address it names
    # — "localhost" resolves to the loopback the harness listens on — so what
    # stops the redirect is the policy, not the network.
    test "a redirect to a host absent from :endpoints is refused and sees no credentials" do
      {leader_port, _leader_url, leader} = start_server!(healthy_routes())
      advertised = "tcp://localhost:#{leader_port}"
      {_port, follower_url, follower} = start_server!(redirect_routes(advertised))
      pid = self()

      assert {:error, %Error{} = error} =
               Connection.connect(
                 endpoints: [follower_url],
                 client: Arangox.MintClient,
                 auth: {:basic, "root", "hunter2"},
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert error.message == "all endpoints are unavailable"

      assert_receive {:failover, %Error{endpoint: ^follower_url, message: message}}
      assert message =~ "refused redirect to #{inspect(advertised)}"
      assert message =~ ":endpoint_mapper"

      # The control: the pool really does carry credentials, and really did send
      # them to the endpoint it was configured for.
      assert authorized_requests(follower) != []

      # And nothing at all reached the advertised host.
      assert ProtocolServer.requests(leader) == []
      assert authorized_requests(leader) == []
    end

    # The reason "its host already appears" is a summary, not the rule. Host
    # matching alone would authorize this redirect.
    test "a redirect naming a different port on a configured host is refused" do
      {_other_port, other_url, other} = start_server!(healthy_routes())
      advertised = String.replace(other_url, "http://", "tcp://")
      {_port, follower_url, _follower} = start_server!(redirect_routes(advertised))
      pid = self()

      assert {:error, %Error{}} =
               Connection.connect(
                 endpoints: [follower_url],
                 client: Arangox.MintClient,
                 auth: {:basic, "root", "hunter2"},
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{message: message}}
      assert message =~ "refused redirect"

      assert ProtocolServer.requests(other) == []
      assert authorized_requests(other) == []
    end

    # The normalization clause. Without it the server's own scheme vocabulary
    # never matches a user's configuration and the feature never fires.
    test "an advertised tcp:// endpoint is admitted by a configured http:// endpoint" do
      {leader_port, leader_url, leader} = start_server!(healthy_routes())
      advertised = "tcp://127.0.0.1:#{leader_port}"
      {_port, follower_url, _follower} = start_server!(redirect_routes(advertised))

      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [follower_url, leader_url],
                 client: Arangox.MintClient
               )

      # Only the redirect can produce the advertised `tcp://` spelling; the
      # ordinary walk would have arrived at the configured `http://` one.
      assert state.endpoint == advertised
      assert ProtocolServer.requests(leader) != []

      :ok = Connection.disconnect(:normal, state)
    end

    # The container case. The mapped target is deliberately absent from
    # `:endpoints`: an admitted mapper output is not re-checked for membership,
    # which is exactly why the mapper is a trust boundary.
    test "an :endpoint_mapper rewriting an internal hostname to loopback is followed" do
      {_leader_port, leader_url, leader} = start_server!(healthy_routes())
      advertised = "tcp://db.internal:8529"
      {_port, follower_url, _follower} = start_server!(redirect_routes(advertised))

      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [follower_url],
                 client: Arangox.MintClient,
                 endpoint_mapper: %{advertised => leader_url}
               )

      assert state.endpoint == leader_url
      assert Enum.any?(ProtocolServer.requests(leader), &(&1["path"] == @availability))

      :ok = Connection.disconnect(:normal, state)
    end

    test "the socket held before a redirect is closed" do
      {leader_port, leader_url, _leader} = start_server!(healthy_routes())
      advertised = "tcp://db.internal:8529"
      {follower_port, follower_url, _follower} = start_server!(redirect_routes(advertised))

      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [follower_url],
                 client: Arangox.MintClient,
                 endpoint_mapper: %{advertised => leader_url}
               )

      assert sockets_to(follower_port) == []
      assert length(sockets_to(leader_port)) == 1

      :ok = Connection.disconnect(:normal, state)
      assert sockets_to(leader_port) == []
    end

    # Settled from the two official drivers that implement this: arangojs
    # re-queues the task on `503 && leaderEndpoint` before reaching any error
    # path, and the Java driver's `failIfNotMatch` only marks a failure when the
    # redirect target is not the host it was already on. Following a leader is
    # normal operation.
    test "an admitted redirect does not fire failover_callback" do
      {_leader_port, leader_url, _leader} = start_server!(healthy_routes())
      advertised = "tcp://db.internal:8529"
      {_port, follower_url, _follower} = start_server!(redirect_routes(advertised))
      pid = self()

      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: [follower_url],
                 client: Arangox.MintClient,
                 endpoint_mapper: %{advertised => leader_url},
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      refute_receive {:failover, _exception}, 50

      :ok = Connection.disconnect(:normal, state)
    end

    test "an encrypted origin is not redirected to a cleartext endpoint" do
      pid = self()

      script = %{
        "a" => %{
          responses: %{
            @availability => {503, [{"x-arango-endpoint", "tcp://b:2"}], "{}"}
          }
        },
        "b" => %{responses: %{@availability => {503, "{}"}}}
      }

      # `http://b:2` is configured, so the target passes the origin check and is
      # refused by the downgrade rule alone.
      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(script,
                 endpoints: ["https://a:1", "http://b:2"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{endpoint: "https://a:1", message: message}}
      assert message =~ "refused redirect"
      assert message =~ "cleartext"
    end

    # The downgrade rule must not depend on the *stored* endpoint parsing:
    # storage holds the redacted form, and redaction of a userinfo endpoint
    # keeps only the scheme.
    test "an encrypted origin configured with userinfo still refuses a cleartext redirect" do
      pid = self()

      script = %{
        "a" => %{
          responses: %{
            @availability => {503, [{"x-arango-endpoint", "tcp://b:2"}], "{}"}
          }
        },
        "b" => %{responses: %{@availability => {503, "{}"}}}
      }

      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(script,
                 endpoints: ["https://root:hunter2@a:1", "http://b:2"],
                 failover_callback: fn exception -> send(pid, {:failover, exception}) end
               )

      assert_receive {:failover, %Error{message: message}}
      assert message =~ "cleartext"
      refute message =~ "hunter2"
    end

    test "an advertised value that is not a valid endpoint is refused, not raised" do
      script = %{
        "a" => %{
          responses: %{@availability => {503, [{"x-arango-endpoint", "nonsense://leader"}], "{}"}}
        }
      }

      assert {:error, %Error{endpoint: "http://a:1", message: message}} =
               connect(script, endpoints: "http://a:1")

      assert message =~ ~s(refused redirect to "nonsense://leader")
      assert message =~ "Invalid protocol"
    end

    test "a redirect chain that cycles terminates at the bound" do
      script = %{
        "a" => %{responses: %{@availability => {503, [{"x-arango-endpoint", "tcp://b:2"}], "{}"}}},
        "b" => %{responses: %{@availability => {503, [{"x-arango-endpoint", "tcp://a:1"}], "{}"}}}
      }

      assert {:error, %Error{message: "all endpoints are unavailable"}} =
               connect(script, endpoints: ["http://a:1", "http://b:2"])

      # The budget is 3 redirects per connect attempt, shared by the whole walk:
      # a -> b -> a -> b spends it, then the two endpoints still on the list are
      # each tried once more and refused at the bound. Five sockets, all closed.
      assert length(ScriptClient.opened()) == 5
      assert ScriptClient.opened() == ScriptClient.closed()
    end

    test "a map :endpoint_mapper with no entry for the advertised endpoint refuses" do
      script = %{
        "a" => %{
          responses: %{
            @availability => {503, [{"x-arango-endpoint", "tcp://leader:9999"}], "{}"}
          }
        }
      }

      assert {:error, %Error{message: message}} =
               connect(script,
                 endpoints: "http://a:1",
                 endpoint_mapper: %{"tcp://somewhere-else:8529" => "http://localhost:8529"}
               )

      assert message =~ ~s(refused redirect to "tcp://leader:9999")
      assert message =~ ":endpoint_mapper"
      refute Enum.any?(ScriptClient.opened(), fn {host, _id} -> host == "leader" end)
    end

    test "a map :endpoint_mapper key is matched on its normalized origin" do
      script = %{
        "a" => %{responses: %{@availability => {503, [{"x-arango-endpoint", "tcp://b:2"}], "{}"}}},
        "b" => healthy()
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script,
                 endpoints: "http://a:1",
                 endpoint_mapper: %{"http://b:2" => "http://b:2"}
               )
    end

    test "a function :endpoint_mapper that raises refuses instead of crashing connect" do
      script = %{
        "a" => %{responses: %{@availability => {503, [{"x-arango-endpoint", "tcp://b:2"}], "{}"}}}
      }

      assert {:error, %Error{message: message}} =
               connect(script,
                 endpoints: "http://a:1",
                 endpoint_mapper: fn _advertised -> raise "mapper is broken" end
               )

      assert message =~ "refused redirect"
      assert message =~ "mapper is broken"
    end

    # What an election in progress looks like. Reconnecting would fetch the same
    # 503, and spending the budget here would starve a real redirect later in
    # the walk.
    test "a server that advertises itself is unavailable, not a redirect" do
      script = %{
        "a" => %{responses: %{@availability => {503, [{"x-arango-endpoint", "tcp://a:1"}], "{}"}}}
      }

      assert {:error, %Error{message: "service unavailable"}} =
               connect(script, endpoints: "http://a:1")

      assert length(ScriptClient.opened()) == 1
    end

    test "a 503 without the header is still just an unavailable endpoint" do
      script = %{"a" => %{responses: %{@availability => {503, "{}"}}}}

      assert {:error, %Error{message: "service unavailable"}} =
               connect(script, endpoints: "http://a:1")
    end
  end

  describe ":endpoint_mapper validation" do
    test "the accepted shapes are a map, a one-argument function and an MFA tuple" do
      assert %{} = Arangox.child_spec(endpoint_mapper: %{"tcp://a:1" => "http://a:1"})
      assert %{} = Arangox.child_spec(endpoint_mapper: fn advertised -> advertised end)
      assert %{} = Arangox.child_spec(endpoint_mapper: {Map, :get, [%{}]})
    end

    test "anything else is rejected" do
      for invalid <- ["http://a:1", :map, nil, 1, fn -> "http://a:1" end, {Map, :get}] do
        assert_raise ArgumentError, ~r/:endpoint_mapper/, fn ->
          Arangox.start_link(endpoint_mapper: invalid)
        end
      end
    end

    test "a map with non-binary or unparseable entries is rejected" do
      for invalid <- [
            %{"tcp://a:1" => :nope},
            %{nope: "http://a:1"},
            %{"tcp://a:1" => "nonsense://a:1"}
          ] do
        assert_raise ArgumentError, ~r/:endpoint_mapper/, fn ->
          Arangox.start_link(endpoint_mapper: invalid)
        end
      end
    end

    test "an MFA tuple naming a function that does not exist is rejected" do
      assert_raise ArgumentError, ~r/:endpoint_mapper/, fn ->
        Arangox.start_link(endpoint_mapper: {Map, :no_such_function, [1, 2]})
      end
    end
  end

  describe "read-only pools" do
    test "connect against a server reporting readonly mode" do
      script = %{
        "a" => %{
          responses: %{
            @mode => {200, ~s({"mode":"readonly"})},
            @version => {200, @version_body}
          }
        }
      }

      assert {:ok, %Connection{endpoint: "http://a:1", read_only?: true} = state} =
               connect(script, endpoints: ["http://a:1"], read_only?: true)

      assert {"x-arango-allow-dirty-read", "true"} in state.headers
      assert {"a", @mode} in ScriptClient.requests()
    end

    test "a server reporting default mode is walked past under failover" do
      script = %{
        "a" => %{responses: %{@mode => {200, ~s({"mode":"default"})}}},
        "b" => %{
          responses: %{
            @mode => {200, ~s({"mode":"readonly"})},
            @version => {200, @version_body}
          }
        }
      }

      assert {:ok, %Connection{endpoint: "http://b:2"}} =
               connect(script, endpoints: ["http://a:1", "http://b:2"], read_only?: true)

      assert [{"a", _}] = ScriptClient.closed()
    end

    test "a server reporting default mode errors on a single endpoint" do
      script = %{"a" => %{responses: %{@mode => {200, ~s({"mode":"default"})}}}}

      assert {:error, %Error{message: "not a readonly server", endpoint: "http://a:1"}} =
               connect(script, endpoints: "http://a:1", read_only?: true)

      assert length(ScriptClient.closed()) == 1
    end
  end

  describe "server version discovery" do
    test "the version is read once at connect and cached in connection state" do
      assert {:ok, %Connection{} = state} =
               connect(%{"a" => healthy()}, endpoints: ["http://a:1"])

      assert state.server_version == Version.parse!("3.12.5")

      assert Enum.count(ScriptClient.requests(), fn {_host, path} -> path == @version end) == 1
    end

    test "a version without a patch component still parses" do
      script = %{"a" => %{responses: %{@version => {200, ~s({"version":"3.12"})}}}}

      assert {:ok, %Connection{server_version: %Version{major: 3, minor: 12, patch: 0}}} =
               connect(script, endpoints: ["http://a:1"])
    end

    test "an unparseable version stays unknown rather than being guessed" do
      script = %{"a" => %{responses: %{@version => {200, ~s({"version":"banana"})}}}}

      assert {:ok, %Connection{server_version: nil}} = connect(script, endpoints: ["http://a:1"])
    end

    test "a server that does not report a version at all stays unknown" do
      script = %{"a" => %{responses: %{@version => {404, ~s({"error":true})}}}}

      assert {:ok, %Connection{server_version: nil}} = connect(script, endpoints: ["http://a:1"])
    end

    test "a non-JSON version body stays unknown instead of raising" do
      script = %{"a" => %{responses: %{@version => {200, "<html>not json</html>"}}}}

      assert {:ok, %Connection{server_version: nil}} = connect(script, endpoints: ["http://a:1"])
    end

    test "a non-JSON mode body does not raise on a read-only pool" do
      script = %{"a" => %{responses: %{@mode => {200, "<html>not json</html>"}}}}

      assert {:error, %Error{message: "not a readonly server"}} =
               connect(script, endpoints: "http://a:1", read_only?: true)
    end

    test "the version is discovered over a real socket" do
      {_port, url} = start_server(healthy_routes())

      assert {:ok, %Connection{} = state} =
               Connection.connect(endpoints: [url], client: Arangox.MintClient)

      assert state.server_version == Version.parse!("3.12.5")

      :ok = Connection.disconnect(:normal, state)
    end
  end

  describe "leader redirects against a live active-failover cluster" do
    # docker-compose.yml's `resilient_single` publishes the three members'
    # container ports 8529/8539/8549 on host ports 8003/8004/8005. A follower
    # advertises the leader by its *container* address ("http://localhost:8539"
    # when the leader is the member on host port 8004), which no host-side
    # `:endpoints` list can contain — so the default policy refuses that
    # redirect and the mapper is what makes it followable. See the
    # `:endpoint_mapper` section of `Arangox.start_link/1`.
    @container_to_host %{
      "http://localhost:8529" => TestHelper.failover_1(),
      "http://localhost:8539" => TestHelper.failover_2(),
      "http://localhost:8549" => TestHelper.failover_3()
    }

    @members [TestHelper.failover_1(), TestHelper.failover_2(), TestHelper.failover_3()]

    # The leader is whichever member completes a connect; the others answer 503
    # and are refused, since the address they advertise is not reachable from
    # the host. Discovered rather than hard-coded: leadership moves.
    defp failover_follower do
      Enum.find(@members, fn endpoint ->
        case Connection.connect(endpoints: endpoint, client: Arangox.MintClient) do
          {:ok, state} ->
            :ok = Connection.disconnect(:normal, state)
            false

          {:error, _exception} ->
            true
        end
      end)
    end

    @tag integration: :arango_3_11
    test "a real follower's redirect is refused without a mapper" do
      follower = failover_follower()
      assert follower, "no member answered 503 — is the resilient_single container up?"

      assert {:error, %Error{} = error} =
               Connection.connect(
                 endpoints: follower,
                 client: Arangox.MintClient,
                 auth: {:basic, "root", ""}
               )

      assert error.endpoint == follower
      assert error.message =~ "refused redirect to"
      assert error.message =~ ":endpoint_mapper"

      # Not a connection failure against the advertised address — a refusal
      # before any connection to it was attempted.
      refute error.message =~ "econnrefused"

      assert [advertised] =
               Regex.run(~r/refused redirect to "([^"]+)"/, error.message,
                 capture: :all_but_first
               )

      assert {:ok, %Arangox.Endpoint{addr: {:tcp, _host, port}}} =
               Arangox.Endpoint.parse(advertised)

      # Against a live server: no socket to the advertised address exists,
      # so nothing carrying the authorization header reached it.
      assert sockets_to(port) == []
    end

    @tag integration: :arango_3_11
    test "a pool pointed at a follower reaches the leader through :endpoint_mapper" do
      follower = failover_follower()
      assert follower, "no member answered 503 — is the resilient_single container up?"

      assert {:ok, %Connection{} = state} =
               Connection.connect(
                 endpoints: follower,
                 client: Arangox.MintClient,
                 endpoint_mapper: @container_to_host
               )

      # The redirect landed on a different member than the one configured, at
      # the host address the mapper named.
      assert state.endpoint in (@members -- [follower])
      :ok = Connection.disconnect(:normal, state)

      {:ok, pool} =
        Arangox.start_link(
          endpoints: [follower],
          client: Arangox.MintClient,
          endpoint_mapper: @container_to_host,
          pool_size: 1,
          show_sensitive_data_on_connection_error: true
        )

      on_exit(fn -> stop_pool(pool) end)

      assert %Arangox.Response{status: 200} =
               Arangox.get!(pool, "/_admin/server/availability")
    end
  end
end
