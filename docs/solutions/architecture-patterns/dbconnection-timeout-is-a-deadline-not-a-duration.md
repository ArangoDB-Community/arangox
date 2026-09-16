---
title: "DBConnection's :timeout is a deadline, not a duration you can reuse downstream"
date: 2026-08-07
category: architecture-patterns
module: arangox-connection
problem_type: architecture_pattern
component: database
severity: high
applies_when:
  - Adding a socket-level or request-level timeout to a DBConnection-based driver
  - Deriving any wait inside handle_execute, handle_declare, handle_fetch, or a client callback
  - Reviewing a timeout design that compares two durations to pick the smaller one
  - Reviewing a design for reasoning errors rather than internal consistency
tags: [db-connection, timeout, deadline, connection-pool, elixir, checkout, adversarial-review]
---

# DBConnection's :timeout is a deadline, not a duration you can reuse downstream

## Context

While planning arangox 1.0 we needed a request timeout: no client should wait on a socket forever. The obvious design was to resolve a pool-level `:request_timeout`, compare it against the caller's `:timeout`, take the lower of the two, subtract a small margin, and use that as the socket receive timeout.

That design is wrong, and it is wrong in a way that survives review. It is locally coherent — the arithmetic is defensible, the code looks defensive, and it behaves correctly under every test that does not saturate the pool. It survived an architecture review, a feasibility review, a cross-model whole-document sweep by a different model family, and two re-reads by the author. (session history)

The feasibility pass came closest without arriving. It observed that the design could not work as a static default "because DBConnection reads the checkout deadline from *each caller's* option list" — correctly identifying that the caller's value is per-call and variable, but not going on to ask when that value started counting. (session history)

The failure the design produces is not "the timeout is slightly off." It is the exact failure the timeout was introduced to prevent.

## Guidance

**Treat the caller's `:timeout` as a duration that started counting when the caller asked for a connection, not when your code got one.** Capture an absolute deadline at entry and derive every downstream wait from the *remaining* budget.

DBConnection already does this internally. `Holder.checkout/3` takes a monotonic reading and immediately converts the caller's duration into an absolute instant:

```elixir
# deps/db_connection/lib/db_connection/holder.ex:66-69
def checkout(pool, callers, opts) do
  queue? = Keyword.get(opts, :queue, @queue)
  now = System.monotonic_time(@time_unit)
  timeout = abs_timeout(now, opts)
```

```elixir
# deps/db_connection/lib/db_connection/holder.ex:441-446
defp abs_timeout(now, opts) do
  case Keyword.get(opts, :timeout, @timeout) do
    :infinity -> Keyword.get(opts, :deadline)
    timeout -> min(now + timeout, Keyword.get(opts, :deadline))
  end
end
```

`@timeout` is `15000` (`holder.ex:8`) and `@time_unit` is `1000`, so the budget is in milliseconds (`holder.ex:9`). The resulting instant arms an **absolute** timer (`abs: true`), not a relative one:

```elixir
# deps/db_connection/lib/db_connection/holder.ex:452-457
defp start_deadline(timeout, pid, ref, holder, start) do
  deadline =
    :erlang.start_timer(timeout, pid, {ref, holder, self(), timeout - start}, abs: true)

  {deadline, [{conn(:deadline) + 1, deadline}]}
end
```

The trap is that **`opts` is never rewritten**. The same keyword list that produced the absolute deadline — still carrying the original *duration* under `:timeout` — is threaded unchanged all the way to your `handle_execute/4`. The full path, with the same `opts` binding at every hop:

