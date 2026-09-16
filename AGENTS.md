# arangox — agent notes

An Elixir driver for ArangoDB, implemented on `DBConnection` (Elixir's pooled
database-connection behaviour). The default transport is HTTP via Mint;
VelocyStream (ArangoDB's binary protocol, removed by the server in 3.12) is an
explicit opt-in for 3.11 deployments via `client: Arangox.VelocyClient`.

## Current work

A breaking modernization is in progress on `feat/v0-8-modernization`, shipping
as **0.8.0** — the plan's "1.0" names this release (KD13). 1.0 itself is
reserved for the later release that replaces DBConnection with
`http_connection`. The implementation plan at
`docs/plans/2026-08-06-001-feat-arangox-1-0-modernization-plan.md`
is the authority for that work — requirements (R-numbers), key decisions
(KD/KTD-numbers), and implementation units (U-numbers) are all defined there.
Decisions marked `session-settled` were made with alternatives in view; a real
defect found inside one still gets surfaced, but the preference itself is not
reopened without evidence.

## Code comments

Comments are for whoever has to change the code next, not for whoever reviews
the diff. Write what constrains the code, what breaks if it changes, and what
cannot be seen by reading it — a protocol rule, a required ordering, a
surprising return shape, a reason an obvious simplification is wrong. Then stop.

Do not narrate history ("this used to throw", "the old version pinned"), argue
that a decision was correct, restate what the code plainly says, or close on a
rhetorical flourish. That material belongs in the commit message, where it is
addressed to someone reading history deliberately. Plan identifiers (R-, KD-,
KTD-, U-, AE-, Q-numbers) must never appear in code, comments, docstrings,
test names, or commit messages — they reference internal planning documents a
library user cannot read. State the constraint itself in plain words instead.

The same applies to test comments. A `describe` block may say what question the
block answers; individual tests should not re-argue it.

## Tests

Three tiers:

- `mix test` — unit and protocol tiers, no Docker needed. The protocol tier
  runs against `Arangox.ProtocolServer` (`test/support/protocol_server.ex`),
  a local harness that can serve arbitrary routes, hang, truncate, speak TLS,
  and record what reached it. Read its moduledoc before writing socket-level
  tests.
- `mix test.integration` — needs the containers from `docker-compose.yml`
  (`docker compose up --detach --wait`). Its preflight probe expects the full
  stack; `ARANGOX_SKIP_DOCKER_CHECK=1 mix test --only integration <file>`
  runs a subset against whatever is up. Integration tests carry a *valued*
  tag — `integration: true` (3.12 tier), `integration: :arango_3_11` (the
  3.11 trio), `integration: :readme` (README doctests, full stack) — so CI
  legs select by value (`--only integration:arango_3_11`) while the bare
  `--only integration` behind `mix test.integration` matches all of them.
  Compose profiles mirror the split (`3.12`/`3.11`); the committed `.env`
  enables both so plain `docker compose up` is unchanged.

Container topology (host ports): `single_no_auth` 8529 and `single_auth`
8001/8002 (TLS) on 3.12; `resilient_single` 8003–8005, a 3.11 active-failover
trio deliberately pinned to 3.11 (VelocyStream and active failover are
3.11-only concerns); `cluster` 8006–8008, three coordinators for
cross-coordinator behavior (stream-transaction identity, leader questions).

Hygiene expected before claiming work done: `mix test`,
`mix compile --warnings-as-errors`, `mix format --check-formatted` on touched
files, and red-before-green evidence for behavior-bearing changes.

## Documented solutions

`docs/solutions/` holds documented solutions to past problems (bugs,
architecture patterns), organized by category with YAML frontmatter
(`module`, `tags`, `problem_type`). Relevant when implementing or debugging
in areas it covers — currently DBConnection mechanics (timeouts, deadlines,
callback processes), transaction-state ordering, and URL construction in the
API surface. These ship with the library; see _Publishing to origin_ for what
that requires of them.

`CONCEPTS.md` at the repo root is the shared domain vocabulary — entities,
named processes, and status concepts with project-specific meaning ("Client"
means a transport implementation here, not a consumer). Relevant when
orienting or naming things.

## Generated code: errno

`lib/arangox/errno.ex` is generated — edit `priv/arangodb/gen_errno.exs` and
regenerate (`mix run priv/arangodb/gen_errno.exs`); never hand-edit the
module. The source table `priv/arangodb/errors-3.12.10.dat` is vendored and
SHA-pinned (see `priv/arangodb/README.md`). Its tag is the driver's single
version pin: `Arangox.Errno.tag/0`, which must equal the compose default in
`docker-compose.yml` — the conformance gate asserts it against the live
server before comparing anything.

## The API surface

`lib/arangox/api/` is owned, hand-maintained source. It was derived from
ArangoDB's OpenAPI description once, but no generator stands behind it and
nothing regenerates it — edit it by hand, with tests. Two gates watch it:

- `test/arangox/api/surface_test.exs` (unit tier, pure source): the adapter
  seam (every operation reaches the network only through
  `Arangox.API.Client`), every path segment a literal or a bare argument,
  every operation carrying a delegating bang twin, no parameter both forced
  and offered, and the pinned 230-operation count.
- `test/arangox/api/conformance_test.exs` (integration tier): fetches the API
  description the compose 3.12 server itself serves and compares the surface
  against it — address coverage both ways, query keys, required-parameter
  reachability, request media. Its moduledoc is where the set-comparison rule
  and the stripped database prefix are explained.

Addresses are compared as sets, not one to one. The description lists 243
operations at 228 distinct addresses, because it documents one endpoint
several times when it takes more than one body or answers more than one shape
— eight ways to create an index, six view operations with a search-alias twin.
The surface carries 230 operations: one per address, plus two deliberate
extras where an address genuinely does two things (`POST` and `PUT` on
`/_api/document/{collection}`). All three counts are pinned.

A required query parameter is either forced by the operation or offered as an
option, and the conformance gate fails if it is neither. The one that must
never be offered is `onlyget` on `PUT /_api/document/{collection}`: without it
that request replaces the whole collection instead of reading from it, so
`get_many/4` forces it and `replace_many/4` must not.

### Recorded response shapes

The description the server serves does not describe most success bodies: it
carries no reusable schemas at all, and 417 of its 752 responses have no
content schema. Prose is not a type, so the shapes in each operation's
`## Returns` section come from the server instead — recorded by
`priv/arangodb/capture_responses.exs` into
`priv/arangodb/response-shapes-<tag>.json`, which is committed.

Run it with the compose stack up (`mix run priv/arangodb/capture_responses.exs`).
It builds a fixture (collection, document, index, graph, view, analyzer, user,
transaction), sweeps every GET and HEAD whose arguments the fixture can fill,
runs a named list of writes, and records a second pass against the cluster
coordinator for the reads a single server answers 501 or 403 to. Writes are
never swept — a sweep that guesses at write operations eventually calls
something irreversible.

98 of 230 operations currently carry a recorded shape. The rest are reads
needing a fixture nobody has built yet (Foxx wants a deployed service, jobs
want an async job, replication wants a batch), writes not on the named list,
or `shutdown_progress`, which only answers while the server is shutting down.
Refresh the recording when the version pin moves; an operation with no
recording simply has no `## Returns` section, which is the honest outcome.

### Known fidelity gaps

The surface deliberately does not carry everything the document states. Each
gap below ends with the check that re-derives its numbers from the live
document (`GET http://localhost:8529/_db/_system/_admin/aardvark/api/swagger.json`,
no auth); re-run them when the pin moves and refresh these counts and the
README's user-facing disclosures.

1. **Five array schemas carry no `items`**, so the surface types them
   `term`/`[:unknown]` rather than inventing an element schema the document
   does not state: the request bodies of
   `DELETE /_api/document/{collection}` (deleteDocuments) and
   `PUT /_api/document/{collection}#get` (getDocuments), and the `result`
   property of the success responses of `POST /_api/cursor` and its two
   cursor-continuation operations. Check: walk every `requestBody` and
   response schema (including nested `properties`) for `"type": "array"`
   objects lacking an `items` key.
2. **47 header parameter objects across 4 names appear in no signature**:
   `x-arango-trx-id` (24 uses — the per-request `:transaction` option covers
   it), `If-Match` (13) and `If-None-Match` (4) (callers pass them via
   `:headers`), and `x-arango-allow-dirty-read` (6, also `:headers`).
   Anything that must set a header is the adapter's concern, never an
   operation's. Check: enumerate parameter objects with `"in": "header"`
   across all operations; count total and per name.
3. **129 of the document's 164 paths carry the `/_db/{database-name}/`
   prefix**, which the surface leaves off entirely: the database is a
   `:database` option that the driver prepends, falling back to the pool's own
   setting. 6 paths hardcode `/_db/_system/` (database management), and 29
   (backup, cluster, log and server administration, `/_open/auth`,
   `/_api/token`) carry no `/_db` prefix at all. Check: count the document's
   path keys by prefix.

### Updating to a new server tag

1. Bump the compose default (`ARANGO_VERSION` in `docker-compose.yml`) and
   the errno pin together: vendor the new `errors-<tag>.dat` and regenerate
   `Arangox.Errno` per `priv/arangodb/README.md`. `Errno.tag/0` is the pin
   everything else asserts against.
2. Start the stack and run the conformance gate. It reports drift as concrete
   mismatches — operations added or removed, query keys or request media
   changed, cardinality moved. Hand-apply that drift to the owned surface
   (and the gate's pinned counts and required-parameter watch) until green.
3. Re-run the fidelity-gap checks above and refresh their counts here and the
   user-facing disclosures in `README.md`.
4. Read the server release notes for semantic changes the gate cannot see —
   behavior, defaults, deprecations behind an unchanged address.

## Publishing to origin

Work happens on a feature branch. The branch is pushed, a pull request carries
it, and GitHub squash-merges it into `main`. There is no separate release
branch and no hand-split history: `main` gets one commit per merged branch.

That squash commit is created by GitHub, so it is signed with GitHub's own key
rather than yours — it shows as verified, by GitHub. Your own commits on the
branch are signed with your key; `commit.gpgsign` and `tag.gpgsign` are set
locally so that happens without being asked for. If the signing agent's
passphrase cache has expired, a commit fails with `gpg failed to sign the
data` and nothing is written; unlock the agent and repeat the command.

These notes, `CLAUDE.md`, `CONCEPTS.md`, `docs/plans/` and `docs/solutions/`
are tracked and reach origin with the library. They keep the citations that
produced them — requirement, decision and unit numbers, and which review pass
found what — because a maintainer reading them is the audience. The library
itself does not: no planning identifier belongs in code, comments, docstrings,
test names, or a commit message, where a library user would meet it with no
way to look it up.

Still untracked, in `.git/info/exclude`: `docs/handoffs/` (notes passed
between working sessions), `.claude/`, and `.gstack/`.

Two local tools guard the push, in `.git/release-tools/`:

- `scan.sh [ref]` refuses content that reveals how the repository is worked
  on. With no argument it reads the tracked working tree; with a ref it reads
  that ref's tree. Patterns live beside it, split into case-insensitive prose
  (`patterns-i.txt`) and case-sensitive planning identifiers
  (`patterns-s.txt`).

  It does not read `AGENTS.md`, `docs/plans/` or `docs/solutions/`, which are
  published with their citations intact, nor lockfiles, whose hex digests match
  the identifier patterns by accident. Those exclusions are listed in
  `scan.sh` itself. What remains guarded is everything a library user reads as
  the library: `lib/`, `test/`, `README.md`, `CHANGELOG.md`, `CONCEPTS.md`,
  `mix.exs`. It also fails when any path in `paths.txt` is tracked at all — a
  directory arriving wholesale is a lost exclusion, not a phrase, and no
  content pattern would see it.

- `.git/hooks/pre-push` scans the tree being pushed and the commit messages in
  the push range, and refuses the push on a hit. `--no-verify` overrides it.

Everything under `.git/` is local and does not survive a fresh clone. After
re-cloning, the exclude list, the hooks, and these tools are all gone and
nothing warns you. Copy `.git/info/exclude` and `.git/release-tools/` out
before deleting a checkout.

## Known quirks

- The `resilient_single` service runs with authentication enabled (U18): a
  committed test-only JWT secret turns it on, and root keeps the empty
  password the tier uses everywhere. Tests reaching ports 8003–8005 must pass
  `auth: {:basic, "root", ""}` — the driver has no default auth. This is what
  lets `"auth resolution with velocy client"` assert that wrong credentials
  are refused; 3.12 has authentication but no VelocyStream, so the 3.11
  service is the only host on which that test means anything.
- Only the active-failover *leader* answers a write, and which of the three
  3.11 members leads is not fixed. Reads and VelocyStream authentication are
  served by any member, which is why most tests can name one port; a test that
  writes has to find the leader (see `vst_leader!/0` in
  `test/arangox/client_test.exs`).
- The whole tree passes `mix format --check-formatted`, and CI enforces it
  globally (U18). The old carve-out for two unformatted test files is gone.
- Pull images from the official `arangodb` repository, not from
  `arangodb/arangodb`. The organisation repository is missing recent tags —
  3.12.5 onwards is absent there but present in the official one — which is
  what once made the pinned tag look unpublished. The compose default is the
  driver's pin: it must equal `Errno.tag/0`, and the conformance gate fails
  on any mismatch.
