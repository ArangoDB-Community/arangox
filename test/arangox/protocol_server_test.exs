defmodule Arangox.ProtocolServerTest do
  @moduledoc """
  Smoke tests proving every `Arangox.ProtocolServer` capability behaves as
  documented, using plain `:gen_tcp` and `Mint` as clients (never arangox
  itself). Unit tier: no Docker, ephemeral ports, `async: true`.
  """

  use ExUnit.Case, async: true

  @moduletag :harness_smoke

  alias Arangox.ProtocolServer

  describe "cowboy listener" do
    test "/status/:code responds with the code and configured headers" do
      {port, server} = start_server()
      ProtocolServer.set_response_headers(server, [{"x-harness", "yes"}])

      response = mint_request(port, "GET", "/status/418")

      assert response.status == 418
      assert {"x-harness", "yes"} in response.headers
      assert response.data == "{}"

      bodyless = mint_request(port, "GET", "/status/204")
      assert bodyless.status == 204
      assert bodyless.data == ""
    end

    test "/echo returns what arrived on the wire" do
      {port, _server} = start_server()

      response =
        mint_request(port, "POST", "/echo?foo=bar", [{"x-echo-test", "1"}], ~s({"a":1}))

      assert response.status == 200
      echo = Jason.decode!(response.data)
      assert echo["method"] == "POST"
      assert echo["path"] == "/echo"
      assert echo["query"] == "foo=bar"
      assert ["x-echo-test", "1"] in echo["headers"]
      assert echo["body"] == ~s({"a":1})
    end

    test "/redirect-503 responds 503 with x-arango-endpoint from config" do
      {port, server} = start_server(redirect_to: "http://replacement.test:8529")

      response = mint_request(port, "GET", "/redirect-503")
      assert response.status == 503
      assert {"x-arango-endpoint", "http://replacement.test:8529"} in response.headers

      ProtocolServer.set_redirect_endpoint(server, "http://other.test:8530")
      response = mint_request(port, "GET", "/redirect-503")
      assert {"x-arango-endpoint", "http://other.test:8530"} in response.headers
    end

    test "every request is recorded and queryable via requests/1 and /record" do
      {port, server} = start_server()

      _ = mint_request(port, "GET", "/status/200", [{"authorization", "Bearer secret"}])
      _ = mint_request(port, "POST", "/echo", [], "hello")

      assert [first, second] = ProtocolServer.requests(server)
      assert first["method"] == "GET"
      assert first["path"] == "/status/200"
      assert ["authorization", "Bearer secret"] in first["headers"]
      assert second["method"] == "POST"
      assert second["path"] == "/echo"
      assert second["body"] == "hello"

      response = mint_request(port, "GET", "/record")
      assert response.status == 200
      # the /record request itself is recorded before responding
      assert [%{"path" => "/status/200"}, %{"path" => "/echo"}, %{"path" => "/record"}] =
               Jason.decode!(response.data)
    end

    test "/hang never responds" do
      {port, _server} = start_server()

      response = mint_request(port, "GET", "/hang", [], nil, 400)
      assert response.timeout
      assert response.status == nil
    end

    test "/trailers sends trailing headers after a chunked body (client sent te: trailers)" do
      {port, _server} = start_server()

      socket = tcp_connect(port)

      :ok =
        :gen_tcp.send(
          socket,
          "GET /trailers HTTP/1.1\r\nhost: localhost\r\nte: trailers\r\n\r\n"
        )

      {raw, :timeout} = recv_until(socket)
      assert raw =~ "HTTP/1.1 200"
      assert raw =~ "transfer-encoding: chunked"
      assert raw =~ "body-before-trailers"
      # trailers arrive after the terminating 0-length chunk
      assert [_body, trailer_part] = String.split(raw, "\r\n0\r\n", parts: 2)
      assert trailer_part =~ "x-protocol-server-trailer: trailer-value"
      :gen_tcp.close(socket)
    end

    test "/early-hints sends a 103 informational response before the 200" do
      {port, _server} = start_server()

      socket = tcp_connect(port)
      :ok = :gen_tcp.send(socket, "GET /early-hints HTTP/1.1\r\nhost: localhost\r\n\r\n")

      {raw, :timeout} = recv_until(socket)
      assert raw =~ "HTTP/1.1 103"
      assert raw =~ "link: </assets/app.css>; rel=preload; as=style"
      assert raw =~ "HTTP/1.1 200"
      :gen_tcp.close(socket)
    end

    test "/stall and /truncate on the cowboy listener point at the raw listener" do
      {port, _server} = start_server()

      assert mint_request(port, "GET", "/stall").status == 501
      assert mint_request(port, "GET", "/truncate").status == 501
    end
  end

  describe "raw listener" do
    test "/hang accepts the request and never responds" do
      {port, _server} = start_server(listener: :raw)

      socket = tcp_connect(port)
      :ok = :gen_tcp.send(socket, "GET /hang HTTP/1.1\r\nhost: localhost\r\n\r\n")

      assert {:error, :timeout} = :gen_tcp.recv(socket, 0, 400)
      :gen_tcp.close(socket)
    end

    test "/stall claims a large content-length, sends a partial body, then hangs" do
      {port, _server} = start_server(listener: :raw)

      socket = tcp_connect(port)
      :ok = :gen_tcp.send(socket, "GET /stall HTTP/1.1\r\nhost: localhost\r\n\r\n")

      {raw, :timeout} = recv_until(socket)
      assert raw =~ "HTTP/1.1 200 OK"
      assert raw =~ "content-length: 100000"
      assert raw =~ ~s({"partial":)
      assert byte_size(raw) < 100_000
      # still hanging, not closed
      assert {:error, :timeout} = :gen_tcp.recv(socket, 0, 300)
      :gen_tcp.close(socket)
    end

    test "/truncate claims a large content-length then closes the socket mid-body" do
      {port, _server} = start_server(listener: :raw)

      socket = tcp_connect(port)
      :ok = :gen_tcp.send(socket, "GET /truncate HTTP/1.1\r\nhost: localhost\r\n\r\n")

      {raw, :closed} = recv_until(socket)
      assert raw =~ "HTTP/1.1 200 OK"
      assert raw =~ "content-length: 100000"
      assert raw =~ ~s({"partial":)
      assert byte_size(raw) < 100_000
    end

    test "raw requests are recorded" do
      {port, server} = start_server(listener: :raw)

      socket = tcp_connect(port)
      :ok = :gen_tcp.send(socket, "GET /truncate?x=1 HTTP/1.1\r\nhost: localhost\r\n\r\n")
      {_raw, :closed} = recv_until(socket)

      assert [entry] = ProtocolServer.requests(server)
      assert entry["method"] == "GET"
      assert entry["path"] == "/truncate"
      assert entry["query"] == "x=1"
      assert ["host", "localhost"] in entry["headers"]
    end
  end

  describe "TLS" do
    test "tls: true serves the harness certificate, verifiable against the harness CA" do
      {port, _server} = start_server(tls: true)

      {:ok, conn} = mint_connect(:https, port, protocols: [:http1])
      assert Mint.HTTP.protocol(conn) == :http1

      response = mint_request_on(conn, "GET", "/status/200")
      assert response.status == 200
      assert response.data == "{}"
    end

    test "tls: :http2 negotiates HTTP/2 via ALPN when the client offers it" do
      {port, _server} = start_server(tls: :http2)

      {:ok, conn} = mint_connect(:https, port, protocols: [:http1, :http2])
      assert Mint.HTTP.protocol(conn) == :http2

      response = mint_request_on(conn, "GET", "/status/200")
      assert response.status == 200
    end

    test "raw listener supports tls: true (HTTP/1.1 only)" do
      {port, _server} = start_server(listener: :raw, tls: true)

      {:ok, socket} =
        :ssl.connect(
          ~c"localhost",
          port,
          [
            :binary,
            active: false,
            verify: :verify_peer,
            cacertfile: String.to_charlist(ProtocolServer.ca_path())
          ],
          2_000
        )

      :ok = :ssl.send(socket, "GET /truncate HTTP/1.1\r\nhost: localhost\r\n\r\n")
      {raw, :closed} = ssl_recv_until(socket)
      assert raw =~ "content-length: 100000"
      assert byte_size(raw) < 100_000
    end
  end

  describe "HTTP/2 stream reset" do
    test "/h2-reset sends HEADERS + DATA then a real RST_STREAM(INTERNAL_ERROR)" do
      {port, _server} = start_server(tls: :http2)

      {:ok, conn} = mint_connect(:https, port, protocols: [:http2])
      assert Mint.HTTP.protocol(conn) == :http2

      response = mint_request_on(conn, "GET", "/h2-reset")
      assert response.status == 200
      assert response.data == "partial-before-reset"
      refute response.done
      assert %{reason: {:server_closed_request, :internal_error}} = response.error
    end
  end

  describe "lifecycle" do
    test "instances run concurrently on distinct ephemeral ports and stop cleanly" do
      {port_a, server_a} = start_server()
      {port_b, server_b} = start_server(listener: :raw)
      assert port_a != port_b

      assert mint_request(port_a, "GET", "/status/200").status == 200
      assert :ok = ProtocolServer.stop(server_a)
      assert :ok = ProtocolServer.stop(server_b)
      # stop is idempotent
      assert :ok = ProtocolServer.stop(server_a)
      assert {:error, _} = :gen_tcp.connect({127, 0, 0, 1}, port_b, [:binary], 500)
    end
  end

  ## Helpers

  defp start_server(opts \\ []) do
    assert {:ok, port, server} = ProtocolServer.start(opts)
    on_exit(fn -> ProtocolServer.stop(server) end)
    {port, server}
  end

  defp mint_connect(scheme, port, opts) do
    transport_opts =
      if scheme == :https do
        [cacertfile: ProtocolServer.ca_path()]
      else
        []
      end

    Mint.HTTP.connect(scheme, "localhost", port,
      transport_opts: transport_opts,
      protocols: Keyword.get(opts, :protocols, [:http1])
    )
  end

  defp mint_request(port, method, path, headers \\ [], body \\ nil, timeout \\ 5_000) do
    {:ok, conn} = mint_connect(:http, port, [])
    mint_request_on(conn, method, path, headers, body, timeout)
  end

  defp mint_request_on(conn, method, path, headers \\ [], body \\ nil, timeout \\ 5_000) do
    {:ok, conn, ref} = Mint.HTTP.request(conn, method, path, headers, body)
    {conn, response} = collect(conn, ref, empty_response(), timeout)
    Mint.HTTP.close(conn)
    response
  end

  defp empty_response do
    %{status: nil, headers: [], trailers: [], data: "", done: false, error: nil, timeout: false}
  end

  defp collect(conn, ref, response, timeout) do
    if response.done or response.error do
      {conn, response}
    else
      receive do
        message ->
          case Mint.HTTP.stream(conn, message) do
            {:ok, conn, entries} ->
              collect(conn, ref, apply_entries(response, ref, entries), timeout)

            {:error, conn, error, entries} ->
              response = apply_entries(response, ref, entries)
              {conn, %{response | error: response.error || error}}

            :unknown ->
              collect(conn, ref, response, timeout)
          end
      after
        timeout -> {conn, %{response | timeout: true}}
      end
    end
  end

  defp apply_entries(response, ref, entries) do
    Enum.reduce(entries, response, fn
      {:status, ^ref, status}, acc ->
        %{acc | status: status}

      {:headers, ^ref, headers}, acc ->
        if acc.headers == [] do
          %{acc | headers: headers}
        else
          %{acc | trailers: acc.trailers ++ headers}
        end

      {:data, ^ref, data}, acc ->
        %{acc | data: acc.data <> data}

      {:done, ^ref}, acc ->
        %{acc | done: true}

      {:error, ^ref, error}, acc ->
        %{acc | error: error}
    end)
  end

  defp tcp_connect(port) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
    socket
  end

  defp recv_until(socket, acc \\ "") do
    case :gen_tcp.recv(socket, 0, 500) do
      {:ok, data} -> recv_until(socket, acc <> data)
      {:error, :timeout} -> {acc, :timeout}
      {:error, :closed} -> {acc, :closed}
    end
  end

  defp ssl_recv_until(socket, acc \\ "") do
    case :ssl.recv(socket, 0, 500) do
      {:ok, data} -> ssl_recv_until(socket, acc <> data)
      {:error, :timeout} -> {acc, :timeout}
      {:error, :closed} -> {acc, :closed}
    end
  end
end
