# Changelog

## v0.8.0 (2026-08-12)

HTTP via Mint is now the default transport for ArangoDB 3.12 and later; 
VelocyStream and active failover remain supported as explicit opt-ins 
for ArangoDB 3.11, which is the last server release that speaks them.

* Breaking changes
  * The default client is `Arangox.MintClient` over HTTP. ArangoDB removed
    VelocyStream in 3.12, so `Arangox.VelocyClient` must now be selected
    explicitly (`client: Arangox.VelocyClient`) and needs a 3.11 server. The
    Gun client remains available as `Arangox.GunClient`.
  * TLS certificates are verified by default (`verify_peer`, hostname checks,
    system trust store), and TLS below 1.2 is refused. Connecting to a server
    with an untrusted certificate now fails until you supply trust material
    via `ssl_opts: [cacertfile: ...]` or opt out with
    `ssl_opts: [verify: :verify_none]`.
  * A pool configured with `:auth` refuses to start when its endpoints are
    cleartext (`http://`) and not on this machine, because the credentials
    would be readable in transit. Loopback endpoints are exempt; opt in
    explicitly with `allow_cleartext_auth: true`.
  * Every client failure is an `%Arangox.Error{}` with `:reason` populated —
    HTTP status, ArangoDB `errorNum`, and an atom reason derived from it.
    Connect failures are returned, never raised.
  * Stream transactions are handle-based. `Arangox.begin_transaction/2`
    returns an `%Arangox.Transaction{}` handle; requests join it with the
    per-request `transaction:` option. The option accepts only the handle
    struct, never a bare identifier binary.
  * `DBConnection.prepare/2` for AQL is refused: ArangoDB has no prepared
    statements. The AQL plan cache (ArangoDB 3.12.4+) is an explicit opt-in
    via `use_plan_cache: true`, with `Arangox.plan_cache/1` and
    `Arangox.clear_plan_cache/1` to manage it.
  * Every request runs under an absolute deadline established when the caller
    enters the pool, so time spent queueing counts against `:timeout`. A
    timed-out request disconnects its connection instead of returning it to
    the pool, and a fully written request is never retried automatically.
  * `:json_library` and `:vst_maxsize` are per-pool start options. The
    application-config forms still work and warn once per pool; they will
    be removed in the next release.
  * The `:database` option (per pool and per request) is validated: names
    that would alter the request path (`/`, `?`, `#`, `%`, control
    characters) are refused, and extended names (spaces, unicode) are
    percent-encoded on HTTP paths.
  * Leader redirects (active failover, 3.11) are only followed when the
    advertised endpoint passes an admission policy; anything else requires an
    explicit `:endpoint_mapper`. Unknown start options log a warning.
  * Headers are lists of `{name, value}` string tuples; maps are no longer
    accepted, at the `:headers` start option or on a request. The wire order
    is fixed — pool headers, then the transaction header when one applies,
    then the request's own — and nothing is merged, deduplicated, renamed or
    re-cased: a request header no longer *replaces* a same-named pool header,
    both are sent. The body codec is selected from the request's own headers
    (first `content-type` entry, any casing) or the `:content_type` pool
    option — never from pool `:headers`. Exactly one transaction header is
    ever added, and a request already naming one, in any casing, runs under
    its own. Response headers are the same shape — the parsed `{name, value}`
    list, order and repeats as received over HTTP, built from the wire map
    over VelocyStream. See the README's "Headers" section for the per-client
    wire behavior.
  * Requires Elixir 1.15+ on OTP 26+. The OTP floor is enforced at compile
    time: `:ssl` verifies peers by default from OTP 26, and the TLS defaults
    above rely on that.

