# Concepts

Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Terms accrete as the driver's design settles; direct edits are fine. Glossary only, not a spec or catch-all.

## Connection and transport

### Client
A pluggable transport implementation — the thing that actually speaks a wire protocol to an ArangoDB server. Not a consumer of this library; the consumer is a caller.

A Client owns connecting, liveness checking, issuing a Request, and closing. It does not own encoding or decoding of bodies, or header merging — those belong to the driver, so every Client sees the same Request and returns the same Response regardless of protocol. A Client is selected per pool at start time, and is the only place a protocol-specific assumption is allowed to live.

Nor does a Client own transport defaults. It passes the caller's transport options through as given and forces only the few its own framing depends on, so what a connection does when the caller says nothing — including whether certificates are verified — stays the transport library's to decide and to improve. Where a transport's own default is safe but its failure is unreadable, a Client may translate the error; it may not substitute a result.

### Socket
Whatever handle a Client returns from connecting, held in a connection's state and passed back to that same Client on later calls. It is deliberately opaque — a raw TCP socket for one Client, a protocol connection struct for another — so nothing outside the Client may inspect or act on it.

### Endpoint
A single addressable ArangoDB server location: either a host and port, or a Unix domain socket path, together with whether the connection to it is TLS-encrypted.

An Endpoint is an address, not a URL — the scheme in the string a user supplies is consumed at parse time to decide the address form and the TLS flag, and is not carried forward. A pool may be configured with a single Endpoint or with several; when several are given, they are tried in order of precedence.

### Active failover
An ArangoDB deployment of several servers in which one is elected leader and the others follow. Only the leader admits a connection.

A follower refuses one, and which member leads is not fixed and changes without notice. A pool aimed at such a deployment is therefore given every member, and the ordered walk over Endpoints is how it finds the one currently admissible; naming a single member makes the outcome depend on an election the caller does not control. Removed by the server in 3.12, so a 3.11 concern only.

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
The resource-object operations under `Arangox.API.*` — one Elixir function per operation of ArangoDB's HTTP API, each reaching the network only through the Adapter. Spec-derived owned source: the functions were originally produced from ArangoDB's published OpenAPI document and are hand-maintained, with conformance to the server's own document enforced by the Conformance gate rather than by regeneration. That conformance covers the addresses an operation reaches and the parameters it names, not the values the operations put into them.

### Adapter
The single module (`Arangox.API.Client`) every API-surface operation calls, translating an operation's request map into a driver request. It is operation-agnostic — nothing in it is keyed to a specific operation — and it is the seam that keeps the surface transport-independent: a transport change touches the Adapter, never the operations.

A segment may declare that its value is a Composite path parameter, and the Adapter honours that declaration generically — it reads the shape an operation states, never the identity of the operation stating it.

### Composite path parameter
A path parameter whose value is itself a path — an ArangoDB index identifier is a collection name and a number joined by a separator — so it fills a single slot in a documented address but occupies more than one segment on the wire.

An operation declares such a parameter explicitly rather than the Adapter guessing at it. The Adapter then keeps the separators inside that value and encodes each part between them, so the value can add path depth but still cannot introduce a query or a fragment. An ordinary path parameter is the opposite: a separator inside it is data and is escaped like any other character, because a collection whose name contains one is a name and not structure. ArangoDB's API description writes both kinds the same way, so the Conformance gate cannot tell them apart; only calling the operation with a real value does.

### Forced parameter
A query parameter an operation always sends under a value it fixes itself, never offered to callers as an option.

The distinction from an offered parameter is a safety one, not a convenience one. Some parameters decide what an endpoint does rather than how it does it — one flag separates reading many documents from replacing a whole collection at the same address and method — so letting a caller supply a value is the hazard. Forcing it puts the decision in the operation's own source, where it can be read, rather than in the Adapter, which stays operation-agnostic. A parameter that is both forced and offered would hand the choice back, so the two sets never overlap.

### Conformance gate
The integration-tier test proving the API surface matches the Live oracle: operation addresses (compared as sets — the document describes one endpoint several times when it takes more than one body or returns more than one shape), query-parameter sets, request media, and required-parameter declarations. It asserts the server's version equals the driver's single pinned server version first, so the error table, the surface, and the test server always describe the same release.

Every dimension it compares is one the description states. Anything the description leaves unstated — the internal structure of a parameter's value among it — is outside its reach, so a green gate means the surface addresses the right endpoints under the right parameter names, not that a call works.

A second, server-free tier checks what can be read from the operation sources alone: that nothing reaches the network except through the Adapter, that addresses are built from literal segments and bare arguments rather than assembled as strings, that every operation has a delegating bang twin, and that no parameter is both forced and offered.

### Live oracle
The API description the tested server itself serves, used as the authority the Conformance gate checks the API surface against. Distinct from a vendored copy of the same description, which can drift from the server it claims to describe; the live oracle and the system under test cannot disagree about which release they are.

It is an authority on shape, not on behaviour: it states what an operation is called and what it accepts, never what the server does with a particular value. The same server's responses to real calls are a separate authority, and the only one that settles what an operation returns or whether it works at all.

## Testing

### Server line
One of the two ArangoDB releases the suite is exercised against, together with the compose services that run it: the 3.12 line (single servers, one of them with TLS, plus a three-coordinator cluster) and the 3.11 line (an active-failover trio, pinned there because VelocyStream and Active failover are 3.11-only concerns).

An integration test is tagged by the line whose service it reaches, never by the line whose feature it is about — a test about a 3.11 feature that connects to a 3.12 port belongs to the 3.12 line. The distinction is invisible where every line is running and decisive where one line is started at a time.

## Transactions

### Stream Transaction
A server-side ArangoDB transaction addressed by an identifier, so that individual requests — possibly on different connections — participate by carrying that identifier rather than by being bound to one connection.

The identifier is a bearer capability: whoever presents it acts inside the transaction, so it is redacted from inspection and logs like authentication material. It encodes the coordinator that issued it, and other coordinators forward participating requests there, which is what makes the transaction usable from any pooled connection. The server ends transactions on its own timeout, so a driver's local bookkeeping about whether one is running can be wrong in both directions; and a finished transaction remains queryable for a retention window, responding with its final status rather than disappearing.

## Flagged ambiguities

- "Timeout" had been used for both the pool's checkout deadline (how long a Caller will wait to obtain a connection, measured from when it entered the pool) and a request's own time budget at the socket. These are distinct, and the first is an absolute instant rather than a duration that can be reused for the second.
