defmodule Arangox.RedactionTest.StateProbe do
  @moduledoc """
  Reports the connection state the real connect pipeline built.

  Sends `inspect(state)` and the state itself to the process registered as
  `Arangox.RedactionTest.Probe` on every request, so a test can assert on what
  `inspect/1` reveals about a pool that was configured with credentials —
  without reaching inside `Arangox.Connection` to construct state by hand.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Request, Response}

  @impl true
  def connect(_endpoint, _opts), do: {:ok, make_ref()}

  @impl true
  def request(%Request{}, _opts, %Connection{} = state) do
    case Process.whereis(Arangox.RedactionTest.Probe) do
      nil -> :ok
      pid -> send(pid, {:state, state, inspect(state, limit: :infinity)})
    end

    {:ok, %Response{status: 200, headers: [], body: nil}, state}
  end

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.RedactionTest do
  @moduledoc """
  No driver-produced error, exception message, log line or struct
  inspection contains authentication material.

  Unit and protocol tier: no Docker.

  ## Why there is no option to turn this off

  `DBConnection` ships `:show_sensitive_data_on_connection_error`, and it does
  not cover arangox. It sanitizes only exceptions that **escape** `connect/1`
  (`db_connection/lib/db_connection/connection.ex`, the `rescue` clause);
  arangox's `connect/1` never raises — it returns
  `{:error, exception}`, which `DBConnection` logs through
  `Exception.format_banner/3` with no sanitization at all. Making connect safer
  moved arangox out of the only redaction `DBConnection` offers.

  Redaction is therefore unconditional: it happens where the endpoint is
  stored, and there is no flag. The tests below set the `DBConnection` flag
  **on** — the least favourable setting — so that a reader cannot mistake the
  flag for what makes them pass.
  """

  use ExUnit.Case, async: false

  import TestHelper, only: [stop_pool: 1]

  # The verification gate `mix test --only redaction` selects this
  # file; the tag adds nothing to a normal run, which already includes it.
  @moduletag :redaction

  import ExUnit.CaptureLog

  alias Arangox.{Client, Connection, Endpoint, Error, MintClient, ProtocolServer, Request}

  doctest Arangox.Endpoint, only: [redact: 1]

  @password "hunter2"
  @username "root"
  @token "s3cr3ttokenvalue"
  @encoded Base.encode64("#{@username}:#{@password}")

  # Nothing is listening here.
  @refused 65_001
  @endpoint_with_userinfo "http://#{@username}:#{@password}@localhost:#{@refused}"

  setup do
    Process.register(self(), Arangox.RedactionTest.Probe)
    :ok
  end

  describe "Arangox.Endpoint.redact/1:" do
    test "an @ anywhere costs everything after the scheme" do
      assert Endpoint.redact("http://root:hunter2@localhost:8529") == "http://[redacted]"

      assert Endpoint.redact("https://root:hunter2@db.internal:8529/path?q=1") ==
               "https://[redacted]"

      # The username is authentication material too.
      assert Endpoint.redact("http://root@localhost:8529") == "http://[redacted]"
    end

    test "leaves an endpoint without an @ alone" do
      for endpoint <- [
            "http://localhost:8529",
            "https://db.internal:8529",
            "tcp://localhost:8529",
            "http://unix:/tmp/arangodb.sock",
            "unix:///tmp/arangodb.sock"
          ] do
        assert Endpoint.redact(endpoint) == endpoint
      end
    end

    test "a password containing an @ cannot survive" do
      redacted = Endpoint.redact("http://root:pass@word@localhost:8529")

      assert redacted == "http://[redacted]"
      refute redacted =~ "pass"
    end

    # The redaction never looks for the userinfo, only for the scheme: a
    # credential sitting outside a well-formed authority is not found by
    # parsing, so anything an @ could be part of has to go wholesale.
    test "a typo'd endpoint hiding its password outside the authority still loses it" do
      redacted = Endpoint.redact("http://root:hunter2/path@db:8529")

      assert redacted == "http://[redacted]"
      refute redacted =~ @password
    end

    test "never raises, whatever it is given" do
      assert Endpoint.redact(:not_a_binary) == :not_a_binary
      assert Endpoint.redact(nil) == nil
      assert Endpoint.redact("") == "[redacted]"
      assert Endpoint.redact("root:hunter2@localhost") == "[redacted]"
    end

    test "a credential written ahead of the scheme is redacted, not kept as a prefix" do
      # Keeping the bytes before "://" is only safe when the userinfo comes
      # after it. Prefixing credentials puts them in front, where a prefix
      # rule preserves them verbatim.
      assert Endpoint.redact("root:hunter2@http://localhost:8529") == "[redacted]"
      assert Endpoint.redact("root:hunter2@tcp://db.internal:8529") == "[redacted]"
    end
  end

  describe "a failed connect to an endpoint carrying userinfo:" do
    test "the log contains neither the password nor its base64 encoding" do
      log =
        capture_log(fn ->
          {:ok, pool} =
            Arangox.start_link(
              endpoints: @endpoint_with_userinfo,
              auth: {:basic, @username, @password},
              client: MintClient,
              pool_size: 1,
              backoff_min: 10
            )

          on_exit(fn -> stop_pool(pool) end)

          # Let at least one backoff cycle log.
          Process.sleep(200)
        end)

      assert log =~ "failed to connect",
             "the connect-failure line never appeared, so this test proves nothing"

      refute log =~ @password
      refute log =~ @encoded
      refute log =~ Base.encode64(@password)
      assert log =~ "http://[redacted]"
    end

    test "the returned error carries the redacted endpoint" do
      assert {:error, %Error{} = error} =
               Connection.connect(
                 endpoints: @endpoint_with_userinfo,
                 auth: {:basic, @username, @password},
                 client: MintClient
               )

      assert error.endpoint == "http://[redacted]"
      assert error.reason == :econnrefused

      message = Exception.message(error)
      refute message =~ @password
      refute message =~ @encoded
    end

    test ":failover_callback receives an error with no credentials in it" do
      test = self()

      assert {:error, %Error{}} =
               Connection.connect(
                 endpoints: [@endpoint_with_userinfo],
                 auth: {:basic, @username, @password},
                 client: MintClient,
                 failover_callback: fn error -> send(test, {:failover, error}) end
               )

      assert_receive {:failover, %Error{} = error}
      refute inspect(error) =~ @password
      refute Exception.message(error) =~ @password
    end

    test "an endpoint that does not even parse still does not leak" do
      assert {:error, %Error{} = error} =
               Connection.connect(
                 endpoints: "gopher://#{@username}:#{@password}@localhost:1",
                 client: MintClient
               )

      message = Exception.message(error)
      assert message =~ "Invalid protocol in endpoint configuration"
      refute message =~ @password
      refute inspect(error) =~ @password
    end

    test "start_link/1 rejecting a malformed :endpoints list does not print the password" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(endpoints: [@endpoint_with_userinfo, :not_a_binary])
        end)

      refute Exception.message(error) =~ @password
    end
  end

  # Redaction's single exception. arangox accepts `:show_sensitive_data_on_connection_error`
  # (it is among the known DBConnection options), so a developer who sets it
  # expects it to work. DBConnection's own sanitizer cannot deliver that here: it
  # wraps only exceptions *raised* out of `connect/1`, and arangox
  # returns instead. Honouring it is therefore arangox's job, and it reaches the
  # connect-time error and nothing else.
  describe "show_sensitive_data_on_connection_error:" do
    test "restores the credentials in the connect-time error when set" do
      assert {:error, %Error{} = error} =
               Connection.connect(
                 endpoints: @endpoint_with_userinfo,
                 auth: {:basic, @username, @password},
                 client: MintClient,
                 show_sensitive_data_on_connection_error: true
               )

      assert error.endpoint == @endpoint_with_userinfo
      assert Exception.message(error) =~ @password
    end

    test "the log shows them too, which is the point of setting it" do
      log =
        capture_log(fn ->
          {:ok, pool} =
            Arangox.start_link(
              endpoints: @endpoint_with_userinfo,
              auth: {:basic, @username, @password},
              client: MintClient,
              pool_size: 1,
              backoff_min: 10,
              show_sensitive_data_on_connection_error: true
            )

          on_exit(fn -> stop_pool(pool) end)
          Process.sleep(200)
        end)

      assert log =~ "failed to connect",
             "the connect-failure line never appeared, so this test proves nothing"

      assert log =~ @password
    end

    test "redacts by default, so the flag is what makes the difference" do
      assert {:error, %Error{endpoint: redacted}} =
               Connection.connect(
                 endpoints: @endpoint_with_userinfo,
                 auth: {:basic, @username, @password},
                 client: MintClient
               )

      refute redacted =~ @password
    end

    test "does not reach inspect/1, which has no opt-out" do
      config = %{
        client: MintClient,
        endpoints: [@endpoint_with_userinfo],
        endpoint_mapper: nil,
        redirects_left: 3,
        failover?: false,
        json_library: Jason,
        content_type: :json,
        max_body_size: 134_217_728,
        vst_maxsize: 30_720,
        request_timeout: 15_000,
        show_sensitive?: true,
        opts: [auth: {:basic, @username, @password}]
      }

      state =
        Connection.new(
          make_ref(),
          @endpoint_with_userinfo,
          Endpoint.new(@endpoint_with_userinfo),
          config
        )

      inspected = inspect(state, limit: :infinity)

      refute inspected =~ @password
      refute inspected =~ @encoded
      refute state.endpoint =~ @password
    end
  end

  describe "inspecting connection state:" do
    test "reveals neither the password nor the encoded authorization header" do
      pool = start_probe_pool(auth: {:basic, @username, @password})

      assert {:ok, _response} = Arangox.get(pool, "/anything")
      assert_receive {:state, %Connection{} = state, inspected}

      # The credential really is in state -- the request path needs it. What is
      # under test is that inspecting it does not disclose it.
      assert state.auth == {:basic, @username, @password}
      assert {"authorization", "Basic #{@encoded}"} in state.headers

      refute inspected =~ @password
      refute inspected =~ @encoded
      refute inspected =~ @username

      # ...and it is still recognisably a connection struct, with the fields
      # anyone actually inspects it for.
      assert inspected =~ "%Arangox.Connection{"
      assert inspected =~ "authorization"
      assert inspected =~ "[redacted]"
      assert inspected =~ "client: Arangox.RedactionTest.StateProbe"
    end

    test "redacts a bearer token too" do
      pool = start_probe_pool(auth: {:bearer, @token})

      assert {:ok, _response} = Arangox.get(pool, "/anything")
      assert_receive {:state, %Connection{} = state, inspected}

      assert state.auth == {:bearer, @token}
      refute inspected =~ @token
    end

    test "a state configured with a userinfo endpoint holds it redacted" do
      {:ok, port, server} = ProtocolServer.start(routes: healthy_routes())
      on_exit(fn -> ProtocolServer.stop(server) end)

      pool =
        start_probe_pool(
          auth: {:basic, @username, @password},
          endpoints: "http://#{@username}:#{@password}@localhost:#{port}"
        )

      assert {:ok, _response} = Arangox.get(pool, "/anything")
      assert_receive {:state, %Connection{} = state, inspected}

      assert state.endpoint == "http://[redacted]"
      refute inspected =~ @password
    end

    test "state with no auth configured inspects unchanged" do
      pool = start_probe_pool([])

      assert {:ok, _response} = Arangox.get(pool, "/anything")
      assert_receive {:state, %Connection{auth: nil}, inspected}

      assert inspected =~ "auth: nil"
      refute inspected =~ "[redacted]"
    end
  end

  # The rule is enforced at `Arangox.Client.request/3`, the seam every client
  # and every connect probe crosses, rather than by a transport: HTTP/1.1
  # refuses such a value locally, but under HTTP/2 the header is HPACK-encoded
  # and only the server objects, so a transport-dependent check would name the
  # offending header on one protocol and not the other.
  describe "a header value the driver refuses:" do
    test "a bearer token with an illegal header byte is not in the error message" do
      {:ok, port, server} = ProtocolServer.start()
      on_exit(fn -> ProtocolServer.stop(server) end)

      {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = struct(Connection, socket: socket, client: MintClient)

      request = %Request{
        method: :get,
        path: "/status/200",
        # A newline is not a legal header value byte, and for this header the
        # value is the credential.
        headers: [{"authorization", "Bearer #{@token}\nx"}]
      }

      assert {:error, %Error{} = error, _state} = Client.request(request, [], state)

      assert error.reason == :invalid_header_value

      message = Exception.message(error)
      assert message =~ "authorization"
      refute message =~ @token
      refute inspect(error) =~ @token

      # Refused before the transport, so nothing carrying it was written.
      assert ProtocolServer.requests(server) == []
    end

    test "an illegal byte in a header name is refused too" do
      {:ok, port, server} = ProtocolServer.start()
      on_exit(fn -> ProtocolServer.stop(server) end)

      {:ok, socket} = MintClient.connect(Endpoint.new("http://localhost:#{port}"), [])
      state = struct(Connection, socket: socket, client: MintClient)

      request = %Request{
        method: :get,
        path: "/status/200",
        headers: [{"x-smuggled\r\nx-injected", "1"}]
      }

      assert {:error, %Error{reason: :invalid_header_value}, _state} =
               Client.request(request, [], state)

      assert ProtocolServer.requests(server) == []
    end

    test "the same failure through a pool keeps the token out of the log" do
      {:ok, port, server} = ProtocolServer.start(routes: healthy_routes())
      on_exit(fn -> ProtocolServer.stop(server) end)

      log =
        capture_log(fn ->
          {:ok, pool} =
            Arangox.start_link(
              endpoints: "http://localhost:#{port}",
              auth: {:bearer, "#{@token}\nx"},
              client: MintClient,
              pool_size: 1,
              backoff_min: 10,
              show_sensitive_data_on_connection_error: true
            )

          on_exit(fn -> stop_pool(pool) end)
          Process.sleep(200)
        end)

      assert log =~ "failed to connect",
             "the connect-failure line never appeared, so this test proves nothing"

      refute log =~ @token
      assert log =~ "authorization"
    end
  end

  describe "an :auth option of an unsupported shape:" do
    test "raises without printing the credential" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(auth: {:basic, @username, @password, :extra})
        end)

      message = Exception.message(error)
      refute message =~ @password
      refute message =~ @username
      assert message =~ "4-element tuple tagged :basic"
      assert message =~ "{:basic, username, password}"
    end

    test "a bare binary is described by size, not by value" do
      error = assert_raise(ArgumentError, fn -> Arangox.start_link(auth: @token) end)

      message = Exception.message(error)
      refute message =~ @token
      assert message =~ "#{byte_size(@token)}-byte binary"
    end

    test "a map is described by its size" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(auth: %{user: @username, password: @password})
        end)

      message = Exception.message(error)
      refute message =~ @password
      assert message =~ "a map with 2 keys"
    end

    test "a supported tag carrying a non-string credential is refused" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(auth: {:bearer, %{token: @token}})
        end)

      message = Exception.message(error)
      refute message =~ @token
      assert message =~ "string"
    end

    test "a non-string username or password is refused the same way" do
      error =
        assert_raise(ArgumentError, fn ->
          Arangox.start_link(auth: {:basic, %{user: @username}, @password})
        end)

      message = Exception.message(error)
      refute message =~ @username
      refute message =~ @password
      assert message =~ "string"
    end

    # `DBConnection.start_link(Arangox.Connection, ...)` skips
    # `Arangox.start_link/1` and with it `Auth.validate/1`, so the connect
    # pipeline is the last line of defense: a credential of a shape the header
    # interpolation would choke on must come back as a described error, never
    # as a raised message carrying the inspected value into the log.
    test "a pool started around the validation still cannot leak the credential into the log" do
      {:ok, port, server} = ProtocolServer.start(routes: healthy_routes())
      on_exit(fn -> ProtocolServer.stop(server) end)

      log =
        capture_log(fn ->
          {:ok, pool} =
            DBConnection.start_link(Arangox.Connection,
              endpoints: "http://localhost:#{port}",
              auth: {:bearer, %{token: @token}},
              client: MintClient,
              pool_size: 1,
              backoff_min: 10,
              show_sensitive_data_on_connection_error: true
            )

          on_exit(fn -> stop_pool(pool) end)
          Process.sleep(200)
        end)

      assert log =~ "failed to connect",
             "the connect-failure line never appeared, so this test proves nothing"

      refute log =~ @token
    end
  end

  describe "the echoed request:" do
    test "the authorization header is redacted on the way back out" do
      pool = start_probe_pool(auth: {:basic, @username, @password})

      assert {:ok, request, _response} = Arangox.request(pool, :get, "/anything")

      assert {"authorization", "[redacted]"} in request.headers
      refute inspect(request) =~ @encoded
    end
  end

  test "connection state holding an open transaction inspects without the identifier" do
    state =
      struct(Connection,
        socket: nil,
        client: MintClient,
        endpoint: "http://localhost:1",
        trx_id: "3298558923352"
      )

    rendered = inspect(state)
    refute rendered =~ "3298558923352"
    assert rendered =~ ~s(trx_id: "[redacted]")
  end

  # The echoed request is sanitized before it is returned, but `DBConnection`
  # logs the in-flight query — the raw request, headers already merged — when
  # a call fails. Redaction therefore has to live on `inspect/1` itself.
  describe "inspecting a raw request:" do
    test "the authorization value is redacted while other headers stay visible" do
      request = %Request{
        method: :get,
        path: "/x",
        headers: [{"authorization", "Basic #{@encoded}"}, {"x-custom", "kept"}]
      }

      inspected = inspect(request)

      refute inspected =~ @encoded
      assert inspected =~ "[redacted]"
      assert inspected =~ "kept"
      assert inspected =~ "/x"
    end

    # HTTP header names are case-insensitive, and a caller setting
    # `"Authorization"` is doing nothing wrong — an exact-key match would leave
    # the credential visible in the one place the rule exists to cover.
    test "redaction does not depend on the header name's case" do
      for name <- ["Authorization", "AUTHORIZATION", "X-Arango-Trx-Id"] do
        request = %Request{method: :get, path: "/x", headers: [{name, "Basic #{@encoded}"}]}

        refute inspect(request) =~ @encoded, "#{name} was echoed unredacted"
      end
    end

    test "the transaction identifier is redacted like authentication material" do
      request = %Request{
        method: :get,
        path: "/x",
        headers: [{"x-arango-trx-id", "3298558923352"}]
      }

      refute inspect(request) =~ "3298558923352"
    end
  end

  describe "the server's message is bounded when rendered:" do
    test "Exception.message/1 truncates a pathological message" do
      long = String.duplicate("a", Error.message_limit() * 3)
      rendered = Exception.message(%Error{message: long})

      assert byte_size(rendered) < byte_size(long)
      assert rendered =~ "truncated"
    end

    test "a message within the limit is untouched" do
      assert Exception.message(%Error{message: "short", endpoint: "e"}) == "[e] short"
    end

    # A byte-positioned cut can land inside a multibyte character and turn a
    # valid message into an invalid binary.
    test "the cut lands on a codepoint boundary" do
      long = String.duplicate("€", Error.message_limit())
      rendered = Exception.message(%Error{message: long})

      assert String.valid?(rendered)
      assert byte_size(rendered) < byte_size(long)
    end
  end

  ## Helpers

  defp healthy_routes do
    json = [{"content-type", "application/json"}]

    %{
      "/_admin/server/availability" => {200, json, ~s({"error":false,"code":200})},
      "/_api/version" => {200, json, ~s({"version":"3.12.5"})}
    }
  end

  defp start_probe_pool(opts) do
    {:ok, pool} =
      Arangox.start_link(
        Keyword.merge(
          [client: Arangox.RedactionTest.StateProbe, pool_size: 1],
          opts
        )
      )

    on_exit(fn -> stop_pool(pool) end)
    pool
  end
end
