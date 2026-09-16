defmodule Arangox.DeadlineTest do
  @moduledoc """
  Which deadline reaches which request.

  Unit tier: no sockets. The property under test is entirely option plumbing —
  `Arangox.run/3` and `Arangox.transaction/3` publish the block's deadline in
  the process dictionary, and the question is which requests are entitled to
  read it — so the assertion is on the `:deadline` a client is handed, which
  `Arangox.Client` documents as part of its contract.

  A request issued from inside a block on pool A to an *unrelated* pool B is
  legitimate code (a read replica, a second tenant, an audit write). It must
  get the budget it asked for, not what is left of pool A's block. Requests the
  block really does own — including the ones arangox never sees the options of,
  a cursor's per-batch fetches above all — must still be bounded by it.
  """

  use ExUnit.Case, async: true

  import TestHelper, only: [stop_pool: 1]

  alias Arangox.Response

  @block_timeout 1_000
  @pool_b_request_timeout 12_000

  defmodule RecordingClient do
    @moduledoc false
    @behaviour Arangox.Client

    alias Arangox.{Connection, Request, Response}

    @impl true
    def connect(_endpoint, opts) do
      client_opts = Keyword.fetch!(opts, :client_opts)

      {:ok,
       %{owner: Keyword.fetch!(client_opts, :recorder), tag: Keyword.fetch!(client_opts, :tag)}}
    end

    @impl true
    def request(%Request{method: method, path: path}, opts, %Connection{socket: socket} = state) do
      send(socket.owner, {:recorded, socket.tag, method, path, Keyword.get(opts, :deadline)})

      {:ok, reply(method, path), state}
    end

    @impl true
    def close(%Connection{}), do: :ok

    # Enough of the transaction protocol for `Arangox.transaction/3` to begin
    # and commit; anything else makes `DBConnection` retire the connection and
    # the pool reconnects in a loop.
    defp reply(:post, "/_api/transaction/begin"),
      do: %Response{
        status: 201,
        headers: [],
        body: ~s({"result":{"id":"3298558923352","status":"running"},"error":false,"code":201})
      }

    defp reply(:put, "/_api/transaction/3298558923352"),
      do: %Response{
        status: 200,
        headers: [],
        body: ~s({"result":{"id":"3298558923352","status":"committed"},"error":false,"code":200})
      }

    # Enough of the cursor protocol for one two-batch stream: the declare
    # reports `hasMore`, so `handle_fetch/4` makes a second request.
    defp reply(:post, "/_api/cursor"),
      do: %Response{
        status: 201,
        headers: [],
        body: ~s({"id":"c1","hasMore":true,"result":[1],"error":false,"code":201})
      }

    defp reply(:put, "/_api/cursor/c1"),
      do: %Response{
        status: 200,
        headers: [],
        body: ~s({"hasMore":false,"result":[2],"error":false,"code":200})
      }

    defp reply(_method, _path),
      do: %Response{status: 200, headers: [], body: ~s({"error":false,"code":200})}
  end

  setup do
    pool_a = start_pool!(:a, [])
    pool_b = start_pool!(:b, request_timeout: @pool_b_request_timeout)

    # Connect probes record too. Warm both pools, then drop everything recorded
    # so far, so each test's `assert_receive` sees only its own requests.
    assert {:ok, %Response{}} = Arangox.get(pool_a, "/warm")
    assert {:ok, %Response{}} = Arangox.get(pool_b, "/warm")
    flush()

    %{pool_a: pool_a, pool_b: pool_b}
  end

  defp start_pool!(tag, opts) do
    {:ok, pool} =
      Arangox.start_link(
        [
          endpoints: ["http://#{tag}.invalid:8529"],
          client: RecordingClient,
          pool_size: 1,
          client_opts: [recorder: self(), tag: tag]
        ] ++ opts
      )

    on_exit(fn -> stop_pool(pool) end)

    pool
  end

  defp flush do
    receive do
      {:recorded, _tag, _method, _path, _deadline} -> flush()
    after
      0 -> :ok
    end
  end

  describe "a block's deadline" do
    test "bounds a request on the block's own connection", %{pool_a: pool_a} do
      now = System.monotonic_time(:millisecond)

      Arangox.run(
        pool_a,
        fn conn -> assert {:ok, %Response{}} = Arangox.get(conn, "/on-a") end,
        timeout: @block_timeout
      )

      assert_receive {:recorded, :a, :get, "/on-a", deadline}
      assert_in_delta deadline, now + @block_timeout, 100
    end

    test "does not bound a request to another pool", %{pool_a: pool_a, pool_b: pool_b} do
      now = System.monotonic_time(:millisecond)

      Arangox.run(
        pool_a,
        fn conn ->
          assert {:ok, %Response{}} = Arangox.get(conn, "/on-a")
          assert {:ok, %Response{}} = Arangox.get(pool_b, "/on-b")
        end,
        timeout: @block_timeout
      )

      assert_receive {:recorded, :a, :get, "/on-a", own}
      assert_receive {:recorded, :b, :get, "/on-b", foreign}

      assert_in_delta own, now + @block_timeout, 100

      # The second pool asked for nothing, so it gets `DBConnection`'s default
      # 15s, not the ~1s left of a block it has no part in.
      assert foreign - own > 10_000,
             "the request to the other pool inherited the block's deadline " <>
               "(#{foreign - own}ms apart)"
    end

    test "does not bound a request to another pool that asked for no deadline",
         %{pool_a: pool_a, pool_b: pool_b} do
      now = System.monotonic_time(:millisecond)

      Arangox.run(
        pool_a,
        fn _conn ->
          assert {:ok, %Response{}} = Arangox.get(pool_b, "/on-b", [], timeout: :infinity)
        end,
        timeout: @block_timeout
      )

      assert_receive {:recorded, :b, :get, "/on-b", deadline}

      # `timeout: :infinity` leaves no caller deadline to inherit, so the second
      # pool's own `:request_timeout` is what bounds it — not the first pool's
      # block.
      assert_in_delta deadline, now + @pool_b_request_timeout, 200
    end

    test "bounds a transaction's requests", %{pool_a: pool_a, pool_b: pool_b} do
      now = System.monotonic_time(:millisecond)

      Arangox.transaction(
        pool_a,
        fn conn ->
          assert {:ok, %Response{}} = Arangox.get(conn, "/on-a")
          assert {:ok, %Response{}} = Arangox.get(pool_b, "/on-b")
        end,
        timeout: @block_timeout
      )

      assert_receive {:recorded, :a, :get, "/on-a", own}
      assert_receive {:recorded, :b, :get, "/on-b", foreign}

      assert_in_delta own, now + @block_timeout, 100
      assert foreign - own > 10_000
    end
  end

  describe "a query's deadline" do
    # `query/4` is a direct execute from the caller, like `get/4` and
    # `request/6`, so it has to stamp the deadline in the caller's process
    # before checkout can spend any of it. A cursor deliberately does
    # not: it runs inside a block that already published one.
    test "query/4 stamps the caller's budget", %{pool_a: pool_a} do
      now = System.monotonic_time(:millisecond)

      assert {:ok, %Response{}} =
               Arangox.query(pool_a, "RETURN 1..2", %{}, timeout: @block_timeout)

      assert_receive {:recorded, :a, :post, "/_api/cursor", declare}
      assert_in_delta declare, now + @block_timeout, 100
    end

    # The drain is the caller's own request continued, not a new one. Batches
    # that restarted the clock would let a query outlive the budget it asked
    # for by however many batches the server chose to split the result into.
    test "the batches a drain fetches share that same instant", %{pool_a: pool_a} do
      assert {:ok, %Response{}} =
               Arangox.query(pool_a, "RETURN 1..2", %{}, timeout: @block_timeout)

      assert_receive {:recorded, :a, :post, "/_api/cursor", declare}
      assert_receive {:recorded, :a, :put, "/_api/cursor/c1", drain}

      assert declare == drain
    end
  end

  describe "a cursor inside a block" do
    test "has its batch fetches bounded by the block", %{pool_a: pool_a} do
      now = System.monotonic_time(:millisecond)

      # `Arangox.cursor/4` delegates straight to `DBConnection.stream/4`, and
      # `handle_fetch/4` is invoked by `DBConnection` with the stream's own
      # option list — arangox has no stamping point on that path, so the
      # process-dictionary carrier is the only thing that can bound it. This is
      # the case the carrier exists for.
      assert [1, 2] =
               Arangox.run(
                 pool_a,
                 fn conn ->
                   conn |> Arangox.cursor("RETURN 1") |> Enum.flat_map(& &1.body["result"])
                 end,
                 timeout: @block_timeout
               )

      assert_receive {:recorded, :a, :post, "/_api/cursor", declare}
      assert_receive {:recorded, :a, :put, "/_api/cursor/c1", fetch}

      assert_in_delta declare, now + @block_timeout, 100
      assert_in_delta fetch, now + @block_timeout, 100
    end

    test "streamed from another pool gets that pool's block deadline",
         %{pool_a: pool_a, pool_b: pool_b} do
      now = System.monotonic_time(:millisecond)
      inner_timeout = 5_000

      # A cursor on pool B can only be opened inside a block on pool B, and
      # `in_block/2`'s save-and-restore makes the innermost block's deadline the
      # live one.
      assert [1, 2] =
               Arangox.run(
                 pool_a,
                 fn _conn ->
                   Arangox.run(
                     pool_b,
                     fn conn ->
                       conn |> Arangox.cursor("RETURN 1") |> Enum.flat_map(& &1.body["result"])
                     end,
                     timeout: inner_timeout
                   )
                 end,
                 timeout: @block_timeout
               )

      assert_receive {:recorded, :b, :post, "/_api/cursor", declare}
      assert_receive {:recorded, :b, :put, "/_api/cursor/c1", fetch}

      assert_in_delta declare, now + inner_timeout, 150
      assert_in_delta fetch, now + inner_timeout, 150
    end
  end
end
