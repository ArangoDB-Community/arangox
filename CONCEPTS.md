# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## Connection and transport

### Client
A pluggable transport implementation — the thing that actually speaks a wire protocol to an ArangoDB server. Not a consumer of this library; the consumer is a caller.

A Client owns connecting, liveness checking, issuing a Request, and closing. It does not own encoding or decoding of bodies, or header merging — those belong to the driver, so every Client sees the same Request and returns the same Response regardless of protocol. A Client is selected per pool at start time, and is the only place a protocol-specific assumption is allowed to live.

Nor does a Client own transport defaults. It passes the caller's transport options through as given and forces only the few its own framing depends on, so what a connection does when the caller says nothing — including whether certificates are verified — stays the transport library's to decide and to improve. Where a transport's own default is safe but its failure is unreadable, a Client may translate the error; it may not substitute an answer.

### Socket
Whatever handle a Client returns from connecting, held in a connection's state and passed back to that same Client on later calls. It is deliberately opaque — a raw TCP socket for one Client, a protocol connection struct for another — so nothing outside the Client may inspect or act on it.

### Endpoint
A single addressable ArangoDB server location: either a host and port, or a Unix domain socket path, together with whether the connection to it is TLS-encrypted.

An Endpoint is an address, not a URL — the scheme in the string a user supplies is consumed at parse time to decide the address form and the TLS flag, and is not carried forward. A pool may be configured with a single Endpoint or with several; when several are given, they are tried in order of precedence.

### VelocyStream
ArangoDB's binary wire protocol, as opposed to HTTP. One of the protocols a Client can implement. Abbreviated VST.

### Caller
The process that asks the pool for a connection and then runs the request itself. Worth naming because it is not the connection process: the pool hands the connection's state to the Caller, which applies the Client's callbacks in its own process and is therefore the process actually blocked while waiting on a Socket.

### Request deadline
The absolute instant by which a request must complete, fixed when the Caller enters the pool — a point in time, not a duration that restarts at each step, so time spent queueing for a connection is already spent. Every socket wait a request performs, receiving and writing alike, is derived from what remains of it, and a request that outlives it ends in Retirement rather than in a longer wait.

### Retirement
Taking a connection out of service instead of returning it to the pool, forced whenever its Socket can no longer be trusted to carry the next request — bytes may still be in flight, a response was left half-read, or the peer is gone. A retiring close aborts rather than lingers: nothing legitimately waits on the far side of a connection the driver has decided to discard.

## API surface

### API surface
The resource-object operations under `Arangox.Api.*` — one Elixir function per operation of ArangoDB's HTTP API, each reaching the network only through the Adapter. Spec-derived owned source: the functions were originally produced from ArangoDB's published OpenAPI document and are hand-maintained, with conformance to the server's own document enforced by the Conformance gate rather than by regeneration.

### Adapter
The single module (`Arangox.Api.Client`) every API-surface operation calls, translating an operation's request map into a driver request. It is operation-agnostic — nothing in it is keyed to a specific operation — and it is the seam that keeps the surface transport-independent: a transport change touches the Adapter, never the operations.

### Conformance gate
The integration-tier test proving the API surface matches the Live oracle: operation addresses (as a multiset — the document distinguishes two operations sharing a path and method by a URL fragment), query-parameter sets, request media, required-parameter declarations, and operation identity. It asserts the server's version equals the driver's single pinned server version first, so the error table, the surface, and the test server always describe the same release.

### Live oracle
The API description the tested server itself serves, used as the authority the Conformance gate checks the API surface against. Distinct from a vendored copy of the same description, which can drift from the server it claims to describe; the live oracle and the system under test cannot disagree about which release they are.

## Transactions

### Stream Transaction
A server-side ArangoDB transaction addressed by an identifier, so that individual requests — possibly on different connections — participate by carrying that identifier rather than by being bound to one connection.

The identifier is a bearer capability: whoever presents it acts inside the transaction, so it is redacted from inspection and logs like authentication material. It encodes the coordinator that issued it, and other coordinators forward participating requests there, which is what makes the transaction usable from any pooled connection. The server ends transactions on its own timeout, so a driver's local bookkeeping about whether one is running can be wrong in both directions; and a finished transaction remains queryable for a retention window, answering with its final status rather than disappearing.

## Flagged ambiguities

- "Timeout" had been used for both the pool's checkout deadline (how long a Caller will wait to obtain a connection, measured from when it entered the pool) and a request's own time budget at the socket. These are distinct, and the first is an absolute instant rather than a duration that can be reused for the second.