* Enhancements
  * A resource API: 243 operations across 22 `Arangox.Api.*` modules —
    `Arangox.Api.Collections.create_collection/3`,
    `Arangox.Api.Documents.get_document/4`, and so on — derived from
    ArangoDB's OpenAPI description at tag 3.12.10 and owned as hand-maintained
    source. Every operation runs through the driver's pool and carries its
    error contract, `:database`, `:transaction`, and timeout options. The
    integration suite verifies the surface, operation by operation, against
    the OpenAPI document the tested server itself serves. Reading several
    documents by key is `Arangox.Api.Documents.get_documents/4`, which always
    sends `onlyget=true` — the flag that separates it from a bulk replace on
    the same URL.
  * Opt-in VelocyPack bodies over HTTP: `content_type: :velocypack` (requires
    the optional `:velocy` dependency) encodes request bodies as VelocyPack
    and asks for the same in return. Responses are decoded by their own
    content type, so a server that answers JSON is still read correctly.
  * HTTP/2 support on both HTTP clients. On `Arangox.MintClient` it is opt-in
    per pool with `client_opts: [protocols: [:http2]]` — settled by ALPN on
    TLS, prior knowledge on cleartext — and HTTP/1.1 remains its default on
    both schemes; see the known limitation below for why it is offered rather
    than assumed. `Arangox.GunClient` follows `:gun`'s own defaults instead
    (HTTP/1.1 on cleartext, ALPN with HTTP/2 preferred on TLS), since the
    limitation is Mint-specific; `client_opts: %{protocols: [:http2]}` asserts
    it on cleartext.
  * Header names and values carrying a carriage return, line feed, or null are
    refused before they reach a transport, with `reason: :invalid_header_value`
    naming the header but never echoing its value. The rule lives at the one
    seam every request and connect probe crosses, so it holds under both
    protocols — HTTP/1.1 refuses such a value locally, while under HTTP/2 the
    header is HPACK-encoded and only the server would object.
  * `Arangox.query/4` as the one-shot AQL door, mapping snake_case options to
    the server's keys, plus streamed cursors through `DBConnection.stream/4`.
  * `:max_body_size` pool option (default 128 MiB): a larger response body is
    rejected with a structured error before any decoding runs. Malformed
    bodies in either codec return structured errors (`:encode_error`,
    `:decode_error`, `:body_too_large`, `:invalid_length`) instead of
    raising, with size and length-prefix bounds enforced before the decoder
    sees a byte.
  * Credential redaction throughout: inspecting connection state, requests,
    or transaction handles never reveals credentials or transaction
    identifiers; the request struct echoed back from a call carries
    `[redacted]` in place of sensitive header values. An endpoint containing
    an `@` anywhere is stored and reported with everything after its scheme
    replaced by `[redacted]` — the redaction never tries to locate the
    userinfo, so a typo'd endpoint cannot smuggle a password past it — and an
    endpoint without an `@` has no userinfo to lose and stays readable in
    errors and logs. `show_sensitive_data_on_connection_error` restores
    credentials in connect-time errors only, for debugging.
  * Unix domain socket support in `Arangox.MintClient`
    (`"http://unix:/path/to.sock"`).
  * Raw request bodies: a `content-type` naming neither JSON nor VelocyPack
    (`text/plain` for `/_api/import`, `application/octet-stream`) sends a
    binary body byte-for-byte instead of running it through the JSON codec —
    which had quietly quoted such bodies since 0.7. `Arangox.Api` operations
    declaring a single non-JSON request media type set the header themselves.

