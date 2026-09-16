defmodule Arangox.ConfigTest.ProbeClient do
  @moduledoc """
  Reports the per-pool configuration that reached connection state.

  Answers `200` with an empty body to everything, and sends the resolved
  `:json_library` and `:vst_maxsize` from the `Arangox.Connection` struct to
  the process registered as `Arangox.ConfigTest.Probe` on every request. That
  makes "which value did *this* pool end up with" observable without a server.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Request, Response}

  @impl true
  def connect(_endpoint, _opts), do: {:ok, make_ref()}

  @impl true
  def alive?(%Connection{}), do: true

  @impl true
  def request(%Request{path: path}, _opts, %Connection{} = state) do
    notify({:probe, path, state.json_library, state.vst_maxsize})

    {:ok, %Response{status: 200, headers: [], body: nil}, state}
  end

  @impl true
  def close(%Connection{}), do: :ok

  defp notify(message) do
    case Process.whereis(Arangox.ConfigTest.Probe) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end

defmodule Arangox.ConfigTest.FakeJson do
  @moduledoc """
  A stand-in JSON module, so a pool can be configured with something other than
  `Jason` without pulling in a second JSON dependency.
  """

  def encode!(term), do: Jason.encode!(term)
  def decode(binary), do: Jason.decode(binary)
  def decode!(binary), do: Jason.decode!(binary)
end

defmodule Arangox.ConfigTest.RefusingClient do
  @moduledoc """
  Never connects, and counts how often `connect/2` was entered.

  `DBConnection` re-enters `Arangox.Connection.connect/1` *in the same process*
  on every backoff cycle, so this client makes the reconnect loop countable.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Request, Response}

  @impl true
  def connect(_endpoint, _opts) do
    case Process.whereis(Arangox.ConfigTest.Probe) do
      nil -> :ok
      pid -> send(pid, :connect_attempt)
    end

    {:error, :econnrefused}
  end

  @impl true
  def alive?(%Connection{}), do: false

  @impl true
  def request(%Request{}, _opts, %Connection{} = state),
    do: {:ok, %Response{status: 200, headers: [], body: nil}, state}

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.ConfigTest.FakeTransport do
  @moduledoc """
  A `:gen_tcp`-shaped transport that records what a client wrote.

  `Arangox.VelocyClient` treats a socket as `{module, port}` and only calls
  `send/2`, `recv/3` and `close/1` on it, so a module plus a pid stands in for a
  real socket. `recv/3` reports a closed socket, which makes
  `VelocyClient.request/3` return right after it has written the whole stream.

  The receive is the three-argument form: the two-argument
  `:gen_tcp.recv/2` has no timeout argument, which is how VelocyStream came to
  wait on a socket forever.
  """

  def send(pid, data) do
    Kernel.send(pid, {:sent, IO.iodata_to_binary(data)})
    :ok
  end

  def recv(_pid, _length, timeout) when is_integer(timeout) and timeout > 0,
    do: {:error, :closed}

  def close(_pid), do: :ok
end

