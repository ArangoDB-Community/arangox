defmodule Arangox.VelocyTest do
  @moduledoc """
  VelocyStream client quality.

  Unit tier, no Docker. `Arangox.VelocyClient.request/3` writes its whole
  request before it reads anything, so a bare `:gen_tcp` listener that accepts
  and stays silent is enough to assert on what the client wrote — and on what
  it declined to write.

  The socket is built directly rather than through `connect/2`: the handshake is
  covered by `Arangox.ProtocolTest`.
  """

  use ExUnit.Case, async: false

  alias Arangox.{Connection, Error, Request, Response, VelocyClient}

  # Accepts one connection and stays silent, forwarding everything that arrives
  # to the test process so the bytes the client wrote can be asserted on.
  defp listener! do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)
    test = self()

    acceptor =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        forward(socket, test)
      end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listen)
    end)

    port
  end

  defp forward(socket, test) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        send(test, {:wire, data})
        forward(socket, test)

      {:error, _reason} ->
        :ok
    end
  end

  # Everything that arrived, concatenated. TCP is a stream, so one send is not
  # one receive: the chunks are reassembled here and re-split by their own
  # headers rather than by however the kernel happened to deliver them.
  defp wire(acc \\ "") do
    receive do
      {:wire, data} -> wire(acc <> data)
    after
      200 -> acc
    end
  end

  # A chunk is a 24-byte header followed by its payload. The header's second
  # field packs the chunk number and the "is first" flag into 32 bits, written
  # as the big-endian rendering of a little-endian decode — so the four bytes on
  # the wire are that packing reversed.
  defp parse_chunks(binary, acc \\ [])

  defp parse_chunks("", acc), do: Enum.reverse(acc)

  defp parse_chunks(
         <<length::little-32, packed::binary-size(4), _msg_id::little-64, msg_length::little-64,
           rest::binary>>,
         acc
       ) do
    payload_size = length - 24
    <<payload::binary-size(^payload_size), tail::binary>> = rest

    <<chunk_n::31, is_first::1>> =
      packed |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()

    chunk = %{
      chunk_n: chunk_n,
      first?: is_first == 1,
      payload: payload,
      msg_length: msg_length
    }

    parse_chunks(tail, [chunk | acc])
  end

  defp state!(fields \\ []) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, listener!(), [:binary, active: false], 1_000)

    on_exit(fn -> :gen_tcp.close(socket) end)

    struct(
      Connection,
      [
        socket: {:gen_tcp, socket},
        client: VelocyClient,
        vst_maxsize: 30_720,
        request_timeout: 200
      ] ++ fields
    )
  end

  # Answers with scripted bytes once the client has written its request, then
  # closes. This is how a malformed or truncated reply is put in front of the
  # client without a server willing to produce one.
  defp replying_listener!(reply) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)

    acceptor =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listen)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 5_000)
        :ok = :gen_tcp.send(socket, reply)
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      Process.exit(acceptor, :kill)
      :gen_tcp.close(listen)
    end)

    port
  end

  defp replying_state!(reply, fields \\ []) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, replying_listener!(reply), [:binary, active: false], 1_000)

    on_exit(fn -> :gen_tcp.close(socket) end)

    struct(
      Connection,
      [
        socket: {:gen_tcp, socket},
        client: VelocyClient,
        vst_maxsize: 30_720,
        request_timeout: 500
      ] ++ fields
    )
  end

  defp chunk_header(chunk_length, chunk_n, is_first, msg_length \\ 0) do
    packed = :binary.decode_unsigned(<<chunk_n::31, is_first::1>>, :little)

    <<chunk_length::little-32, packed::32, 0::little-64, msg_length::little-64>>
  end

  ## Unsupported methods

  # Guards the regression where an unlisted method became the sentinel `-1` on
  # the wire and the caller waited out its budget for a reply the server could
  # not produce. An error rather than a raise, because `request/3` is
  # contractually non-raising; the raising counterpart belongs to
  # `Endpoint.new/1`, which no DBConnection callback sits behind.
  describe "an unsupported method" do
    test "is refused by name instead of being sent as a sentinel" do
      state = state!()

      assert {:error, %Error{} = error, %Connection{}} =
               VelocyClient.request(%Request{method: :trace, path: "/_api/version"}, [], state)

      assert error.message =~ "trace"
    end

    test "nothing is written to the socket for a method that cannot be sent" do
      state = state!()

      VelocyClient.request(%Request{method: :trace, path: "/_api/version"}, [], state)

      assert wire() == ""
    end
  end

  ## Bodies that cannot be encoded

  # Encoding happens inside `request/3` for this client, on caller-supplied
  # data, so an unencodable term is a caller mistake that must come back as an
  # error rather than killing the connection process — the callback
  # reaches `DBConnection` through `Arangox.Connection`.
  #
  # A pid stands in for any term with no `VelocyPack.Encoder` implementation.
  # `%DateTime{}` does not qualify — velocy 0.1.8+ encodes it (type `0x1c`) —
  # which is why the fixture is a pid.
  describe "a body the codec cannot encode" do
    test "is an error rather than a raise" do
      state = state!()

      request = %Request{
        method: :post,
        path: "/_api/document/c",
        body: %{"p" => self()}
      }

      assert {:error, %Error{} = error, %Connection{}} =
               VelocyClient.request(request, [], state)

      assert is_binary(error.message)
    end

    test "nothing is written to the socket" do
      state = state!()

      request = %Request{
        method: :post,
        path: "/_api/document/c",
        body: %{"p" => self()}
      }

      VelocyClient.request(request, [], state)

      assert wire() == ""
    end
  end

  ## Framing

  # A small chunk size is a legitimate per-pool configuration and the only way
  # to reach the multi-chunk path without a request of tens of kilobytes. These
  # pin the wire format a server has to be able to read.
  describe "framing" do
    test "a message that fits is one chunk, numbered as the total" do
      state = state!()

      VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)

      assert [chunk] = parse_chunks(wire())
      assert chunk.first?
      assert chunk.chunk_n == 1
    end

    # The first chunk carries the chunk *count*; the rest carry their own index
    # from 1. A reader needs both to know how many chunks to wait for.
    test "a message that does not fit is split, and the pieces reassemble" do
      state = state!(vst_maxsize: 30)

      VelocyClient.request(
        %Request{
          method: :post,
          path: "/_api/cursor",
          body: %{"query" => String.duplicate("x", 200)}
        },
        [],
        state
      )

      assert [first | rest] = chunks = parse_chunks(wire())
      assert length(chunks) > 1

      assert first.first?
      assert first.chunk_n == length(chunks)
      refute Enum.any?(rest, & &1.first?)
      assert Enum.map(rest, & &1.chunk_n) == Enum.to_list(1..length(rest))
    end

    # Every chunk declares the same total size, headers included. A reader
    # sizes its buffer from it.
    test "every chunk declares the same message length, headers included" do
      state = state!(vst_maxsize: 30)

      VelocyClient.request(
        %Request{
          method: :post,
          path: "/_api/cursor",
          body: %{"query" => String.duplicate("x", 200)}
        },
        [],
        state
      )

      chunks = parse_chunks(wire())
      payloads = chunks |> Enum.map(& &1.payload) |> IO.iodata_to_binary()

      assert Enum.map(chunks, & &1.msg_length) |> Enum.uniq() == [
               byte_size(payloads) + 24 * length(chunks)
             ]
    end
  end

  ## Database-prefixed paths

  # `request/3`'s rescue reports a raise as a dead socket, so a path shape a
  # caller can legitimately write must never reach it.
  describe "a path naming a database with no trailing segment" do
    test "is sent rather than reported as a transport fault" do
      state = state!()

      assert {:error, %Error{reason: :timeout}, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_db/mydb"}, [], state)

      # The request reached the wire naming the database; the silent listener
      # simply never replied to it.
      assert wire() =~ "mydb"
    end
  end

  ## Send failures

  # Guards the regression where the chunk loop escaped by throwing, which a
  # caller cannot match on. An already-closed socket is the ordinary trigger.
  describe "a send failure" do
    test "is an error tuple rather than a throw" do
      state = state!(vst_maxsize: 30)
      {:gen_tcp, socket} = state.socket
      :ok = :gen_tcp.close(socket)

      assert {:error, %Error{reason: :closed}, %Connection{}} =
               VelocyClient.request(
                 %Request{
                   method: :post,
                   path: "/_api/cursor",
                   body: %{"query" => String.duplicate("x", 200)}
                 },
                 [],
                 state
               )
    end
  end

  ## Malformed and truncated replies

  # `request/3` reaches `DBConnection` through `Arangox.Connection`, so an
  # exception here retires the connection with a message about the driver
  # rather than the server.
  describe "a reply that does not arrive whole" do
    test "a chunk shorter than its header promised is an error" do
      # Claims a 1024-byte chunk, sends 10 bytes of it, then closes.
      reply = chunk_header(1024, 1, 1) <> String.duplicate("x", 10)
      state = replying_state!(reply)

      assert {:error, %Error{} = error, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)

      assert error.reason == :closed
    end

    test "a header that stops mid-way is an error" do
      state = replying_state!(<<0, 0, 0>>)

      assert {:error, %Error{} = error, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)

      assert error.reason == :closed
    end

    # A first chunk announcing that the message has zero chunks is nonsense, but
    # it is nonsense a server could send, and the client reads the count before
    # it can know better. The count drives how many more chunks are read.
    test "a chunk count of zero is an error rather than a crash" do
      state = replying_state!(chunk_header(24, 0, 1))

      assert {:error, %Error{}, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)
    end

    # `recv/3` with length 0 on a raw-mode socket returns whatever bytes are
    # buffered rather than none, so an empty chunk read that way swallows the
    # next chunk's header and desynchronises the stream.
    test "an empty chunk reassembles instead of desynchronising the stream" do
      {:ok, payload} = VelocyPack.encode([1, 2, 200, %{}])
      msg_length = 2 * 24 + byte_size(payload)

      reply =
        chunk_header(24, 2, 1, msg_length) <>
          chunk_header(24 + byte_size(payload), 1, 0, msg_length) <> payload

      state = replying_state!(reply)

      assert {:ok, %Response{status: 200}, %Connection{}} =
               VelocyClient.request(%Request{method: :get, path: "/_api/version"}, [], state)
    end
  end
end
