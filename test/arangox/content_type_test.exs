defmodule Arangox.ContentTypeTest.StubClient do
  @moduledoc """
  A scripted `Arangox.Client` that reports the wire request to the owning test
  process as `{:request, %Arangox.Request{}}` — headers merged, body encoded —
  and answers with a scripted `{status, headers, body}`, so a test can assert
  both on what the pool put on the wire and on how it decodes what comes back.

  Scripts are keyed by `{method, path}` and travel in the fabricated socket, so
  there is no named process and the tests stay `async: true`. Anything
  unscripted answers `200 {}` with no content type.
  """

  @behaviour Arangox.Client

  alias Arangox.{Connection, Endpoint, Error, Request, Response}

  @impl true
  def connect(%Endpoint{}, opts) do
    {:ok, opts |> Keyword.fetch!(:client_opts) |> Map.new()}
  end

  @impl true
  def request(%Request{} = request, _opts, %Connection{socket: socket} = state) do
    send(socket.owner, {:request, request})

    case Map.get(socket.script, {request.method, request.path}, {200, [], "{}"}) do
      {:error, reason} ->
        {:error, %Error{reason: reason, message: "scripted #{inspect(reason)}"}, state}

      {status, headers, body} ->
        {:ok, %Response{status: status, headers: headers, body: body}, state}
    end
  end

  @impl true
  def close(%Connection{}), do: :ok
end

