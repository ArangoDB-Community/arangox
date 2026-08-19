---
title: "Bounding socket writes on the BEAM: the stall was in close, not send"
date: 2026-08-19
category: performance-issues
module: arangox-client
problem_type: performance_issue
component: database
severity: high
symptoms:
  - "A caller with only milliseconds of deadline budget left could still block for about 15 seconds writing to a peer that had accepted the TCP connection but stopped reading from it"
  - "The chunked VelocyStream client could be held roughly 15 seconds per chunk, multiplying the stall across a single request"
  - "An 8 MB :gen_tcp.send to a silent peer returned :ok in about 0 ms instead of blocking, so the connect-time 15-second send_timeout never had a chance to fire"
  - "Through Mint the same scenario stalled about 5.2 seconds even though a raw :gen_tcp.recv honored its timeout exactly, because Mint's error handling closes the socket and a close with unsent bytes queued toward a dead peer blocks in the driver's close-flush wait"
root_cause: config_error
resolution_type: code_fix
related_components:
  - testing_framework
tags: [gen-tcp, mint, velocystream, gun, socket-options, send-timeout, high-watermark, deadline]
---

# Bounding socket writes on the BEAM: the stall was in close, not send

## Problem

Every request in this driver carries an absolute deadline, but only socket receives were derived from the remaining budget — socket writes were bounded by a fixed 15-second `send_timeout` set once at connect. A caller with milliseconds of budget left could be held about 15 seconds writing to a peer that accepted the connection but stopped reading, and the chunked VelocyStream (ArangoDB's binary protocol) client could be held 15 seconds per chunk, so an N-chunk message could cost N times 15 seconds.

## Symptoms

The observable failures, measured on macOS with OTP (Open Telecom Platform, the Erlang runtime) 28:

- An 8 MB `:gen_tcp.send/2` to a silent peer — one that accepts the connection and never reads — returned `:ok` in roughly 0 ms. The inet driver (the C driver inside the Erlang virtual machine that owns TCP sockets) accepted the entire oversized write into its internal queue in a single port command. The send never blocked, so the `send_timeout` timer never ran at all.
- A raw `:gen_tcp.recv/3` against the same silent peer then honored its 250 ms timeout exactly.
- The same scenario driven through Mint (the driver's default HTTP client library) stalled the caller for about 5.2 seconds — far past both the request budget and the receive timeout.
- Through the VelocyStream client, a multi-chunk write to a peer that stopped reading could hold the caller for the fixed 15-second bound once per chunk.

The 5.2-second figure was the tell: it did not match the request budget (300 ms in the reproduction), the receive timeout, or the 15-second send bound. It matched the Erlang virtual machine's multi-second close-flush wait — the time a closing process spends waiting for the inet driver to flush queued bytes toward a peer that will never read them. Even 1 KB of queued data costs the full wait.

## What Didn't Work

The fixed 15-second bound did not enter the code by accident. An earlier fix round had already established that no client bounded socket writes at all — Gun applies its own `{send_timeout, 15000}` default only when the caller passes no `tcp_opts`, and this driver always passed the key, silently suppressing it, while Mint and VelocyStream configured nothing. That round restored a fixed 15-second bound, verified it only by asserting the option value reaches the transport configuration (not by simulating a peer that stops reading), and explicitly deferred deadline-aware writes as too large to rush. The fixed bound was a known stopgap; what nobody knew was that it was also inert. (session history)

The investigation then proceeded from the assumption that the stall lived in the send, and each probe eliminated part of that assumption:

1. **A per-request `send_timeout` alone, applied through Mint.** The red test still failed at exactly 5.2 seconds. The reason only became clear later: the send never blocked in the first place (the inet driver had swallowed the whole payload into its queue), so no send timer — fixed or budget-derived — ever had a chance to fire. The stall was somewhere else entirely.

2. **Bisecting the stack to locate the stall.** Three runs against the same silent listener: (a) raw `:gen_tcp` send plus raw `:gen_tcp` recv — both timings honest; (b) Mint connect and Mint request, then a raw `:gen_tcp.recv/3` on the underlying socket — still honest; (c) Mint connect, Mint request, and Mint's own `recv` — 5.2 seconds. The delta between (b) and (c) is Mint's receive error path. When a transport operation fails, Mint closes the socket inside its own error handling — `handle_transport_error/2` calls `conn.transport.close(conn.socket)` (deps/mint/lib/mint/http1.ex:554-557) — and closing a socket that still has unsent bytes queued toward a dead peer blocks the closing process for the full close-flush wait. The library's cleanup, not the driver's send, was charging the caller.

3. **A `high_watermark` on a raw socket, without touching close behavior.** Setting a queue watermark made the raw-socket timings honest, because the send could now block and the timeout could run. But through Mint the 5.2-second stall remained: the timed-out request still left bytes in the driver queue, Mint still closed the socket on the error path, and the close still flushed. The stall only disappeared once close became an abort.

## Solution

The fix is three socket options that work as a set, plus re-deriving the send bound from the remaining budget at each write. In the Mint client, the connect-time defaults (lib/arangox/client/mint.ex:106-111):

```elixir
@default_send_opts [
  send_timeout: 15_000,
  send_timeout_close: true,
  high_watermark: 65_536,
  linger: {true, 0}
]
```

These are merged into Mint's `transport_opts` at connect, under the caller's own options (lib/arangox/client/mint.ex:126). Then `request/3` checks the budget before writing anything — an already-elapsed deadline gets a distinct "before the request was sent" error rather than the receive-phase wording (lib/arangox/client/mint.ex:204-209, 337-342) — and replaces the fixed send bound with the remaining budget (lib/arangox/client/mint.ex:211-218):

```elixir
{:ok, remaining} ->
  # The write half of the deadline: `Mint.request/5` performs the socket write
  # synchronously, and a write blocks while the peer's receive window
  # is full — before the deadline-bounded receive loop ever runs. The
  # send bound is therefore the remaining budget, set per request; the
  # connect-time `send_timeout` covers only writes made before the
  # first request.
  _ = set_send_timeout(Mint.get_socket(socket), remaining)
```

with `set_send_timeout/2` dispatching on the socket type (lib/arangox/client/mint.ex:286-290): `:inet.setopts/2` when `is_port/1` holds, `:ssl.setopts/2` otherwise.

The VelocyStream client carries the send timeout, the close-on-expiry flag, and the zero linger (lib/arangox/client/velocy.ex:172-175) — but no explicit `high_watermark`, and the omission is load-bearing rather than an oversight. Its writes are already chunked into bounded port commands (one per protocol chunk), and a stream of moderate commands blocks at the driver's own default watermark once the queue fills; the pre-fix behavior proved it, with the caller blocking the full 15 seconds per chunk. The single oversized port command — Mint handing a whole body to one send — is the shape that sails past the default watermark and needs the explicit one. VelocyStream re-derives the budget once per chunk, because a fixed bound would be paid once per chunk of an N-chunk stream (lib/arangox/client/velocy.ex:500-520):

```elixir
defp send_stream({mod, port}, chunks, deadline, opts, state) do
  Enum.reduce_while(chunks, :ok, fn chunk, :ok ->
    case Client.socket_timeout(deadline, opts, state) do
      :elapsed ->
        {:halt,
         {:error,
          %Error{
            reason: :timeout,
            message: "the request timeout elapsed before the request was fully sent"
          }}}

      {:ok, remaining} ->
        _ = set_send_timeout(mod, port, remaining)

        case mod.send(port, chunk) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end
  end)
end
```

The Gun client is deliberately exempt from per-request send bounds. Gun writes from its own process, so a caller can never block inside a socket send, and every wait the caller does perform is already bounded by the request deadline (lib/arangox/client/gun.ex:63-69, and the moduledoc at lib/arangox/client/gun.ex:25-30 documents the asymmetry). Its socket still carries the full option set for teardown hygiene (lib/arangox/client/gun.ex:70-75), and the merge is done carefully: Gun applies its own `{send_timeout, 15000}` default only when `:tcp_opts` is absent from its options map, and this driver always passes the key, so the bounds are merged under the caller's list rather than relied on as Gun's default (lib/arangox/client/gun.ex:88-94).

## Why This Works

Three inet-driver behaviors interact here, and no single option fixes the problem alone:

1. **An unbounded single write means the send never blocks.** The inet driver accepts an arbitrarily large write into its internal queue in one port command and returns `:ok` immediately — 8 MB in roughly 0 ms in the reproduction. `send_timeout` only bounds a *blocked* send, so for a single-command writer the timer is dead code without a queue bound. `high_watermark: 65_536` caps the queue at 64 KiB; once the queue is over the watermark, the next send blocks, and only then can any timeout apply. A writer that issues many smaller commands — VelocyStream's chunked stream — blocks at the driver's default watermark instead, which is why it needs no explicit one; the watermark option exists for the single-blob shape.

2. **A fixed send bound is wrong for a deadline-based driver.** Once the send can block, `send_timeout` bounds it — but a fixed 15-second value ignores the caller's actual remaining budget, and a chunked writer pays it per chunk. Re-deriving the bound from the deadline via `setopts` immediately before each write makes the block bounded by what the caller has left, not by a constant chosen at connect. `send_timeout_close: true` additionally closes the socket on expiry, so a half-written request can never be misread as the start of the next one.

3. **Close flushes, and libraries close inside their error paths.** Closing a socket that still has queued unsent bytes blocks the closing process until the driver gives up flushing them — a multi-second wait (about 5 seconds observed), paid even for 1 KB of queued data. Mint closes the socket inside its own transport-error handling (deps/mint/lib/mint/http1.ex:554-557), so precisely the caller whose budget just expired — the one whose timed-out write left bytes in the queue — is the one held for the flush. `linger: {true, 0}` (zero-timeout `SO_LINGER`) turns every close into an abort: the queue is discarded, the peer sees a connection reset, and the closing process returns immediately. The abort is safe in this driver because it only ever closes sockets it is retiring — there is no graceful half-close that any peer legitimately waits on.

The general lesson: on the Erlang virtual machine, "bound the socket write" decomposes into a watermark (makes blocking possible), a budget-derived `send_timeout` (makes the block bounded), and abort-on-close linger (makes teardown not re-pay the wait) — and the caller-visible stall may live in *close*, not send, because the flush wait lands on whichever process happens to run the library's cleanup.

## Prevention

The `"socket write bounds"` describe block in test/arangox/protocol_test.exs:1053-1168 pins the behavior. Its scenario is `silent_listener!/0` (test/arangox/protocol_test.exs:125-143), a local TCP listener that accepts and then sleeps forever, combined with an 8 MB body, a 300 ms request budget, and a deliberately small 16 KiB `sndbuf` so the write blocks almost immediately. Each client's caller must return in under 5 seconds — generous for a loaded scheduler, but strictly below both the 5.2-second close-flush stall and the 15-second connect-time bound that the bug produced (test/arangox/protocol_test.exs:1121-1143 for Mint, 1145-1167 for VelocyStream). The Gun test at test/arangox/protocol_test.exs:1096-1113 pins the exemption itself: it proves a Gun caller escapes the same silent peer within its budget with no per-request send bound, which is what makes the exemption a verified fact rather than an assumption. Two further tests pin the option-merging hazard — an unrelated `tcp_opts` entry must not strip the send bound, and a caller's own `send_timeout` must win (test/arangox/protocol_test.exs:1054-1076). The `"a budget spent before the write"` block (test/arangox/protocol_test.exs:1170-1206) pins the pre-send error wording, so an elapsed-before-send failure never claims a response was in flight.

Anyone adding a transport client should answer one question first: does the caller's process ever execute the socket write? If yes (Mint and VelocyStream both write synchronously in the caller), the client needs the send timeout, close-on-expiry, and zero linger at connect, plus a budget-derived `setopts` before every write — and the explicit `high_watermark` too if the client hands the transport whole bodies in one command, since that is the shape whose send otherwise never blocks. A chunked writer blocks at the driver's default watermark on its own, as VelocyStream does. If no (Gun writes from its own connection process), per-request send bounds do not apply, but the socket should still carry the watermark and the zero linger so the writing process is protected and retirement never pays the flush wait. In either case, verify how the underlying library treats your `tcp_opts`: Gun silently drops its own send-timeout default the moment the key is present, and any library may close the socket inside its error handling — which is exactly where an unlingered close would hand your caller a multi-second bill.

A deeper rework remains deferred: truly streaming writes in flow-control-window-sized pieces under the deadline (interleaving writes with window updates) is a read/write state machine, not a socket-option change, and belongs to the planned transport rework rather than a fix round. (session history)

## Related Issues

- [dbconnection-timeout-is-a-deadline-not-a-duration.md](../architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md) — the receive-side half of the same guarantee: every socket wait derives from the caller's remaining budget, and a timed-out connection is retired, never returned. This doc is the write/close-side half that the receive-only fix left open.
- [transport-tls-defaults-are-not-the-drivers-to-supply.md](../architecture-patterns/transport-tls-defaults-are-not-the-drivers-to-supply.md) — the same client modules and the same lesson family: locally coherent transport code that was wrong about what the dependency or runtime actually does.