* Fixes
  * A cursor the server issued no id for — a single-batch result — is keyed
    under a reference and answered entirely from driver memory: abandoning it
    before its batch was delivered no longer builds a `DELETE` for an id the
    server never issued (previously a crash that retired the connection), and
    its cleanup is the local no-op it always should have been. A cursor-create
    reply promising more batches *without* an id is refused at declare: those
    batches could never be fetched.
  * `Arangox.GunClient`'s socket carries the same teardown hygiene as the
    other clients — a bounded driver queue and an abort on close. Per-request
    send bounds deliberately do not apply to it: `:gun` writes from its own
    process, so a caller can never block inside a socket send, which is now
    documented and pinned by a test.
  * A 2xx response whose declared content type is neither JSON nor VelocyPack
    is returned with its body raw instead of failing as `:decode_error` —
    Prometheus metrics, multipart batch responses, and Foxx bundle downloads
    are non-JSON successes. An absent content type still decodes as JSON.
  * `ping/1` no longer disconnects a healthy pool when `:request_timeout` is
    set below the driver's socket-timeout floor: requests that arrive with no
    caller deadline get at least the floor as their budget, so an aggressive
    `:request_timeout` bounds callers without turning every idle health check
    into a reconnect.
  * A budget spent before anything was written reports "before the request
    was sent" rather than borrowing the receive-phase wording that claimed a
    response was in flight.
  * A malformed entry in a request's header list — anything but a
    `{name, value}` tuple — is refused as a described error on a healthy
    connection instead of raising out of the callback and retiring it. The
    entry is never echoed; it may carry a credential.
  * A supported `:auth` tuple carrying a non-string credential is refused at
    `start_link/1`, and again described — never rendered — by the connect
    pipeline, so a pool started directly through `DBConnection.start_link/2`
    cannot leak the value into the connect-failure log.
  * Socket writes are bounded by the request's remaining budget: each request
    (and each VelocyStream chunk) re-derives the socket's send timeout from
    its deadline, the inet driver's send queue is bounded by a watermark so
    the send timer actually runs for large bodies, and sockets close with a
    zero linger so retiring a connection with unsent bytes queued to a dead
    peer aborts instead of stalling in the driver's flush wait.
  * An HTTP/2 connection the server has told to go away (GOAWAY) is retired
    from the pool as soon as a request fails on it. Both HTTP clients now
    consult the socket, not just the error's reason atom, before a connection
    goes back to the pool, and the VelocyStream client reports a retiring
    reason for any failure past the point where bytes reached the wire.
  * The connect pipeline catches throws and exits — not only raises — from
    user-pluggable code (a `:json_library` decoding probe responses), failing
    the connect in order instead of crash-looping the connection process.
  * `Arangox.GunClient` handles a `1xx` informational response by waiting for
    the real one instead of failing the request.
  * `Exception.message/1` on a long error truncates on a UTF-8 character
    boundary.
  * An explicit default port (`:80`/`:443`) is recognized only in the
    endpoint's authority; the same digits in a path or userinfo no longer
    count as writing the port out.
  * Connection processes no longer leak sockets when authentication or the
    availability probe fails during connect.
  * A transport error while probing one endpoint no longer stops the walk —
    the remaining endpoints are still tried.
  * A per-request `:database` no longer double-prefixes a path that already
    names one.
  * The VelocyStream client answers with an error instead of raising when
    given an unsupported HTTP method or a body it cannot encode, and its
    connect timeout budget is per endpoint rather than shared across probe
    stages.
  * A cursor drain that outlives its deadline retires the connection instead
    of leaving it poisoned in the pool.

### Known limitations

**`Arangox.MintClient` bounds HTTP/2 request bodies by the peer's
flow-control window.** It hands a request body to `Mint.request/5` whole rather
than streaming it, and HTTP/2 applies flow control to request bodies: one
larger than the window the peer advertises is refused with
`reason: :exceeds_window_size` rather than waiting for a `WINDOW_UPDATE`.
ArangoDB advertises about 64 KiB, so bulk inserts and large documents exceed
it. `Arangox.GunClient` does **not** have this limitation — `:gun` queues the
body and honours `WINDOW_UPDATE` itself — and neither client is affected on
HTTP/1.1, which has no flow control.