- `DBConnection.execute/4` calls `run(conn, &run_execute(&1, query, params, &2, &3), meter, opts)` (`db_connection.ex:859-867`).
- `run/4` delegates to `run_with_retries/5` (`db_connection.ex:1597-1600`).
- `run_with_retries/5` calls `checkout(pool, meter, opts)` and then, on a later line of the same function body, `fun.(conn, meter, opts)` — the identical binding, unmodified in between (`db_connection.ex:1602-1609`).
- `checkout/3` passes it straight to the pool: `pool_mod.checkout(pool, callers, opts)` (`db_connection.ex:1346-1354`), which is where `abs_timeout/2` converts it above.
- `run_execute/5` calls `Holder.handle(pool_ref, :handle_execute, [query, params], opts)` (`db_connection.ex:1554-1558`).
- `Holder.handle/4` (`holder.ex:135-137`) delegates to `handle_or_cleanup/5`, which reads the module and state from ETS and appends `opts` to the argument list: `holder_apply(holder, module, fun, args ++ [opts, state])` (`holder.ex:165-166`).
- `holder_apply/4` is a bare `apply(module, fun, args)` (`holder.ex:377-379`).

Nothing on that path replaces `:timeout` with a remainder. Reading `opts[:timeout]` inside `handle_execute/4` and using it as a socket timeout restarts a clock that has already been running — possibly for most of its budget.

The correct shape:

```elixir
# At entry, before checkout can consume budget. The deadline is derived from
# the caller's own budget — not from the pool's option, which is a separate
# and possibly larger number:
deadline = System.monotonic_time(:millisecond) + caller_budget

# At the socket, however much later. The pool's own timeout is a ceiling on
# the derived wait, not a replacement for it:
remaining = deadline - System.monotonic_time(:millisecond)
socket_timeout = min(remaining - @margin, resolved_request_timeout)

if socket_timeout >= @minimum do
  do_receive(socket, socket_timeout)
else
  {:error, already_elapsed_error()}   # fail fast, do not start a doomed request
end
```

Getting the first line wrong is the same bug in a new costume: seeding the deadline from the pool's configured timeout rather than from the caller's budget makes the `min` redundant and restores the original overrun. The pool option can only ever tighten the caller's bound, never extend it.

Two rules fall out of it:

1. **A remainder below the usable minimum fails fast.** If the deadline has passed, or is so close that no request could finish inside it, issuing the request is wasted work whose response nobody will read.
2. **A timeout must disconnect, not return the connection.** See "Why This Matters."

## Why This Matters

The deadline timer's target process is the **pool**, not the caller. `checkout_call/5` runs in the caller, receives the ETS holder transfer, and arms the timer against the `pool` pid it just learned from that message:

```elixir
# deps/db_connection/lib/db_connection/holder.ex:316-318
{:"ETS-TRANSFER", holder, pool, {^lock, ref, checkin_time}} ->
  Process.demonitor(lock, [:flush])
  {deadline, ops} = start_deadline(timeout, pool, ref, holder, start)
```

DBConnection's `handle_*` callbacks, by contrast, run in the **caller's** process, not the connection process. The pool gives the ETS holder away to the caller pid (`holder.ex:211-212`, `:ets.give_away(holder, pid, ...)`); the caller then reads the connection module and state out of that table and applies them itself (`holder.ex:144-167`, ending in the `holder_apply/4` call at `:165-166`; the bare `apply/3` is at `:377-379`). The same read happens at checkout to hand the caller its initial state (`holder.ex:335-346`). The source labels the boundary directly: `## Pool API (invoked by caller)` at `holder.ex:61` versus `## Pool callbacks (invoked by pools)` at `holder.ex:196`. So the caller is the process actually blocked in `:gen_tcp.recv/3` or `Mint.recv/3`.

Put those two facts together and the duration-based design fails like this:

1. A caller with a 15-second budget waits 14 seconds for a free connection in a saturated pool.
2. Your `handle_execute/4` reads `opts[:timeout]` — still `15_000` — and sets a ~15-second socket wait.
3. One second later DBConnection's absolute deadline fires **on the pool process**. The pool's `handle_info({:timeout, deadline, ...})` clause builds a `ConnectionError` and calls `Holder.handle_disconnect(holder, exc)` (`deps/db_connection/lib/db_connection/connection_pool.ex:188-208`). It tears the connection down. It sends nothing to the caller pid — the caller's pid appears only inside the error message text.
4. The caller is still sitting in `recv`. Nothing unblocked it. It is now waiting on a socket belonging to a connection that no longer exists, for up to another 14 seconds.

