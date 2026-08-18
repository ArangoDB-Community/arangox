---
title: "Popping the transaction id before the server acknowledges the commit orphans the server-side transaction"
date: 2026-08-08
category: logic-errors
module: arangox-connection
problem_type: logic_error
component: database
severity: high
symptoms:
  - "After a failed commit, DBConnection's automatic rollback finds no transaction id, reports the connection idle, and sends no abort request"
  - "Server-side stream transactions stay alive after a failed commit, holding locks until the server-side TTL expires"
  - "`handle_status/2` treats any HTTP 200 as an active transaction even though the server answers 200 for committed and aborted transactions too"
root_cause: logic_error
resolution_type: code_fix
related_components:
  - testing_framework
tags: [transactions, dbconnection, handle-commit, handle-rollback, state-ordering, stream-transactions, trx-id, elixir]
---

# Popping the transaction id before the server acknowledges the commit orphans the server-side transaction

## Problem

> Citation note: `v0.7.0:path` and `6d58599:path` are `git show` references to historical states (the released 0.7.0 tag and the fix's parent commit). As of this writing the branch is unpublished, so `6d58599` and `da559e7` are branch-local SHAs that a squash or rebase merge may rewrite — if they no longer resolve, locate the fix by its commit subject, "refactor(transactions)!: rewrite the four transaction callbacks".

Shipped arangox 0.7 popped the transaction identifier from connection state before issuing the terminal commit or abort request. In `handle_commit/2` (historical, `v0.7.0:lib/arangox/connection.ex:313-323`; identical at the fix's parent, `6d58599:lib/arangox/connection.ex:921-931`), `Map.pop(state.headers, @header_trx_id)` produced `{id, headers}` and the request went out with `%{state | headers: headers}` — the stripped state. Every failure clause of the `with` returned that stripped state. `handle_rollback/2` had the same shape.

The consequence plays out one layer up. DBConnection (Elixir's pooled database connection behaviour) responds to `{:error, state}` from `handle_commit` by immediately invoking `handle_rollback` on the same connection (`deps/db_connection/lib/db_connection.ex:1901-1903`, db_connection 2.10.2, `run_commit/3`). But the failed commit had already erased the identifier, so the rollback matched the no-transaction clause — `{nil, _headers} -> {:idle, state}` (`6d58599:lib/arangox/connection.ex:963-964`) — and returned without issuing any request. DBConnection then retired the connection, so the caller saw an error either way; the damage was entirely server-side. The ArangoDB stream transaction the commit had failed to end stayed alive, holding its collection locks, until the server's transaction TTL (time to live) expired it.

The same commit fixed a second defect in `handle_status/2`: it matched only on HTTP 200 and reported `:transaction`. ArangoDB answers `GET /_api/transaction/{id}` with 200 for any transaction it still remembers, including committed and aborted ones — the actual state is in the body (demonstrated against the live 3.12 cluster by the integration test starting at `test/arangox/transaction_test.exs:995`, where a finished transaction the server still answers for reads back `:committed` (the assertion is at `:1026`)). So `Arangox.status/1` claimed a transaction was running when it no longer was.

## Symptoms

- A commit the server refused (write-write conflict, disallowed operation, any non-200) left the server-side transaction alive until its TTL, holding its locks. Later writes to the same collections blocked or timed out for no visible reason.
- The recovery path produced no error of its own: the follow-up rollback reported `:idle`, which DBConnection treats as a status answer, not a failure. Nothing logged pointed at the orphaned transaction.
- `Arangox.status/1` reported `:transaction` for transactions the server had already committed or aborted.

## What Didn't Work

- **The pop-then-request shape itself.** Popping the identifier as the first step of the `with` looks like tidy bookkeeping — the transaction is ending, so remove it — but it commits the local state to an outcome the server has not yet confirmed. Restructuring inside that shape (e.g. re-inserting the header in each error clause) would have meant duplicating the restoration across three callbacks' error clauses; the callbacks already duplicated each other, which is how the asymmetry went unnoticed.
- **Answering `handle_status` from local state.** Considered as Q2 in the plan and rejected: the transaction is server-side state, and a local answer lies in both directions — the server aborts transactions on its own (TTL, failover), and a transaction can be finished through another handle. The cost concern doesn't bite because DBConnection's pool-management status calls hit the no-transaction function head, which answers locally with no request.
- **Trusting the HTTP status code as the answer.** The 200 on `GET /_api/transaction/{id}` means "I remember this transaction," not "it is running." Only the body's `result.status` distinguishes running from committed from aborted.

## Solution

Commit `da559e7` ("refactor(transactions)!: rewrite the four transaction callbacks", on branch `feat/v1-0-modernization`) rewrote the callbacks around one rule: the transaction identifier leaves connection state only when the server acknowledges the terminal request.

- Status, commit, and rollback share one parameterized request path, `trx_request/6` (`lib/arangox/connection.ex:971-987`). It builds the outgoing request state — stripping the header from the wire request for commit/abort, keeping it for the status probe — and pattern-matches the outcome. Only an acknowledged 200 reaches the success continuation, which is where the header-free state becomes the returned state.
- On any failure short of a disconnect, the returned state passes through `retain_trx/3` (`lib/arangox/connection.ex:989-990`), which re-inserts the `x-arango-trx-id` header for stripped requests. DBConnection's follow-up rollback now matches the transaction-in-flight head and issues a real `DELETE /_api/transaction/{id}`.
- "No transaction in flight" is a guarded function head answering `:idle` with no request, for all three of status/commit/rollback.
- `handle_status` reads the body, not the HTTP status: `trx_status/1` maps `"running"` to `:transaction`, `"committed"` to `:idle`, and `"aborted"` or anything unrecognized to `:error` — DBConnection's "inside an aborted transaction," whose recovery (a rollback) is safe in either case.
- The request builders moved to `Arangox.Transaction`, where the identifier travels in the URL path. The wire format is deliberately unchanged from 0.7 — commit/abort requests never carried the transaction header (0.7 stripped it too, `v0.7.0:lib/arangox/connection.ex:322`); the fix is purely driver-side bookkeeping, byte-compatible on the wire.

Verification was characterization-first (U6's execution note): per the commit's account, 26 tests pinned the old behavior before the rewrite, and exactly the five pinned-bug tests went red afterward — nothing else moved. R44 — "a failed transaction commit leaves the transaction reachable, so a subsequent rollback addresses the real server-side transaction" — is covered both by an isolated callback test (`test/arangox/transaction_test.exs:346`) and an end-to-end pool test through DBConnection (`test/arangox/transaction_test.exs:468`).

Two safety properties close the loop. If the follow-up rollback itself fails, `handle_rollback` returns `{:error, state}` with the header retained, and DBConnection treats any status return from rollback as grounds to retire the connection (`run_rollback/3` at `deps/db_connection/lib/db_connection.ex:1873-1880`, via `status_disconnect/3` at `:1913-1917`) — so a retained identifier cannot leak into a later checkout; the connection it lives on never returns to the pool. And because the fix keeps the identifier in state longer, it stays subject to R33's rule that transaction identifiers are redacted from inspection and logs like authentication material — retention must not widen exposure.

## Why This Works

State that records an in-flight protocol exchange must be cleared only on the acknowledged outcome, never optimistically before the exchange. Pop-then-request inverts the dependency: the local bookkeeping asserted the transaction was gone before the server agreed. The rewrite makes acknowledgment the only edge on which the identifier leaves state, so the driver's picture of the world can never run ahead of the server's.

The bug also came from conflating two different questions: what the outgoing request carries on the wire, and what the connection remembers. The commit request legitimately goes out without the transaction header — the identifier is in the URL path — but 0.7 implemented that by mutating the remembered state and returning the mutation on every path. `trx_request/6` separates the two: one parameter controls the request, `retain_trx/3` controls what failure paths remember.

The recovery path (rollback-after-failed-commit) is precisely the path that needs the retained state, and it is also the path no happy-path test exercises — commits that succeed never trigger it. That is why the bug shipped, and why characterization-first testing caught it here: pinning all 26 behaviors before the rewrite forced the failure paths to be written down, and the five that flipped red were exactly the defect, isolated from the twenty-one behaviors worth preserving.

The defect's provenance is instructive. It was surfaced by an anti-pattern audit as style — `handle_status`, `handle_commit` and `handle_rollback` were flagged as "three near-identical copies of the same defective shape" before anyone understood the shape hid a correctness bug — and the plan's decision to pair the rewrite with regression requirements came from the observation that "you can't rewrite those and stay neutral about the bugs — you either fix them or deliberately reimplement them." (session history) A pure-style cleanup that faithfully preserved behavior would have reimplemented the orphaned-transaction bug with cleaner syntax.

## Prevention

- When reviewing any code that clears, pops, or overwrites state around an I/O call, ask what the *failure* path needs. If the cleared state is what recovery would use to address the remote side, it must survive until the remote side acknowledges.
- Write the failed-terminal-request test explicitly: "the commit/close/release fails — what does the follow-up see?" This test does not fall out of happy-path coverage, ever. Here it is `test/arangox/transaction_test.exs:346` (callback level) and `:468` (through the pool).
- Keep "what goes on the wire" and "what the connection remembers" as separate parameters, not one mutation. If stripping a header for the request also strips it from state, the two concerns have been merged and the failure path pays for it.
- For rewrites of behavior-bearing code, characterize first: pin the old behavior completely, rewrite, and require that exactly the intended tests flip. The red set is then a precise statement of what the fix changed.
- Do not let a transport status code stand in for protocol state carried in the body. A 200 that means "I remember this" is not a 200 that means "this is running."

## Related Issues

- Requirement R44 and unit U6 in `docs/plans/2026-08-06-001-feat-arangox-1-0-modernization-plan.md`; Q2 (whether status keeps its server round-trip) is resolved inside U6.
- The plan's risk register notes the transaction identifier is a bearer capability (R33, redaction owned by U7/U16) — relevant here because the fix retains the identifier in state longer.
- Sibling learning in the same module, orthogonal failure mode: [[dbconnection-timeout-is-a-deadline-not-a-duration]] (`docs/solutions/architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md`) — deadline arithmetic rather than premature state clearing, but the same lesson family: a DBConnection driver's local bookkeeping must not run ahead of ground truth.
</content>
