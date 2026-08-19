# Arangox

[![Version](https://img.shields.io/hexpm/v/arangox.svg)](https://hex.pm/packages/arangox)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/arangox.svg)
[![CI](https://github.com/ArangoDB-Community/arangox/actions/workflows/elixir.yml/badge.svg?branch=master&event=push)](https://github.com/ArangoDB-Community/arangox/actions/workflows/elixir.yml)

An implementation of [DBConnection](https://hex.pm/packages/db_connection) for
[ArangoDB](https://www.arangodb.com).

Velocy and JSON over HTTP, the new AQL plan cache, a resource API covering ArangoDB's HTTP surface, and pools, transactions and cursors via [DBConnection](https://hex.pm/packages/db_connection).

[VelocyStream](https://github.com/arangodb/velocystream) and
[Active Failover](https://docs.arangodb.com/3.11/deploy/active-failover/)
remain for 3.11.

Supported:

- **ArangoDB** 3.11, 3.12
- **Elixir** 1.15+
- **OTP** 26+

## Examples

```elixir
iex> {:ok, conn} = Arangox.start_link(pool_size: 10)
iex> {:ok, %Arangox.Response{status: 200, body: %{"code" => 200, "error" => false, "mode" => "default"}}} = Arangox.get(conn, "/_admin/server/availability")
iex> {:error, %Arangox.Error{status: 404}} = Arangox.get(conn, "/invalid")
iex> %Arangox.Response{status: 200, body: %{"code" => 200, "error" => false, "mode" => "default"}} = Arangox.get!(conn, "/_admin/server/availability")
iex> {:ok,
iex>   %Arangox.Request{
iex>     body: "",
iex>     headers: [],
iex>     method: :get,
iex>     path: "/_admin/server/availability"
iex>   },
iex>   %Arangox.Response{
iex>     status: 200,
iex>     body: %{"code" => 200, "error" => false, "mode" => "default"}
iex>   }
iex> } = Arangox.request(conn, :get, "/_admin/server/availability")
iex> Arangox.transaction(conn, fn c ->
iex>   stream =
iex>     Arangox.cursor(
iex>       c,
iex>       "FOR i IN [1, 2, 3] FILTER i == 1 || i == @num RETURN i",
iex>       %{num: 2},
iex>       properties: [batchSize: 1]
iex>     )
iex>
iex>   Enum.reduce(stream, [], fn resp, acc ->
iex>     acc ++ resp.body["result"]
iex>   end)
iex> end)
{:ok, [1, 2]}
```

## Clients

### Velocy

Arangox can communicate with _ArangoDB_ 3.11 via _VelocyStream_ by setting `client: Arangox.VelocyClient`, which requires the `:velocy` library. ArangoDB removed VelocyStream in server 3.12, so this client only works against 3.11:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.8.0"},
    {:velocy, "~> 0.1.8"}
  ]
end
```

The default vst chunk size is `30_720`. It is a per-pool start option, so different pools can use different chunk sizes:

```elixir
Arangox.start_link(vst_maxsize: 12_345)
```

Setting it in `config/config.exs` still works in 0.8 and logs a deprecation warning once per pool. That fallback is removed in the next release:

```elixir
# deprecated, removed in the next release
config :arangox, :vst_maxsize, 12_345
```

### HTTP

Arangox ships two HTTP clients. `Arangox.MintClient` is the default and the one
this documentation assumes; `Arangox.GunClient` is below. Mint requires the
`:mint` library and a json library:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.8.0"},
    {:jason, "~> 1.4"},
    {:mint, "~> 1.9"}
  ]
end
```

```elixir
Arangox.start_link(client: Arangox.MintClient)
```

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.MintClient)
iex> {:ok, %Arangox.Response{status: 200, body: nil}} = Arangox.options(conn, "/")
```

HTTP/1.1 is the default on both schemes. HTTP/2 is available per pool, settled
by ALPN on TLS and asserted by prior knowledge on cleartext, which ArangoDB has
accepted since 3.7:

```elixir
Arangox.start_link(client_opts: [protocols: [:http2]])
```

It is offered rather than assumed for two reasons. **This client sends a
request body whole rather than streaming it**, and HTTP/2 flow-controls request
bodies, so one larger than the peer's window — ArangoDB advertises about 64 KiB
— is refused with `:exceeds_window_size` instead of waiting for a
`WINDOW_UPDATE`. A bulk insert or a large document sits above that, while
HTTP/1.1 has no flow control and carries bodies of any size. (`:gun` queues the
body and honours `WINDOW_UPDATE` itself, so `Arangox.GunClient` has no such
bound.) **And multiplexing is not exploited**:
`DBConnection` runs one in-flight request per pooled connection, so concurrency
comes from `:pool_size`, not from streams sharing a connection.

So today HTTP/2 costs a size bound and buys header compression on a driver
whose headers are four small fields. Both bounds lift with the transport
rework in 1.0, which is when it becomes worth defaulting to.

`Arangox.MintClient` supports unix domain sockets (`"http://unix:/tmp/arangodb.sock"`).

To use something else, you'd have to implement the `Arangox.Client` behaviour in a
module somewhere and set that instead.

The default json library is `Jason`. To use a different library, pass the `:json_library` start option.

```elixir
Arangox.start_link(json_library: Poison)
```

Setting it in `config/config.exs` still works in 0.8 and logs a deprecation warning once per pool. That fallback is removed in the next release:

```elixir
# deprecated, going away in the next release
config :arangox, :json_library, Poison
```

### Gun

`Arangox.GunClient` is the second HTTP client. It requires the `:gun` library
and a json library:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.8.0"},
    {:jason, "~> 1.4"},
    {:gun, "~> 2.0"}
  ]
end
```

```elixir
Arangox.start_link(client: Arangox.GunClient)
```

It speaks HTTP/1.1 and HTTP/2 over TCP, TLS and unix domain sockets. The
driver leaves protocol selection to `:gun`'s own defaults: HTTP/1.1 on
cleartext, and on TLS an ALPN offer of both protocols with HTTP/2 preferred.
Unlike the Mint client it has no request-body size bound under HTTP/2: `:gun`
queues the body and honours `WINDOW_UPDATE` itself. To assert HTTP/2 on
cleartext by prior knowledge:

```elixir
Arangox.start_link(client: Arangox.GunClient, client_opts: %{protocols: [:http2]})
```

Note the difference from the Mint example: `:gun` takes its options as a map
rather than a keyword list.

#### The cowlib advisories

`mix deps.get` reports `:cowlib` and `:gun` as vulnerable. This affects users of
`Arangox.GunClient` only — `:cowlib` reaches your application through `:gun`, and
a pool on `Arangox.MintClient` (the default) has neither in its tree.

Three advisories are open against `:cowlib`, all the same shape: an encoder that
does not reject the bytes its matching decoder already refuses. None has a
released fix — every one names 2.9.0 as introduced with no fixed version, and
2.19.0, the latest published, is affected. Two carry upstream fix commits that
have not been cut into a release.

None of them reaches code arangox uses. Check each yourself rather than take our
word:

| Advisory | Vulnerable function | Why it cannot fire here |
| --- | --- | --- |
| [CVE-2026-43966](https://osv.dev/vulnerability/EEF-CVE-2026-43966) | `cow_http_struct_hd:escape_string/2` — escapes only `\` and `"`, so CR and LF survive into an [RFC 8941](https://www.rfc-editor.org/rfc/rfc8941) *structured* header | Arangox builds no structured headers, and nothing in the dependency tree calls the function — its only callers are inside cowlib itself, serializing `Variants` (`cow_http_hd:variants/1`, `variant_key/1`) and WebTransport (`wt_protocol/1`, `wt_available_protocols/1`) headers. |
| [CVE-2026-43969](https://osv.dev/vulnerability/EEF-CVE-2026-43969) | `cow_cookie:cookie/1` — builds a `Cookie:` request header without validating names or values, admitting `;`, `,`, CR, LF and TAB | `:gun` does call this, from its cookie store. That store is opt-in: gun's `cookie_store` option defaults to `undefined`, and `gun_cookies:add_cookie_header/5` returns the headers untouched in that case. Arangox never sets it, so the call is unreachable unless you pass `client_opts: %{cookie_store: {Mod, State}}` yourself. |
| [CVE-2026-43971](https://osv.dev/vulnerability/EEF-CVE-2026-43971) | `cow_link:link/1` — interpolates a target URI, `rel` value and attribute keys into a `Link:` header with no escaping | Never called. Cowlib parses `Link:` headers (`cow_http_hd:parse_link/1`); nothing in the tree builds one. |

Two guards stand in front of all three, whatever cowlib does:

- Arangox validates every header on every request and connect probe. A name or
  value carrying a carriage return, line feed, or null is refused before any
  client sees it.
- `:gun` 2.4 and later raise on an outgoing request header containing CR or LF —
  its `invalid_request_headers` option defaults to `raise`. Arangox resolves
  `:gun` 2.5.0. (The GitHub copy of CVE-2026-43966 lists gun's fix as 2.16.0, a
  version `:gun` has never published, which is why that warning fires at all.)

`:cowboy` and `:cowlib` also appear in this repository's own test tooling.
Nothing there ships: the released package contains `lib/` only.

### VelocyPack bodies

An HTTP pool can carry its bodies as VelocyPack instead of JSON. It is a
per-pool opt-in that requires the optional `:velocy` dependency:

```elixir
Arangox.start_link(content_type: :velocypack)
```

Requests are encoded as VelocyPack with `content-type: application/x-velocypack`,
and the same is requested in return via `accept`. Responses are decoded by
*their own* content type, so a server that declines and answers JSON is still
read correctly, and a `content-type` or `accept` header on an individual
request wins over the pool's setting. `Arangox.VelocyClient` ignores the
option — VelocyStream carries its own encoding.

### Benchmarks

The `:content_type` start option selects the body codec, so what it changes is
measured at the codec: encode and decode cost, and encoded size, on
cursor-row-shaped documents. Median of 5 rounds, Elixir 1.19.4 / OTP 28 on an
Apple M1 Max. Reproduce with `mix run bench/content_type.exs`.

| Payload             | Codec      | Encode    | Decode    | Encoded size |
| ------------------- | ---------- | --------- | --------- | ------------ |
| 1 document          | JSON       | 2.08 µs   | 2.25 µs   | 247 B        |
| 1 document          | VelocyPack | 1.97 µs   | 2.19 µs   | 218 B        |
| 100-document batch  | JSON       | 203.32 µs | 224.96 µs | 25.1 KiB     |
| 100-document batch  | VelocyPack | 225.29 µs | 245.23 µs | 22.2 KiB     |
| 1000-document batch | JSON       | 2.78 ms   | 2.89 ms   | 259.1 KiB    |
| 1000-document batch | VelocyPack | 2.63 ms   | 2.42 ms   | 230.7 KiB    |

Codec speed is close to parity in both directions — which codec leads varies
with payload size by around ±10%. The consistent difference is size: VelocyPack
encodes the same documents about 11% smaller. Request latency against a live
server is dominated by the server and the network either way, so pick
`:content_type` for wire size and server-side preferences, not for client CPU.

## Queries and the plan cache

`Arangox.query/4` is the one-shot door to AQL, mapping snake_case options onto
the server's keys:

```elixir
{:ok, %Arangox.Response{body: %{"result" => [1, 2, 3]}}} =
  Arangox.query(conn, "FOR i IN 1..@n RETURN i", %{n: 3}, batch_size: 100)
```

ArangoDB has no prepared statements, so `DBConnection.prepare/2` is refused —
the error says so. What the server does have (3.12.4+) is an AQL execution-plan
cache, and it is an explicit opt-in per query:

```elixir
Arangox.query(conn, "FOR d IN docs RETURN d", %{}, use_plan_cache: true)
```

`Arangox.plan_cache/1` lists the cache's entries and
`Arangox.clear_plan_cache/1` empties it. Both are **database-wide
administrative operations** — the cache is shared by every application talking
to the database, not a per-pool resource.

Streamed cursors work through `DBConnection.stream/4` inside a transaction, as
in the example at the top.

## Transactions

Stream transactions are handle-based. `Arangox.begin_transaction/2` returns an
`%Arangox.Transaction{}` handle, and any request joins it by passing the
handle — on whichever pooled connection happens to serve that request:

```elixir
{:ok, trx} = Arangox.begin_transaction(conn, write: "products")
{:ok, _} = Arangox.post(conn, "/_api/document/products", %{a: 1}, [], transaction: trx)
{:ok, %Arangox.Response{}} = Arangox.commit_transaction(conn, trx)   # or Arangox.abort_transaction/2
```

The handle's identifier is a **bearer capability**: anyone who can reach the
deployment and holds it can commit, abort, or write into the transaction. Do
not log it or let it cross a trust boundary — `inspect/1` redacts it for
exactly that reason.

`Arangox.transaction/3` remains as the block form built on the same mechanics,
committing on return and aborting if the function raises or exits (see the
example at the top).

## Resource API

Every operation in ArangoDB's HTTP API is available as a typed function under
`Arangox.Api.*` — 243 operations across 22 modules, one per API tag:

```elixir
{:ok, %Arangox.Response{body: body}} =
  Arangox.Api.Collections.create_collection("mydb", %{name: "products"}, conn: conn)

{:ok, %Arangox.Response{}} =
  Arangox.Api.Documents.get_document("mydb", "products", key,
    conn: conn,
    transaction: trx
  )
```

Every `Arangox.Api` call runs through the driver's pool and carries its error
contract and per-request options (`:database`, `:transaction`, `:timeout`).
The function signatures do not expose the API's header parameters: pass
revision preconditions such as `if-match` and `if-none-match` through
`headers:`, and join a stream transaction with `transaction:` rather than an
`x-arango-trx-id` header. Reading several documents by key in one request is
`Arangox.Api.Documents.get_documents/4`, which always sends `onlyget=true` —
the flag the server uses to tell that read apart from a bulk replace on the
same URL.

This surface is spec-derived but owned: hand-maintained source, verified by
the integration test suite against the OpenAPI document the tested server
itself serves, operation by operation. The raw request functions
(`Arangox.get/4`, `Arangox.post/5`, ...) remain available and supported; the
resource layer is an addition, not a replacement.

## Start Options

Arangox assumes a default for the `:endpoints` option, and
[`db_connection`](https://hex.pm/packages/db_connection) assumes a default
`:pool_size` of `1`, so the following:

```elixir
Arangox.start_link()
```

Is equivalent to:

```elixir
options = [
  endpoints: "http://localhost:8529",
  pool_size: 1
]
Arangox.start_link(options)
```

## Endpoints

Unencrypted endpoints can be specified with either `http://` or
`tcp://`, whereas encrypted endpoints can be specified with `https://`,
`ssl://` or `tls://`:

```elixir
"tcp://localhost:8529" == "http://localhost:8529"
"https://localhost:8529" == "ssl://localhost:8529" == "tls://localhost:8529"

"tcp+unix:///tmp/arangodb.sock" == "http+unix:///tmp/arangodb.sock"
"https+unix:///tmp/arangodb.sock" == "ssl+unix:///tmp/arangodb.sock" == "tls+unix:///tmp/arangodb.sock"

"tcp://unix:/tmp/arangodb.sock" == "http://unix:/tmp/arangodb.sock"
"https://unix:/tmp/arangodb.sock" == "ssl://unix:/tmp/arangodb.sock" == "tls://unix:/tmp/arangodb.sock"
```

The `:endpoints` option accepts either a binary, or a list of binaries. In the case of a list,
Arangox will try to establish a connection with the first endpoint it can.

If a connection is established, the availability of the server will be checked (via the _ArangoDB_ api), and
if an endpoint is in maintenance mode or is a _Follower_ in an _Active Failover_ setup, the connection
will be dropped, or in the case of a list, the endpoint skipped.

Active failover is a 3.11 topology, but the endpoint walk is not: against a
3.12 cluster, listing several coordinators gives each pooled connection a
working coordinator even when one is down or draining — the walk skips
whatever does not answer.

With the `:read_only?` option set to `true`, arangox will try to find a server in
_readonly_ mode instead and add the _x-arango-allow-dirty-read_ header to every request:

```elixir
iex> endpoints = ["http://localhost:8003", "http://localhost:8004", "http://localhost:8005"]
iex> {:ok, conn} = Arangox.start_link(endpoints: endpoints, auth: {:basic, "root", ""}, read_only?: true)
iex> %Arangox.Response{body: body} = Arangox.get!(conn, "/_admin/server/mode")
iex> body["mode"]
"readonly"
iex> {:error, %Arangox.Error{status: 403}} = Arangox.post(conn, "/_api/database", %{name: "newDatabase"})
```

## Authentication

### Velocy

ArangoDB's VelocyStream endpoints _do not_ read authorization headers, authentication configuration _must_ be 
provided as options to `Arangox.start_link/1`. 

As a consequence, if you're using bearer auth, there are a couple of caveats to bear in mind:

* New JWT tokens can only be requested in a seperate connection (i.e. during startup before the primary pool
is initialized)
* Refreshed tokens can only be authorized by restarting a connection pool

### HTTP

When using an HTTP client, Arangox will generate a _Basic_ or _Bearer_ authorization header if the `:auth` option is set to `{:basic, username, password}` or to `{:bearer, token}` respectively, and append it to every request. If the `:auth` option is not explicitly set, no authorization header will be appended.

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.MintClient, endpoints: "http://localhost:8001")
iex> {:error, %Arangox.Error{status: 401}} = Arangox.get(conn, "/_admin/server/mode")
```

The header value is obfuscated in transfomed requests returned by arangox, for obvious reasons:

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.MintClient, auth: {:basic, "root", ""})
iex> {:ok, request, _response} = Arangox.request(conn, :options, "/")
iex> request.headers
[{"authorization", "[redacted]"}]
```

## Databases

### Velocy

If the `:database` option is set, it can be overridden by prepending the path of a
request with `/_db/:value`. If nothing is set, the request will be sent as-is and
_ArangoDB_ will assume the `_system` database.

### HTTP

When using an HTTP client, arangox will prepend `/_db/:value` to the path of every request
only if one isn't already prepended. If a `:database` option is not set, nothing is prepended.

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.MintClient)
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_admin/time")
iex> request.path
"/_admin/time"
iex> {:ok, conn} = Arangox.start_link(database: "_system", client: Arangox.MintClient)
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_admin/time")
iex> request.path
"/_db/_system/_admin/time"
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_db/_system/_admin/time")
iex> request.path
"/_db/_system/_admin/time"
```

## Headers

Since 0.8, request headers are lists of `{name, value}` string tuples, and only
that — maps are no longer accepted, at the `:headers` start option or on a
request:

```elixir
[{"header", "value"}]
```

The driver sends them in a fixed order and otherwise leaves them alone:

1. the pool's `:headers`, in the order given (with the authorization header
   the `:auth` option resolves to, and the dirty-read header of a
   `read_only?: true` pool, appended at connect),
2. the stream-transaction header, when one applies (see below),
3. the request's own headers, in the order given,
4. a `content-type` label when the driver encoded the body as VelocyPack, and
   the `accept` header of a VelocyPack pool — each appended only when no
   header of that name, in any casing, is present anywhere above.

Nothing is merged, deduplicated, renamed or re-cased. A request header does
not *replace* a same-named pool header — both go on the wire, request's last:

```elixir
iex> {:ok, conn} = Arangox.start_link(headers: [{"header", "value"}])
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_api/version", "", [{"header", "new_value"}])
iex> {"header", "value"} in request.headers
true
iex> {"header", "new_value"} in request.headers
true
```

Send the same name twice and it is sent twice. HTTP allows that only for
list-valued headers, and what a server makes of an unexpected repeat is the
server's policy — the driver neither prevents nor repairs it.

The quirks worth knowing, per client:

  * `Arangox.MintClient` lowercases header *names* on the wire (HTTP/2
    requires lowercase; Mint applies the same to HTTP/1.1). Values are
    untouched.
  * `Arangox.GunClient` sends names as given.
  * `Arangox.VelocyClient` (deprecated) speaks VelocyStream, whose wire format
    carries headers as a map: it cannot express a repeated name, so the
    right-most occurrence wins and the others are dropped. Casing is
    preserved.

The codec for a request body is selected from the request's *own* headers —
the first `content-type` entry, any casing, parameters ignored — falling back
to the pool's `:content_type` option. A `content-type` placed in the pool's
`:headers` list rides the wire but never selects the codec, so it can label an
encoded body wrongly: configure the pool codec with `:content_type`, not
through `:headers`.

A request joins a stream transaction through exactly one `x-arango-trx-id`
header, supplied by the `:transaction` option or by the in-flight
`Arangox.transaction/3` on that connection — the option outranks the
connection's. A request whose own headers already name that header, in any
casing, runs under its own value alone; the driver adds nothing next to it.

Response headers come back the same shape: a list of `{name, value}` tuples on
`Arangox.Response`. The HTTP clients hand the parsed lines through — names
lowercased, order and repeats as the server sent them. The VelocyStream client
is different by wire format: VelocyStream carries response headers as a map,
so its list can hold no repeated name, its order is the map's key order rather
than the server's, and names keep the server's casing.

## Transport

The `:connect_timeout` start option defaults to `5_000`.

Transport options can be specified via `:tcp_opts` and `:ssl_opts`, for unencrypted and
encrypted connections respectively. When using `:gun` or `:mint`, these options are passed
directly to the `:transport_opts` connect option.

See [`:gen_tcp.connect_option()`](http://erlang.org/doc/man/gen_tcp.html#type-connect_option)
for more information on `:tcp_opts`,
or [`:ssl.tls_client_option()`](http://erlang.org/doc/man/ssl.html#type-tls_client_option) for `:ssl_opts`.

The `:client_opts` option can be used to pass client-specific options to `:gun` or `:mint`.
These options are merged with and may override values set by arangox. Some options cannot be
overridden (i.e. `:mint`'s `:mode` option). If `:transport_opts` is set here it will override
everything given to `:tcp_opts` or `:ssl_opts`, regardless of whether or not a connection is
encrypted.

See the `gun:opts()` type in the [gun docs](https://ninenines.eu/docs/en/gun/2.1/manual/gun/)
or [`connect/4`](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4) in the mint docs for more
information.

## Request Options

Request options are handled by and passed directly to `:db_connection`.
See [execute/4](https://hexdocs.pm/db_connection/DBConnection.html#execute/4) in the `:db_connection` docs for supported
options.

Request timeouts default to `15_000`.

```elixir
iex> {:ok, conn} = Arangox.start_link()
iex> %Arangox.Response{status: 200, body: %{"code" => 200, "error" => false, "mode" => "default"}} = Arangox.get!(conn, "/_admin/server/availability", [], timeout: 15_000)
```

## Contributing

The unit and protocol tiers need no containers; the integration tier runs
against the compose stack:

```
mix format
mix test
docker compose up --detach --wait
mix test.integration
```

## Roadmap

- **1.0**: replace the `DBConnection` foundation with `http_connection`,
  which is what unlocks HTTP/2 multiplexing. The 0.x API is the stability
  promise; 1.0 is reserved for that swap.
- **The next release**: remove the deprecated application-config fallbacks
  (`:json_library`, `:vst_maxsize`) and their reader functions.
- An Ecto adapter remains under consideration.