The user asked for a 15-second bound and got roughly 29 seconds, an opaque error, and a destroyed connection. A timeout designed to prevent an unbounded wait created a longer one.

There is a second reason a timed-out request must **disconnect** rather than return its connection to the pool: on HTTP/1.1 a timeout mid-response leaves unread bytes in the socket and an open request reference. If that connection goes back into the pool, the next checkout — possibly a different caller, a different tenant, a different database — issues its request and reads the *previous* response's remaining bytes. That is a cross-checkout confidentiality leak, not merely corruption.

These two rules have independent origins and both are required. The disconnect rule came out of the architecture review, which found that normalizing client errors into a uniform shape erased the signal DBConnection needs to force a disconnect; the deadline rule came out of a later adversarial pass. (session history) A correct deadline with a normalized error still leaks, and a disconnect-on-timeout with a duration-derived bound still overruns. Neither rule substitutes for the other.

## When to Apply

- Any driver built on `db_connection` that adds a wait the library does not already bound.
- Any review of a timeout design whose derivation compares two durations. Ask directly: *when did each clock start?*
- Any code reading `opts[:timeout]` somewhere other than the checkout boundary.
- Protocols where the driver cannot tell where a response ends. There the disconnect-on-timeout rule is what prevents the leak above, not a tidiness measure.

## Examples

**Before — wrong, and the wrongness is invisible in the common case:**

```elixir
# Looks defensive. Passes every test that does not saturate the pool.
timeout = min(state.request_timeout, Keyword.get(opts, :timeout, 15_000)) - @margin
Mint.recv(conn, 0, timeout)
```

Under an idle pool, checkout is instant, the durations effectively agree, and this behaves correctly. It only fails under contention — which is exactly when timeouts matter and exactly when tests usually are not looking.

**The test that catches it:** a saturated pool plus a short caller deadline. Assert the driver's own timeout error arrives *before* DBConnection's deadline error. A duration-based derivation fails this and passes everything else, which is why the scenario has to be written deliberately rather than discovered.

**The reviewing lesson.** A design can be locally coherent and globally wrong. Each pass that missed this one was checking something real: coherence checks internal consistency, feasibility checks whether the code can do what the plan says, security checks the threat surface. None of them asks whether the reasoning holds. The pass that caught it asked a different question — not whether the derivation was defensible, but what instant each of its terms was measured from. (session history)

## Related

- Implementation lives in unit U9 ("Request timeouts") of `docs/plans/2026-08-06-001-feat-arangox-1-0-modernization-plan.md`. The governing decision is KTD5 and the requirement is R17; U9 lists R17 as its sole requirement and depends on U2 and U17. KTD5 is also the source of the `:request_timeout` name, chosen specifically to avoid colliding with DBConnection's own `:timeout` key in the same keyword list.
- The observable proof of the disconnect corollary is acceptance evidence AE5 in the same plan: a server that accepts a request and never responds must produce a caller error within the request timeout, tear down the connection, and serve the next request from a fresh connection.
- The disconnect itself is produced at the error-classification seam defined by KTD6, whose "socket gone" reason class maps to `{:disconnect, ...}`. A timeout that does not reach that class does not disconnect.
- The plan's risk table names both failure modes in one line each: "A timed-out connection returned to the pool delivers the previous response's bytes to the next caller" and "A timeout budget measured as a duration rather than a deadline lets a queued caller outlive its own deadline — the failure KTD5 exists to prevent."
- Verified against db_connection 2.10.2 (`mix.lock`; `deps/db_connection/mix.exs` `@version`). Line numbers are into the dependency (`deps/db_connection/`), which is present in this checkout but not in every clone — re-locate by function name (`abs_timeout/2`, `start_deadline/5`, `handle_or_cleanup/5`, `holder_apply/4`, `run_with_retries/5`) if they drift.
</content>
