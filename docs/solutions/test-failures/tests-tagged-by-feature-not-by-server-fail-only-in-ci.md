---
title: "A test tagged by the feature it exercises, not the server it reaches, fails only in CI"
date: 2026-09-16
category: test-failures
module: arangox-test-suite
problem_type: test_failure
component: testing_framework
severity: high
symptoms:
  - "The whole integration suite passes locally and the same commit fails in CI, where each job starts one compose profile"
  - "A TLS connection the test requires to succeed comes back an error in the 3.11 job, because port 8002 belongs to the 3.12 service that job never starts"
  - "A pooled connection naming one active-failover member reports that all endpoints are unavailable whenever that member is a follower rather than the leader"
  - "A job that runs one test file fails with \"no test was executed\" after the document those tests were generated from was rewritten"
root_cause: test_isolation
resolution_type: test_fix
related_components:
  - development_workflow
  - tooling
tags: [exunit-tags, integration-tests, ci-matrix, docker-compose-profiles, active-failover, velocystream, doctests, environment-parity, arangox]
---

# A test tagged by the feature it exercises, not the server it reaches, fails only in CI

## Problem

Two integration tests carried the tag of the feature they exercise instead of
the tag of the server they connect to. Each continuous integration (CI) job
starts a single Docker Compose profile, so a test selected into the wrong leg
finds nothing listening on the port it needs; a developer's machine has every
profile up, which makes the mistake invisible locally.

## Symptoms