defmodule Arangox.ConfigTest do
  @moduledoc """
  Per-pool `:json_library` and `:vst_maxsize`, and the deprecated
  application-config fallback and readers.

  Unit tier: no Docker and no network. `async: false` because the tests mutate
  application env and register a named process.
  """

  use ExUnit.Case, async: false

  import TestHelper, only: [stop_pool: 1]

  import ExUnit.CaptureLog

  alias Arangox.Connection
  alias Arangox.ConfigTest.{FakeTransport, ProbeClient, RefusingClient}
  alias Arangox.{Request, Response}

  @deprecation "deprecated"

  setup do
    Application.delete_env(:arangox, :json_library)
    Application.delete_env(:arangox, :vst_maxsize)
    Process.register(self(), Arangox.ConfigTest.Probe)

    on_exit(fn ->
      Application.delete_env(:arangox, :json_library)
      Application.delete_env(:arangox, :vst_maxsize)
    end)

    :ok
  end

  defp start_pool(opts) do
    {:ok, pool} = Arangox.start_link(Keyword.merge([client: ProbeClient, pool_size: 1], opts))
    on_exit(fn -> stop_pool(pool) end)
    pool
  end

  defp count(log, needle) do
    log |> String.split(needle) |> length() |> Kernel.-(1)
  end

  defp drain(message, acc \\ 0) do
    receive do
      ^message -> drain(message, acc + 1)
    after
      0 -> acc
    end
  end

  # Both deprecated readers are called through `apply/3`: they carry a
  # `@deprecated` attribute, and a direct call would make the compiler warn on
  # every run of the suite. What is under test is the runtime warning.
  defp deprecated_json_library, do: apply(Arangox, :json_library, [])
  defp deprecated_vst_maxsize, do: apply(Arangox.VelocyClient, :vst_maxsize, [])

  describe "per-pool options:" do
    test "two pools with different :vst_maxsize each use their own" do
      pool_a = start_pool(vst_maxsize: 111)
      pool_b = start_pool(vst_maxsize: 222)

      assert %Response{status: 200} = Arangox.get!(pool_a, "/pool-a")
      assert %Response{status: 200} = Arangox.get!(pool_b, "/pool-b")

      assert_receive {:probe, "/pool-a", _json, 111}
      assert_receive {:probe, "/pool-b", _json, 222}
    end

    test "two pools with different :json_library each use their own" do
      pool_a = start_pool(json_library: Jason)
      pool_b = start_pool(json_library: Arangox.ConfigTest.FakeJson)

      assert %Response{status: 200} = Arangox.get!(pool_a, "/pool-a")
      assert %Response{status: 200} = Arangox.get!(pool_b, "/pool-b")

      assert_receive {:probe, "/pool-a", Jason, _maxsize}
      assert_receive {:probe, "/pool-b", Arangox.ConfigTest.FakeJson, _maxsize}
    end

    test ":vst_maxsize is resolved at runtime and reaches VelocyStream framing" do
      request = %Request{method: :post, path: "/_admin/echo", body: String.duplicate("a", 400)}

      small = sent_chunks(request, 64)
      large = sent_chunks(request, 30_720)

      assert length(large) == 1
      assert length(small) > 1

      assert Enum.all?(small, &(byte_size(&1) <= 64)),
             "a chunk exceeded the pool's :vst_maxsize: #{inspect(Enum.map(small, &byte_size/1))}"
    end
  end

  # Drives VelocyClient.request/3 over FakeTransport and returns the binaries it
  # wrote, which are exactly the VelocyStream chunks.
  defp sent_chunks(request, vst_maxsize) do
    state = struct(Connection, socket: {FakeTransport, self()}, vst_maxsize: vst_maxsize)

    # The socket-gone signal is a reason class on the one error struct now
    # , not the `:noproc` sentinel.
    assert {:error, %Arangox.Error{reason: :closed}, _state} =
             Arangox.VelocyClient.request(request, [], state)

    collect_sent([])
  end

  defp collect_sent(acc) do
    receive do
      {:sent, data} -> collect_sent([data | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "deprecated application config:" do
    test "application config alone still works, and warns once per pool" do
      Application.put_env(:arangox, :vst_maxsize, 333)

      log =
        capture_log(fn ->
          pool = start_pool([])

          assert %Response{status: 200} = Arangox.get!(pool, "/app-config")
        end)

      assert_receive {:probe, "/app-config", _json, 333}
      assert count(log, ":vst_maxsize") == 1
      assert log =~ @deprecation
    end

    test "a pool option overrides application config, and does not warn" do
      Application.put_env(:arangox, :vst_maxsize, 333)
      Application.put_env(:arangox, :json_library, Poison)

      log =
        capture_log(fn ->
          pool = start_pool(vst_maxsize: 444, json_library: Jason)

          assert %Response{status: 200} = Arangox.get!(pool, "/override")
        end)

      assert_receive {:probe, "/override", Jason, 444}
      refute log =~ @deprecation
    end

    test "the warning is emitted once per pool, not once per pool process" do
      Application.put_env(:arangox, :vst_maxsize, 555)

      log =
        capture_log(fn ->
          pool = start_pool(pool_size: 5)

          assert %Response{status: 200} = Arangox.get!(pool, "/per-pool")
        end)

      assert count(log, ":vst_maxsize") == 1
    end

    test "the warning does not repeat across reconnects" do
      Application.put_env(:arangox, :vst_maxsize, 555)

      log =
        capture_log(fn ->
          {:ok, pool} =
            Arangox.start_link(
              client: RefusingClient,
              pool_size: 2,
              backoff_min: 10,
              backoff_max: 20
            )

          on_exit(fn -> stop_pool(pool) end)

          Process.sleep(500)
        end)

      attempts = drain(:connect_attempt)

      assert attempts > 4,
             "the pool did not actually reconnect (#{attempts} attempts); the test proves nothing"

      assert count(log, ":vst_maxsize") == 1,
             "the deprecation warning repeated across #{attempts} reconnects"
    end
  end

  describe "socket options no endpoint can read:" do
    @unreadable "no endpoint in this pool can read it"

    test ":ssl_opts is flagged when every endpoint is cleartext" do
      log = capture_log(fn -> start_pool(endpoints: "http://localhost:8529", ssl_opts: []) end)

      assert log =~ @unreadable
      assert log =~ ":ssl_opts"
    end

    test ":tcp_opts is flagged when every endpoint is encrypted" do
      log = capture_log(fn -> start_pool(endpoints: "https://localhost:8529", tcp_opts: []) end)

      assert log =~ @unreadable
      assert log =~ ":tcp_opts"
    end

    test "an endpoint list that mixes schemes reads both, so neither is flagged" do
      log =
        capture_log(fn ->
          start_pool(
            endpoints: ["http://localhost:8529", "https://localhost:8530"],
            tcp_opts: [],
            ssl_opts: []
          )
        end)

      refute log =~ @unreadable
    end

    test "a redirect admitted by :endpoint_mapper can reach either scheme, so neither is flagged" do
      log =
        capture_log(fn ->
          start_pool(
            endpoints: "http://localhost:8529",
            ssl_opts: [],
            endpoint_mapper: fn endpoint -> endpoint end
          )
        end)

      refute log =~ @unreadable
    end

    test "passing neither option is silent" do
      log = capture_log(fn -> start_pool(endpoints: "http://localhost:8529") end)

      refute log =~ @unreadable
    end
  end

  describe "deprecated readers:" do
    test "Arangox.json_library/0 returns the fallback and warns" do
      assert capture_log(fn -> assert deprecated_json_library() == Jason end) =~ @deprecation

      Application.put_env(:arangox, :json_library, Poison)

      assert capture_log(fn -> assert deprecated_json_library() == Poison end) =~ @deprecation
    end

    test "Arangox.VelocyClient.vst_maxsize/0 returns the fallback and warns" do
      assert capture_log(fn -> assert deprecated_vst_maxsize() == 30_720 end) =~ @deprecation

      Application.put_env(:arangox, :vst_maxsize, 12_345)

      assert capture_log(fn -> assert deprecated_vst_maxsize() == 12_345 end) =~ @deprecation
    end

    test "the deprecated readers are not on any request path" do
      pool = start_pool([])

      refute capture_log(fn ->
               assert %Response{status: 200} = Arangox.get!(pool, "/no-warning")
             end) =~ @deprecation
    end
  end

  ## Credentials over cleartext

  # Cleartext is supported on purpose — a private network with no TLS
  # termination is a normal way to run this. Sending credentials over it to
  # another machine without saying so is not.
  describe "cleartext credentials:" do
    @credentials {:basic, "root", "hunter2"}

    test "a pool refuses to start and names the option" do
      error =
        assert_raise ArgumentError, fn ->
          Arangox.start_link(endpoints: "http://db.internal:8529", auth: @credentials)
        end

      assert error.message =~ "allow_cleartext_auth"
      assert error.message =~ "db.internal"
    end

    test "the opt-in starts it" do
      assert is_pid(
               start_pool(
                 endpoints: "http://db.internal:8529",
                 auth: @credentials,
                 allow_cleartext_auth: true
               )
             )
    end

    # The documented default configuration, which must be unaffected.
    test "a loopback endpoint needs no opt-in" do
      for endpoint <- ["http://localhost:8529", "http://127.0.0.1:8529", "http://[::1]:8529"] do
        assert is_pid(start_pool(endpoints: endpoint, auth: @credentials)),
               "#{endpoint} is this machine and should need no opt-in"
      end
    end

    # A hostname is not an address. `127.0.0.1.nip.io` and friends resolve
    # wherever their DNS says — often off this machine — so treating any name
    # beginning "127." as loopback exempts exactly the endpoints this check
    # exists to refuse.
    test "a hostname that merely starts with 127. is not loopback" do
      for endpoint <- [
            "http://127.0.0.1.nip.io:8529",
            "http://127.0.0.1.attacker.example:8529",
            "http://127.database.internal:8529"
          ] do
        assert_raise ArgumentError, ~r/allow_cleartext_auth/, fn ->
          Arangox.start_link(endpoints: endpoint, auth: @credentials)
        end
      end
    end

    test "the rest of 127.0.0.0/8 is loopback" do
      for endpoint <- ["http://127.0.0.2:8529", "http://127.1.2.3:8529"] do
        assert is_pid(start_pool(endpoints: endpoint, auth: @credentials)),
               "#{endpoint} is in 127.0.0.0/8 and should need no opt-in"
      end
    end

    # A pool can carry a credential in `:headers` as legitimately as in
    # `:auth` — the pool's headers are sent with every request — so the
    # refusal has to see it there too.
    test "an authorization header counts as a credential" do
      for name <- ["authorization", "Authorization"] do
        assert_raise ArgumentError, ~r/allow_cleartext_auth/, fn ->
          Arangox.start_link(
            endpoints: "http://db.internal:8529",
            headers: [{name, "Basic cm9vdDpodW50ZXIy"}]
          )
        end
      end
    end

    # `with false <- ...` continued only on an exact `false`, so any other
    # value — a typo, a nil from a config lookup — waived the refusal.
    test "only an exact true waives the refusal" do
      for waiver <- [nil, 0, "true", :yes] do
        assert_raise ArgumentError, ~r/allow_cleartext_auth/, fn ->
          Arangox.start_link(
            endpoints: "http://db.internal:8529",
            auth: @credentials,
            allow_cleartext_auth: waiver
          )
        end
      end
    end

    test "TLS needs no opt-in" do
      assert is_pid(start_pool(endpoints: "https://db.internal:8529", auth: @credentials))
    end

    test "a unix socket needs no opt-in — it never leaves the machine" do
      assert is_pid(start_pool(endpoints: "http://unix:/tmp/arangodb.sock", auth: @credentials))
    end

    test "no credentials, no question" do
      assert is_pid(start_pool(endpoints: "http://db.internal:8529"))
    end

    # One exposed endpoint in a list is enough; failover does not make it safe.
    test "any one exposed endpoint in a list is refused" do
      assert_raise ArgumentError, ~r/allow_cleartext_auth/, fn ->
        Arangox.start_link(
          endpoints: ["http://localhost:8529", "http://db.internal:8529"],
          auth: @credentials
        )
      end
    end

    # The message is the sort of thing people paste into issues.
    test "the message carries no credentials from the endpoint" do
      error =
        assert_raise ArgumentError, fn ->
          Arangox.start_link(
            endpoints: "http://root:hunter2@db.internal:8529",
            auth: @credentials
          )
        end

      refute error.message =~ "hunter2"
      assert error.message =~ "[redacted]"
    end
  end

  # These run inside `connect/1`, which is a DBConnection callback: a raise
  # there is not an error, it is a worker restart loop that outruns backoff and
  # exhausts the supervisor's restart intensity.
  describe "nothing raises out of connect/1:" do
    test "a :failover_callback that raises does not take the pool down" do
      {:ok, pool} =
        Arangox.start_link(
          endpoints: ["http://localhost:65001"],
          client: Arangox.MintClient,
          failover_callback: fn _error -> raise "callback boom" end,
          pool_size: 1,
          backoff_min: 20,
          backoff_max: 30
        )

      on_exit(fn -> stop_pool(pool) end)

      Process.sleep(400)

      assert Process.alive?(pool),
             "a raising failover callback killed the pool instead of failing the connect"
    end

    # `Arangox.Connection.connect/1` is reachable without
    # `Arangox.start_link/1`'s validation, so a header list of the wrong shape
    # must come back as a described error, not a raise.
    test "a :headers list of the wrong shape fails the connect in order" do
      assert {:error, %Arangox.Error{} = error} =
               Arangox.Connection.connect(
                 client: ProbeClient,
                 headers: [{"x-bad", %Arangox.TestSupport.Unrenderable{}}]
               )

      # The refused value could be the credential itself, so the message names
      # the shape rule and nothing else.
      refute Exception.message(error) =~ "not_a_string"
      assert Exception.message(error) =~ "list of {name, value} tuples"
    end

    # The map case must reach the same refusal: `struct/2` copies whatever the
    # caller configured into state, so the connect-time check is the only
    # thing standing between a map and a crash mid-request.
    test "map :headers around the validation still fail the connect in order" do
      assert {:error, %Arangox.Error{} = error} =
               Arangox.Connection.connect(
                 client: ProbeClient,
                 headers: %{"x-custom" => "1"}
               )

      assert Exception.message(error) =~ "list of {name, value} tuples"
    end

    test "a :headers list of the wrong shape closes its socket and fails the connect" do
      before = length(Port.list())

      {:ok, pool} =
        DBConnection.start_link(Arangox.Connection,
          client: ProbeClient,
          headers: [{"x-bad", %{not: "a string"}}],
          pool_size: 1,
          backoff_min: 20,
          backoff_max: 30
        )

      on_exit(fn -> stop_pool(pool) end)

      Process.sleep(300)

      assert Process.alive?(pool)

      assert length(Port.list()) - before < 5,
             "connect attempts accumulated sockets instead of closing them"
    end
  end

  describe "validation:" do
    test ":headers must be a list since 0.8, so a map is refused with directions" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(headers: %{"x-custom" => "1"})
        end)

      assert Exception.message(error) =~ "list of {name, value} tuples"
    end

    test "a :headers entry that is not a pair of binaries is refused" do
      for invalid <- [[{"x-custom", %{}}], [{:atom, "1"}], ["x-custom: 1"], "x-custom: 1"] do
        assert_raise ArgumentError, ~r/list of \{name, value\} tuples/, fn ->
          Arangox.start_link(headers: invalid)
        end
      end
    end

    test "an invalid :json_library is rejected" do
      for invalid <- ["Jason", nil, false, 1, {:json, Jason}] do
        assert_raise ArgumentError, ~r/:json_library/, fn ->
          Arangox.start_link(json_library: invalid)
        end
      end
    end

    test "a :json_library that is not a loadable module is rejected" do
      assert_raise ArgumentError, ~r/:json_library/, fn ->
        Arangox.start_link(json_library: Arangox.ConfigTest.NoSuchModule)
      end
    end

    test "an invalid :content_type is rejected" do
      for invalid <- [:vpack, "velocypack", nil, true, 1] do
        assert_raise ArgumentError, ~r/:content_type/, fn ->
          Arangox.start_link(content_type: invalid)
        end
      end
    end

    test "both documented :content_type values are accepted" do
      for valid <- [:json, :velocypack] do
        assert is_pid(start_pool(content_type: valid)),
               "expected #{inspect(valid)} to be accepted"
      end
    end

    test "an invalid :max_body_size is rejected" do
      for invalid <- [:big, "65536", 65_536.0, nil, 0, -1] do
        assert_raise ArgumentError, ~r/:max_body_size/, fn ->
          Arangox.start_link(max_body_size: invalid)
        end
      end
    end

    test "a positive :max_body_size is accepted" do
      assert is_pid(start_pool(max_body_size: 1024))
    end

    test "an invalid :vst_maxsize is rejected" do
      for invalid <- [:big, "30720", 30_720.0, nil, 0, -1] do
        assert_raise ArgumentError, ~r/:vst_maxsize/, fn ->
          Arangox.start_link(vst_maxsize: invalid)
        end
      end
    end

    test ":vst_maxsize must leave room for the 24-byte chunk header" do
      for invalid <- [1, 24] do
        assert_raise ArgumentError, ~r/:vst_maxsize/, fn ->
          Arangox.start_link(vst_maxsize: invalid)
        end
      end

      assert {:ok, pool} = Arangox.start_link(client: ProbeClient, pool_size: 1, vst_maxsize: 25)
      on_exit(fn -> stop_pool(pool) end)
    end

    # The deprecated fallback has to be validated in exactly the same place and
    # by exactly the same rules as the option. `resolve_options/1` reads it on
    # every connect and must not raise there, so `start_link/1` is the only
    # remaining place that can reject it. Leaving the fallback
    # unchecked would let `config :arangox, :vst_maxsize, 10` reach
    # `VelocyClient.request/3` and raise a MatchError out of a DBConnection
    # callback.
    test "an invalid :vst_maxsize in the deprecated application config is rejected too" do
      Application.put_env(:arangox, :vst_maxsize, 10)

      assert_raise ArgumentError, ~r/:vst_maxsize/, fn ->
        Arangox.start_link(client: ProbeClient)
      end

      assert_raise ArgumentError, ~r/:vst_maxsize/, fn ->
        Arangox.child_spec(client: ProbeClient)
      end
    end

    test "an invalid :json_library in the deprecated application config is rejected too" do
      Application.put_env(:arangox, :json_library, "Jason")

      assert_raise ArgumentError, ~r/:json_library/, fn ->
        Arangox.start_link(client: ProbeClient)
      end
    end

    test "a valid start option still wins over invalid application config" do
      Application.put_env(:arangox, :vst_maxsize, 10)

      pool = start_pool(vst_maxsize: 1_024)

      assert %Response{status: 200} = Arangox.get!(pool, "/wins")
      assert_receive {:probe, "/wins", _json, 1_024}
    end

    test "child_spec/1 validates the same options as start_link/1" do
      assert_raise ArgumentError, ~r/:vst_maxsize/, fn ->
        Arangox.child_spec(vst_maxsize: 0)
      end

      assert_raise ArgumentError, ~r/:json_library/, fn ->
        Arangox.child_spec(json_library: "Jason")
      end
    end

    # HTTP/1.1 carries one request per connection, so DBConnection's pool size
    # of one would serialize the whole application — and the supervised path
    # is the normal production path.
    test "child_spec/1 applies the same pool size default as start_link/1" do
      assert %{start: {_mod, _fun, [{Arangox.Connection, opts}]}} =
               Arangox.child_spec(client: ProbeClient)

      assert Keyword.get(opts, :pool_size) == 10

      assert %{start: {_mod, _fun, [{Arangox.Connection, opts}]}} =
               Arangox.child_spec(client: ProbeClient, pool_size: 3)

      assert Keyword.get(opts, :pool_size) == 3
    end

    # `Arangox.Connection` must not raise out of `connect/1`, so a malformed
    # callback there is discarded silently — which makes start-up the only
    # place a misconfigured one can ever be reported.
    test ":failover_callback must be an arity-1 function or an MFA tuple" do
      for invalid <- [
            :not_a_callback,
            fn -> :wrong_arity end,
            {IO, :inspect},
            {IO, :no_such_function, []},
            {IO, :inspect, :not_a_list}
          ] do
        assert_raise ArgumentError, ~r/:failover_callback/, fn ->
          Arangox.start_link(failover_callback: invalid)
        end

        assert_raise ArgumentError, ~r/:failover_callback/, fn ->
          Arangox.child_spec(failover_callback: invalid)
        end
      end

      pool = start_pool(failover_callback: {IO, :inspect, []})
      assert %Response{status: 200} = Arangox.get!(pool, "/mfa-accepted")
    end

    test "neither option is reported as unknown" do
      refute capture_log(fn ->
               pool = start_pool(vst_maxsize: 1_024, json_library: Jason)

               assert %Response{status: 200} = Arangox.get!(pool, "/known")
             end) =~ "Unknown option"
    end
  end
end