defmodule Arangox.ContentTypeTest do
  @moduledoc """
  The content-type seam. A pool's `:content_type` selects the codec
  for request bodies and the `accept` header; response decoding is driven by the
  response's own content type, so a pool that asked for VelocyPack still reads a
  JSON reply when the server declines.

  Protocol tier: no Docker, no network — the client is scripted.
  """

  use ExUnit.Case, async: true

  alias Arangox.{Connection, Error, Request, Response}
  alias Arangox.ContentTypeTest.StubClient

  @vpack "application/x-velocypack"
  @json "application/json"
  @dump "application/x-arango-dump"

  defp state(fields) do
    struct(
      Connection,
      [
        socket: %{owner: self(), script: Keyword.get(fields, :script, %{})},
        client: StubClient,
        endpoint: "http://stub",
        headers: [],
        cursors: %{}
      ] ++ Keyword.delete(fields, :script)
    )
  end

  defp run(request, fields) do
    Connection.handle_execute(nil, request, [], state(fields))
  end

  defp post(path, body), do: %Request{method: :post, path: path, body: body}
  defp get(path), do: %Request{method: :get, path: path}

  ## Request encoding

  describe "the default pool" do
    test "sends a JSON body and sets no VelocyPack content type" do
      run(post("/x", %{"a" => 1}), [])

      assert_received {:request, %Request{body: body, headers: headers}}
      assert body == Jason.encode!(%{"a" => 1})
      refute {"content-type", @vpack} in headers
    end

    test "sends no accept header, leaving the server default" do
      run(get("/x"), [])

      assert_received {:request, %Request{headers: headers}}
      refute Enum.any?(headers, fn {name, _} -> name == "accept" end)
    end
  end

  describe "a VelocyPack pool" do
    test "encodes the request body as VelocyPack and names the content type" do
      run(post("/x", %{"a" => 1}), content_type: :velocypack)

      assert_received {:request, %Request{body: body, headers: headers}}
      assert body == VelocyPack.encode!(%{"a" => 1})
      assert {"content-type", @vpack} in headers
    end

    test "asks for a VelocyPack response on every request, body or not" do
      run(get("/x"), content_type: :velocypack)

      assert_received {:request, %Request{headers: headers}}
      assert {"accept", @vpack} in headers
    end

    test "does not override an accept header the caller set" do
      request = %Request{method: :get, path: "/x", headers: [{"accept", @json}]}
      run(request, content_type: :velocypack)

      assert_received {:request, %Request{headers: headers}}
      assert {"accept", @json} in headers and {"accept", @vpack} not in headers
    end

    test "leaves an empty body empty rather than encoding it" do
      run(%Request{method: :post, path: "/x", body: ""}, content_type: :velocypack)

      assert_received {:request, %Request{body: body}}
      assert body == ""
    end
  end

  # VelocyPack is opt-in so the default stays safe, which is only true if
  # opting in does not change what a document may contain. `%DateTime{}` is the
  # sensitive case: `Jason` writes ISO-8601, and velocy encodes it only from
  # 0.1.8 (type `0x1c`).
  describe "codec parity" do
    test "a document carrying a DateTime encodes under both content types" do
      body = %{"at" => ~U[1969-07-20 20:17:00Z]}

      run(post("/x", body), [])
      assert_received {:request, %Request{body: json}}
      assert is_binary(json)

      run(post("/x", body), content_type: :velocypack)
      assert_received {:request, %Request{body: vpack}}

      # The instant, not the struct: type `0x1c` stores milliseconds, so a
      # decoded value carries millisecond precision whatever it was built with.
      assert %{"at" => decoded} = VelocyPack.decode!(vpack)
      assert DateTime.compare(decoded, body["at"]) == :eq
    end
  end

  ## The encode boundary

  # A body the codec rejects is the caller's mistake, not the connection's:
  # nothing reached the wire, so the answer is an error tuple and the
  # connection stays usable.
  describe "encode boundary" do
    test "a body the JSON codec cannot encode returns a structured error rather than raising" do
      assert {:error, %Error{reason: :encode_error}, %Connection{}} =
               run(post("/x", %{"pid" => self()}), [])

      refute_received {:request, _}
    end

    test "a body the VelocyPack codec cannot encode returns a structured error rather than raising" do
      assert {:error, %Error{reason: :encode_error}, %Connection{}} =
               run(post("/x", %{"pid" => self()}), content_type: :velocypack)

      refute_received {:request, _}
    end
  end

  # A success status with a body the codec rejects: the response was fully
  # read, so the connection is healthy and the failure is an error tuple, not
  # a raise out of the callback and not a disconnect.
  describe "decode boundary" do
    test "a malformed VelocyPack body on a success status returns a structured error rather than raising" do
      script = %{{:get, "/x"} => {200, [{"content-type", @vpack}], <<0x1B, 0x00>>}}

      assert {:error, %Error{reason: :decode_error, status: 200}, %Connection{}} =
               run(get("/x"), content_type: :velocypack, script: script)
    end

    test "a malformed JSON body on a success status returns a structured error rather than raising" do
      script = %{{:get, "/x"} => {200, [{"content-type", @json}], "<html>not json"}}

      assert {:error, %Error{reason: :decode_error, status: 200}, %Connection{}} =
               run(get("/x"), script: script)
    end
  end

  # Bounds run before either codec. Each fixture body would produce a
  # *different* error if it reached a codec, so the asserted reason is the
  # proof that the bound fired first.
  describe "pre-decode bounds" do
    test "a body over the configured size bound is rejected before decoding" do
      script = %{{:get, "/x"} => {200, [{"content-type", @json}], String.duplicate("x", 65)}}

      assert {:error, %Error{reason: :body_too_large} = error, %Connection{}} =
               run(get("/x"), max_body_size: 64, script: script)

      assert error.message =~ "64"
      assert error.message =~ "65"
    end

    test "the size bound has a documented default" do
      assert state([]).max_body_size == 134_217_728
    end

    # `:invalid_length` rather than `:decode_error` is the observable proof
    # that arangox's own cap fired: a run that reaches the codec comes back
    # wrapped as `:decode_error` whatever the codec does with it.
    test "a VelocyPack body with a long continuation-byte run is rejected before the parser runs" do
      hostile = <<0x13>> <> String.duplicate(<<0xFF>>, 16_384) <> <<0x01>>
      script = %{{:get, "/x"} => {200, [{"content-type", @vpack}], hostile}}

      assert {:error, %Error{reason: :invalid_length, status: 200}, %Connection{}} =
               run(get("/x"), content_type: :velocypack, script: script)
    end
  end

  # A `content-type` on the request selects the codec, not just the label: the
  # server reads that header to decide how to parse the body, so encoding by
  # the pool's setting while labelling by the caller's puts mislabelled bytes
  # on the wire.
  describe "per-request content type" do
    test "a JSON override on a VelocyPack pool encodes JSON" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"content-type", @json}]}

      run(request, content_type: :velocypack)

      assert_received {:request, %Request{body: body, headers: headers}}
      assert body == Jason.encode!(%{"a" => 1})
      assert {"content-type", @json} in headers
    end

    test "a VelocyPack override on a JSON pool encodes VelocyPack" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"content-type", @vpack}]}

      run(request, [])

      assert_received {:request, %Request{body: body}}
      assert body == VelocyPack.encode!(%{"a" => 1})
    end

    test "the header is matched case-insensitively and ignores parameters" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"Content-Type", "application/json; charset=utf-8"}]}

      run(request, content_type: :velocypack)

      assert_received {:request, %Request{body: body}}
      assert body == Jason.encode!(%{"a" => 1})
    end

    # The server parses the body by its content type, so a body labelled
    # `text/plain` (a JSONL import) or `application/octet-stream` must cross
    # the wire byte-for-byte; running it through the JSON codec turns a
    # payload of lines into one quoted JSON string.
    test "a content type naming neither codec sends a binary body raw" do
      body = ~s({"a":1}\n{"a":2}\n)
      request = post("/_api/import", body)
      request = %{request | headers: [{"content-type", "text/plain; charset=utf-8"}]}

      assert {:ok, _request, %Response{}, _state} = run(request, [])

      assert_received {:request, %Request{body: sent}}
      assert sent == body
    end

    test "a +json suffix still selects the JSON codec" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"content-type", "application/vnd.api+json"}]}

      run(request, [])

      assert_received {:request, %Request{body: body}}
      assert body == Jason.encode!(%{"a" => 1})
    end

    test "a non-binary body under a raw content type is refused, not encoded" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"content-type", "text/plain"}]}

      assert {:error, %Error{reason: :encode_error}, _state} = run(request, [])
      refute_received {:request, %Request{}}
    end

    # The codec is selected from the request's *own* headers — first
    # content-type entry, any casing — never from the pool's `:headers` list.
    # The pool-level codec lives in the `:content_type` option alone.
    test "a request content-type beats a differently-cased pool header entry" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"content-type", @vpack}]}

      run(request, headers: [{"Content-Type", @json}])

      assert_received {:request, %Request{body: body, headers: headers}}
      assert body == VelocyPack.encode!(%{"a" => 1})
      assert headers == [{"Content-Type", @json}, {"content-type", @vpack}]
    end

    test "the codec never consults the pool's :headers list" do
      request = post("/x", %{"a" => 1})

      run(request, headers: [{"content-type", @vpack}])

      assert_received {:request, %Request{body: body, headers: headers}}
      assert body == Jason.encode!(%{"a" => 1})
      assert headers == [{"content-type", @vpack}]
    end

    test "a VelocyPack pool does not duplicate a caller-cased accept header" do
      request = post("/x", %{"a" => 1})
      request = %{request | headers: [{"Accept", @json}]}

      run(request, content_type: :velocypack)

      assert_received {:request, %Request{headers: headers}}
      assert Enum.count(headers, fn {n, _} -> String.downcase(n) == "accept" end) == 1
      assert List.last(headers) == {"content-type", @vpack}
    end
  end

  # An error body is a body: the same size bound and the same content-type
  # dispatch apply. Reaching for the connect-time JSON decoder here cost both.
  describe "error bodies cross the same boundary" do
    test "a VelocyPack error body still yields errorNum and a reason" do
      body = VelocyPack.encode!(%{"error" => true, "errorNum" => 1203, "errorMessage" => "gone"})
      script = %{{:get, "/x"} => {404, [{"content-type", @vpack}], body}}

      assert {:error, %Error{} = error, %Connection{}} =
               run(get("/x"), content_type: :velocypack, script: script)

      assert error.status == 404
      assert error.error_num == 1203
      assert error.reason == :arango_data_source_not_found
      assert error.message == "gone"
    end

    test "an error body over the size bound is refused rather than decoded" do
      script = %{{:get, "/x"} => {500, [{"content-type", @json}], String.duplicate("x", 65)}}

      assert {:error, %Error{reason: :body_too_large}, %Connection{}} =
               run(get("/x"), max_body_size: 64, script: script)
    end

    test "a non-JSON error page still yields a structured error with the status" do
      script = %{{:get, "/x"} => {502, [{"content-type", "text/html"}], "<html>bad gateway"}}

      assert {:error, %Error{status: 502} = error, %Connection{}} = run(get("/x"), script: script)

      assert error.message =~ "<html>"
    end
  end

  ## Response decoding

  # Decoding follows the response's content type, not the pool's request type.
  describe "response decoding" do
    # The surface ships operations whose successes are not JSON — Prometheus
    # metrics, a multipart batch, a Foxx zip bundle. A declared non-JSON type
    # is already in its wire form; decoding it as JSON would turn every such
    # success into `:decode_error`.
    test "a 2xx body with a declared non-JSON type is returned raw" do
      body = "# HELP arangodb_process_statistics\ncounter 42\n"
      script = %{{:get, "/x"} => {200, [{"content-type", "text/plain; charset=utf-8"}], body}}

      assert {:ok, _req, %Response{body: ^body}, %Connection{}} = run(get("/x"), script: script)
    end

    test "an unregistered binary type is returned raw too" do
      body = <<0x50, 0x4B, 0x03, 0x04, 1, 2, 3>>
      script = %{{:get, "/x"} => {200, [{"content-type", "application/zip"}], body}}

      assert {:ok, _req, %Response{body: ^body}, %Connection{}} = run(get("/x"), script: script)
    end

    test "a +json suffix still selects the JSON decoder" do
      script = %{
        {:get, "/x"} => {200, [{"content-type", "application/vnd.api+json"}], ~s({"a":1})}
      }

      assert {:ok, _req, %Response{body: %{"a" => 1}}, %Connection{}} =
               run(get("/x"), script: script)
    end

    test "a VelocyPack response is decoded through the VelocyPack codec" do
      body = VelocyPack.encode!(%{"hello" => "world"})
      script = %{{:get, "/x"} => {200, [{"content-type", @vpack}], body}}

      assert {:ok, _request, %Response{body: decoded}, _state} =
               run(get("/x"), content_type: :velocypack, script: script)

      assert decoded == %{"hello" => "world"}
    end

    test "a JSON response under a VelocyPack pool is still decoded as JSON" do
      script = %{{:get, "/x"} => {200, [{"content-type", @json}], ~s({"hello":"world"})}}

      assert {:ok, _request, %Response{body: decoded}, _state} =
               run(get("/x"), content_type: :velocypack, script: script)

      assert decoded == %{"hello" => "world"}
    end

    test "a dump response still decodes line by line under a VelocyPack pool" do
      body = ~s({"a":1}\n{"b":2}\n)
      script = %{{:get, "/x"} => {200, [{"content-type", @dump}], body}}

      assert {:ok, _request, %Response{body: decoded}, _state} =
               run(get("/x"), content_type: :velocypack, script: script)

      assert decoded == [%{"a" => 1}, %{"b" => 2}]
    end
  end
end