A developer sees `mix test` pass, `mix test.integration` pass, and two CI legs
fail on the same pull request (#10). Nothing in the local output distinguishes
a correctly tagged test from a wrongly tagged one.

The Transport Layer Security (TLS) test in the VelocyStream block fails on its
middle assertion. `test/arangox/client_test.exs:277-282` asserts three outcomes
against `ssl://localhost:8002`, and that port belongs to the `single_auth`
service, which is in the `3.12` profile (`docker-compose.yml:46` and `:53`).
Run in the 3.11 leg, nothing answers there, so every one of the three connects
returns the same refusal:

```
{:error, %Arangox.Error{message: ":econnrefused", reason: :econnrefused, ...}}
```

The first and third assertions expect an error and still pass, for a reason
that has nothing to do with what they were written to check. The second
assertion, at `:279`, expects `{:ok, {:ssl, _port}}` and is the one that goes
red. That
shape of failure is worth recognising, because two thirds of the test kept
reporting success while the service it describes was absent.

The active-failover authentication test fails differently. `Arangox.get!/3`
raises, and the pool logs the same line on every backoff cycle:

```
[error] Arangox.Connection (#PID<0.222.0> ("db_conn_1")) failed to connect:
        ** (Arangox.Error) all endpoints are unavailable
[error] ** (DBConnection.ConnectionError) [] connection not available and
        request was dropped from queue after 4493ms.
```

That is the output of pointing a pool at a single member of the 3.11
active-failover trio when that member is a follower, reproduced locally against
port 8004. Which member leads is not fixed. Locally 8003 leads, and 8003 is the
member the test named, so the test passed. In CI another member led.

The three members answer the connect pipeline's availability probe differently,
which is the whole mechanism:

```
GET /_admin/server/availability
  8003 -> 200 OK
  8004 -> 503 Service Unavailable, X-Arango-Endpoint: http://localhost:8529
  8005 -> 503 Service Unavailable, X-Arango-Endpoint: http://localhost:8529
```

A third leg in the same CI run failed with no ArangoDB involved at all. The job
ran `mix test.integration test/readme_test.exs`, and Mix reported:

```
Result: 0 tests, 1 excluded
The --only option was given to "mix test" but no test was executed
```

## What Didn't Work

Nothing was tried and rejected. Both causes were read straight out of the CI
logs and the tree. The useful finding is not a discarded approach but the fact
that no local run could have caught either one, for four separate reasons.

- **Every profile is up locally by design.** The committed `.env:6` sets
  `COMPOSE_PROFILES=3.12,3.11`, so a plain `docker compose up --detach --wait`
  starts both server lines. Port 8002 answers and the whole trio answers, which
  is exactly the condition under which a mis-tagged test cannot fail.
- **The local integration alias ignores tag values.** `mix test.integration`
  expands to `test --only integration` (`mix.exs:73`), and a bare `integration`
  filter matches any value the tag carries. The tag that decides which CI leg
  runs a test therefore has no effect on the local run at all.
- **A green `mix test` is not evidence about tags.** The integration tier is
  excluded wholesale at `test/test_helper.exs:111`, so `mix test` never loads
  either test. It also never loaded `test/readme_test.exs`, whose module tag
  `integration: :readme` put it in the same excluded set. `mix test` stayed
  green through a file that defined zero tests, which is why the README problem
  surfaced only in the job that selected that file by name.
- **The suite's own preflight probe is silent in CI.** The friendly "nothing is
  listening, start the containers" message at `test/test_helper.exs:128-148`
  fires only when the bare atom `:integration` appears in the include list. Each
  CI leg selects a value instead (`--only integration:true`,
  `--only integration:arango_3_11`), which puts a keyword pair there, so the
  probe never runs and the leg reports raw connection failures.

One repair that looks available is not. The followers advertise the current
leader in an `X-Arango-Endpoint` header, and the driver knows how to re-enter
the walk at an advertised leader, so following that header appears to solve the
failover test without touching the endpoint list. The advertised value is
`http://localhost:8529`, the container's own internal port. From the host that
address is either nothing at all, in the 3.11 leg, or the unrelated 3.12
`single_no_auth` service (`docker-compose.yml:36`). The driver refuses it in any
case, because an advertised origin is admitted only if it already appears in the
configured `:endpoints` (`lib/arangox/connection.ex:957-962`). Redirect
following cannot rescue a pool that was given one member.

## Solution

Both fixes are in pull request #10, in the commit whose subject is "test: tag
integration tests by the service they reach, and drop the README leg".

The TLS test now overrides its describe block's tag. The block at
`test/arangox/client_test.exs:134-135` carries
`@describetag integration: :arango_3_11`, which is right for the tests in it
that speak VelocyStream, and a per-test tag beats a describe tag:

```elixir
# This client adds no TLS defaults of its own and takes none
# away, so `:ssl`'s own default applies and the container's self-signed
# certificate is refused until the caller says otherwise. Stays on the 3.12
# service: it is the only one with a TLS endpoint, and nothing here reaches
# the VelocyStream protocol — `connect/2` writes the handshake and returns.
@tag integration: true
test "ssl and ssl_opts" do
```

The comment above it already said the test stays on the 3.12 service, so the
prose and the tag had disagreed for as long as both existed. The tag was the
half that was wrong.

The authentication test now passes all three members of the trio instead of one
(`test/arangox_test.exs:250-259`):

```elixir
{:ok, conn1} =
  Arangox.start_link(
    opts(
      endpoints: [@failover_1, @failover_2, @failover_3],
      auth: {:basic, "root", ""},
      client: Arangox.VelocyClient
    )
  )

assert %Response{status: 200} = Arangox.get!(conn1, "/_admin/server/mode")
```

The three module attributes resolve to ports 8003, 8004 and 8005
(`test/arangox_test.exs:21-23`, `test/test_helper.exs:31-33`), which are the
three members of the single `resilient_single` container
(`docker-compose.yml:71-79`).

The README doctests and their CI job were deleted rather than repaired. The
file had been fifteen lines whose only content was `doctest_file("README.md")`,
so the README's `iex>` examples were the entire source of its tests. A review
pass earlier on this branch rewrote the README and turned those examples into
plain code fences. The file then defined nothing, and a job that ran only that
file had nothing to execute. The README's examples are now illustration, checked
by nothing, and the surviving disclosure is that the tag list in `AGENTS.md`
no longer mentions a `:readme` value.

## Why This Works

A tag on an integration test is a statement about the environment the test
needs, not about the subject it covers. Both mis-tags were accurate
descriptions of the subject. The TLS test does live in the VelocyStream block
and does exercise `Arangox.VelocyClient`, and the authentication test does
exercise VelocyStream authentication, which only the 3.11 service can answer.
Neither fact says anything about which port has to be open, and the port is the
only thing a compose profile controls. Once each CI leg starts one profile, the
tag became a claim about infrastructure while it was still being written as a
claim about topic.

The TLS test is the clean case, because it never reaches the protocol its block
is named for. It calls `Arangox.VelocyClient.connect/2`, which writes the
handshake and returns a socket; no request follows. What the test is really
about is whether the client supplies TLS defaults of its own, and the answer
requires only a TLS listener. The stack has exactly one, at
`docker-compose.yml:57`, and it is on the 3.12 service.

For active failover, a list of endpoints is the right shape because the driver
reads a list as permission to move on. `resolve_options/1` sets
`failover?: is_list(given)` (`lib/arangox/connection.ex:353`), and under
failover an unusable endpoint yields `{:next, reason, state}` rather than an
error (`:665`). A follower answers the availability probe with 503, which
`check_availability/3` routes into the redirect path (`:785-790`), the redirect
is refused for the reasons above, and the walk tries the next configured
endpoint. Three members configured means the walk reaches whichever one leads.

A one-element list is still a list, so the old test had the walk enabled and
nowhere to walk to. It exhausted immediately and produced
`%Error{message: "all endpoints are unavailable"}` (`:226` and `:388`), which
DBConnection (Elixir's pooled database-connection behaviour) logs on every
backoff cycle while the caller's checkout times out. The old test was therefore
asserting on the outcome of a leader election it neither runs nor observes.
Passing every member removes the election from the test's inputs, and it is also
how the driver is documented to be pointed at an active-failover deployment.

There is a detail here that makes the failure look stranger than it is. A
follower does serve the request the test makes: `GET /_admin/server/mode`
answers 200 with `"mode":"readonly"` on 8004 and 8005. The refusal happens one
layer earlier, in the connect pipeline's availability probe, so the pool never
gets far enough to issue the request that would have worked.

## Prevention

- The rule is now stated in `AGENTS.md:55-57`: a test carries the tag of the
  server line whose service it reaches, not the one whose feature it is about,
  because each CI leg starts a single compose profile and a test tagged for the
  other line finds nothing listening. The same rule is stated in the workflow
  header at `.github/workflows/elixir.yml:3-5`, where someone editing a leg
  will see it.
- To check one test's tag, follow the ports rather than the prose. Read which
  `TestHelper` accessor the test uses (`test/test_helper.exs:21-33`), map that
  port to a service in `docker-compose.yml`, read that service's `profiles:`
  key, and confirm the tag value matches the leg that starts that profile
  (`.github/workflows/elixir.yml:132` for `3.12`, `:164` for `3.11`). All three
  trio ports and the TLS port are host-side mappings onto different internal
  ports, so the number in the test never matches the number in the service's
  command; the mapping lines are the only link.
- To reproduce a leg locally, start one profile and select by value, which is
  the condition the mis-tags needed:

  ```
  COMPOSE_PROFILES=3.11 docker compose up --detach --wait
  mix test --only integration:arango_3_11
  ```

  Restore the full stack afterwards with `docker compose up --detach --wait`,
  since the plain command reads both profiles from `.env`. Note that the
  preflight probe stays quiet under a valued selector, so a missing service
  shows up as connection errors rather than as an explanation.
- A test that starts a pool against the trio passes all three members. A test
  that names one member must not need the leader, and the only tests that
  safely name one are those calling a client module directly, which skip the
  connect pipeline entirely.
- Two residual cases are worth knowing about before they mislead someone. The
  comment at `test/test_helper.exs:27-28` still says any of the three ports
  serves, which holds for direct client calls and not for a pool. And two of
  the three pools in `"auth resolution with velocy client"` still name a single
  member (`test/arangox_test.exs:264` and `:274`); they pass because they assert
  a failure, and a follower's refusal and a rejected credential are the same
  `DBConnection.ConnectionError` at the assertion. Those two would keep passing
  if the credentials started being accepted.
- A test file generated from another document has no floor. `doctest_file/1`
  defined every test in `test/readme_test.exs`, so rewriting the README did not
  break a test, it removed all of them, and a job that selected only that file
  failed with `The --only option was given to "mix test" but no test was
  executed` instead of with a broken example. The README carried 54 `iex>`
  prompt lines in eight blank-line-separated blocks before the rewrite and
  carries none now. Any file whose test count can silently reach zero needs
  either an assertion on that count or one hand-written test that exists
  regardless of the source document. Deleting the file and its job was the
  choice made here, which is the honest version of leaving the README's examples
  unchecked.