This is why HTTP/2 is opt-in on `Arangox.MintClient` rather than its default,
even though ALPN would negotiate it on TLS: a driver whose bulk inserts fail
above 64 KiB is worse than one speaking HTTP/1.1. `Arangox.GunClient` has no
such bound and follows `:gun`'s own defaults, which negotiate HTTP/2 on TLS;
a Mint pool that opts in should keep its bodies below the window its server
advertises.

Streaming request bodies in window-sized chunks is what removes the bound. It
needs the client to interleave writing the body with reading `WINDOW_UPDATE`
frames under the request deadline, so it is deliberately not a 0.8 change; it
lands with the transport rework below, which is also what makes HTTP/2 worth
defaulting to.

**HTTP/2 multiplexing is not exploited.** `DBConnection` runs one in-flight
request per pooled connection, so concurrency comes from `:pool_size` rather
than from streams sharing a connection.

### What comes next

1.0 replaces the `DBConnection` foundation with `http_connection`. That swap is
what makes multiplexing and streamed request bodies reachable, and it is
breaking on its own — `t:Arangox.conn/0`, `DBConnection.ConnectionError`,
`DBConnection.Stream`, and the pool options are all part of the public surface
today. 0.8 exists so the stability promise lands on the foundation that stays;
the next release removes the deprecated application-config fallbacks in between.

### Migrating from v0.7

Work through these in order; most upgrades need only the first two.

**Pick your client.** If you never set `:client`, v0.7 gave you VelocyStream
and v0.8 gives you HTTP via Mint — add `{:mint, "~> 1.9"}` and `{:jason, "~> 1.4"}`
to your deps and you are done. Requests and responses behave the same. If you
must stay on VelocyStream, set `client: Arangox.VelocyClient` explicitly and
stay on an ArangoDB 3.11 server; 3.12 closes VST connections on sight.

**TLS now verifies.** A `ssl://` endpoint that connected fine under v0.7
(against any certificate, silently) fails under v0.8 until the trust question
is answered. Two different situations need two different answers:

  * a certificate from a **private CA**: point the pool at the CA —
    `ssl_opts: [cacertfile: "/path/to/ca.pem"]`;
  * a **self-signed** certificate you cannot get a CA for:
    `ssl_opts: [verify: :verify_none]`, accepting that the connection is
    then unauthenticated.

**Cleartext with credentials refuses to start** unless the endpoint is
loopback. If you authenticate over plain `http://` to another machine, either
move to TLS or acknowledge the exposure with `allow_cleartext_auth: true`.

**Transactions.** `DBConnection.transaction/3` blocks keep working. Code that
held a raw transaction id binary must hold the `%Arangox.Transaction{}` handle
from `Arangox.begin_transaction/2` instead and pass it per request as
`transaction: trx` — the id is accepted nowhere by itself.

**Application config.** `config :arangox, :json_library` and `:vst_maxsize`
still work and warn; move them to `start_link/1` options before the next release.
Two pools can now disagree, which is the point.

**Timeouts.** `:timeout` is a deadline from pool entry, so queue time counts
against it; a timed-out request disconnects its connection and is never
retried by the driver. If you relied on slow requests surviving past their
timeout, raise the timeout — the old behavior was the bug.

**Redirect targets are vetted.** In containerized 3.11 failover setups where
the leader advertises an address only reachable from inside the network, map
it: `endpoint_mapper: %{"http://advertised:8529" => "http://reachable:8529"}`.
Without a mapping (or same-origin match) the redirect is refused rather than
followed with your credentials.

**Custom clients** must adopt the three-argument callback
`request(request, opts, state)` and return `%Arangox.Error{}` for every
failure; bare reason atoms and library exceptions are no longer accepted. The
raise you get on start names exactly what to change.

## v0.7.0 (2024-02-20)

* Enhancements
  * Added support for ArangoDB JWT authentication via bearer tokens

* Breaking changes
  * `auth` start option now only accepts `{:basic, username, password}` or `{:bearer, token}`
  * No longer authenticates with "root:" by default
  * Requires Elixir v1.7+.
