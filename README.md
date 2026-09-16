# Arangox

[![Hex.pm](https://img.shields.io/hexpm/v/arangox.svg)](https://hex.pm/packages/arangox)
[![Documentation](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/arangox)
[![CI](https://github.com/ArangoDB-Community/arangox/actions/workflows/elixir.yml/badge.svg?branch=main&event=push)](https://github.com/ArangoDB-Community/arangox/actions/workflows/elixir.yml)

Arangox is a pooled Elixir driver for ArangoDB. It gives you a conventional
resource API for everyday work, first-class AQL queries and transactions, and
raw access to the HTTP API when you need it.

```elixir
alias Arangox.API.{Collections, Documents}

{:ok, _collection} = Collections.create(db, %{name: "products"})
{:ok, created} = Documents.create(db, "products", %{name: "Keyboard"})
{:ok, product} = Documents.get(db, "products", created["_key"])
```

Arangox 0.8 supports:

- ArangoDB 3.11 and 3.12
- Elixir 1.15 and later
- OTP 26 and later
- HTTP through Mint by default
- HTTP through Gun as an alternative
- VelocyStream for backward compatibility with ArangoDB 3.11 deployments

## Getting Started

Add Arangox, Mint, and a JSON library to `mix.exs`:

```elixir
def deps do
  [
    {:arangox, "~> 0.8.0"},
    {:jason, "~> 1.4"},
    {:mint, "~> 1.9"}
  ]
end
```

Mint and Jason are optional dependencies so applications can
choose another transport or codec. Add them explicitly when using the default
setup shown here.

For a local server on ArangoDB's default port:

```elixir
{:ok, db} =
  Arangox.start_link(
    endpoints: "http://localhost:8529",
    database: "store",
    auth: {:basic, "root", ""}
  )
```

`Arangox.start_link/1` starts a `DBConnection` pool. The defaults are
`http://localhost:8529` and a pool size of 10, so a local server without
authentication needs only:

```elixir
{:ok, db} = Arangox.start_link()
```

In an application, put the pool under your supervision tree and give it a
stable name:

```elixir
children = [
  {Arangox,
   name: MyApp.Arango,
   endpoints: System.fetch_env!("ARANGODB_URL"),
   database: System.fetch_env!("ARANGODB_DATABASE"),
   auth:
     {:basic, System.fetch_env!("ARANGODB_USER"),
      System.fetch_env!("ARANGODB_PASSWORD")}}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

Calls can now use `MyApp.Arango` anywhere they would use the `db` value from
`start_link/1`.

## Resrouce API

The modules under `Arangox.API` cover ArangoDB's HTTP surface: 230 operations
across 22 resource modules. The pool is always the first argument, followed by
path parameters, a request body when the operation needs one, and options.

Here is a complete document lifecycle:

```elixir
alias Arangox.API.{Collections, Documents}

{:ok, _collection} =
  Collections.create(MyApp.Arango, %{
    name: "products",
    type: 2
  })

{:ok, created} =
  Documents.create(
    MyApp.Arango,
    "products",
    %{name: "Mechanical keyboard", price_cents: 12_900, in_stock: true},
    return_new: true
  )

key = created["_key"]

{:ok, product} = Documents.get(MyApp.Arango, "products", key)

{:ok, updated} =
  Documents.update(
    MyApp.Arango,
    "products",
    key,
    %{in_stock: false},
    return_new: true
  )

{:ok, _deleted} = Documents.delete(MyApp.Arango, "products", key)
```

Operation options use Elixir names. For example, `return_new: true` is sent as
ArangoDB's `returnNew=true`. Every operation also accepts:

- `:database` to override the pool's database for that call
- `:headers` as a list of `{name, value}` tuples
- `:transaction` with an `%Arangox.Transaction{}` handle
- `:timeout` for the caller's complete time budget
- `:request_timeout` for the maximum time spent waiting on the socket

Resource operations return the decoded response body:

```elixir
case Documents.get(MyApp.Arango, "products", key) do
  {:ok, product} ->
    {:found, product}

  {:error, %Arangox.Error{reason: :arango_document_not_found}} ->
    :not_found

  {:error, %Arangox.Error{} = error} ->
    {:failed, error}
end
```

Every operation has a bang form when raising is the clearer control flow:

```elixir
product = Documents.get!(MyApp.Arango, "products", key)
```

Useful starting points include:

- `Arangox.API.Collections` and `Arangox.API.Documents`
- `Arangox.API.Graphs`, `Arangox.API.Views`, and `Arangox.API.Indexes`
- `Arangox.API.Queries` and `Arangox.API.Transactions`
- `Arangox.API.Databases`, `Arangox.API.Users`, and `Arangox.API.Administration`

See the [HexDocs API reference](https://hexdocs.pm/arangox/api-reference.html)
for the complete surface.

## AQL Queries

Use `Arangox.query/4` when AQL is the natural interface. Bind variables stay
separate from the statement, and query options use snake_case names:

```elixir
{:ok, %Arangox.Response{body: %{"result" => products}}} =
  Arangox.query(
    MyApp.Arango,
    """
    FOR product IN products
      FILTER product.price_cents <= @maximum
      SORT product.price_cents ASC
      RETURN product
    """,
    %{maximum: 15_000},
    batch_size: 100
  )
```

ArangoDB has no prepared statements. On ArangoDB 3.12.4 and later, opt into
its server-side AQL plan cache when repeatedly executing eligible query text:

```elixir
Arangox.query(
  MyApp.Arango,
  "FOR product IN products FILTER product._key == @key RETURN product",
  %{key: key},
  use_plan_cache: true
)
```

`Arangox.plan_cache/1` lists the current database's cached plans and
`Arangox.clear_plan_cache/1` clears all of them. Both operations affect the
whole database, not only this pool.

For large results, stream cursor batches inside `Arangox.run/3` or
`Arangox.transaction/3`:

```elixir
{:ok, names} =
  Arangox.transaction(MyApp.Arango, fn conn ->
    conn
    |> Arangox.cursor(
      "FOR product IN products SORT product.name RETURN product.name",
      %{},
      batch_size: 100
    )
    |> Stream.flat_map(fn response -> response.body["result"] end)
    |> Enum.to_list()
  end, read: "products")
```

## Transactions

For work that fits naturally in one function, use the block form. Returning
commits the transaction; `Arangox.abort/2`, an exception, or an exit rolls it
back.

```elixir
alias Arangox.API.Documents

Arangox.transaction(MyApp.Arango, fn conn ->
    case Documents.update(conn, "accounts", from_key, %{active: false}) do
      {:ok, source} -> source
      {:error, error} -> Arangox.abort(conn, error)
    end
  end, write: "accounts"
)
```

For a transaction that must span separate calls, use a handle:

```elixir
{:ok, transaction} =
  Arangox.begin_transaction(MyApp.Arango, write: "products")

{:ok, _product} =
  Arangox.API.Documents.update(
    MyApp.Arango,
    "products",
    key,
    %{in_stock: true},
    transaction: transaction
  )

{:ok, %Arangox.Response{}} =
  Arangox.commit_transaction(MyApp.Arango, transaction)

# or

{:ok, %Arangox.Response{}} =
  Arangox.abort_transaction(MyApp.Arango, transaction)
```

## HTTP Primitives

Arangox exposes low-level HTTP primitives for
unsupported or custom endpoints, Foxx services, etc:

```elixir
{:ok, %Arangox.Response{status: 200, body: version}} =
  Arangox.get(MyApp.Arango, "/_api/version")

{:ok, %Arangox.Response{}} =
  Arangox.post(
    MyApp.Arango,
    "/_db/mydb/myservice/reindex",
    %{full: true}
  )
```

## Configuration

The options most applications need are:

| Option | Purpose | Default |
| --- | --- | --- |
| `:endpoints` | One endpoint or an ordered failover list | `"http://localhost:8529"` |
| `:database` | Database prepended to database-scoped requests | Server default |
| `:auth` | `{:basic, user, password}` or `{:bearer, token}` | No authentication |
| `:pool_size` | Number of concurrently usable connections | `10` |
| `:headers` | Headers sent with every request | `[]` |
| `:connect_timeout` | Budget for each connection attempt | `5_000` ms |
| `:request_timeout` | Per-request socket-wait ceiling | `15_000` ms |
| `:max_body_size` | Largest response body accepted for decoding | 128 MiB |
| `:content_type` | HTTP request-body codec | `:json` |
| `:client` | Transport implementation | `Arangox.MintClient` |

The pool also accepts standard `DBConnection` start options.

### Socket and transport options

Three options carry settings through to the socket and to the transport
library. Which one you want depends on who reads it:

| Option | Goes to | Read when |
| --- | --- | --- |
| `:tcp_opts` | Erlang's `:gen_tcp` | The endpoint is cleartext — `http://`, `tcp://`, or a Unix socket |
| `:ssl_opts` | Erlang's `:ssl` | The endpoint is encrypted — `https://`, `ssl://`, or `tls://` |
| `:client_opts` | The transport library itself | Always |

An option is read only when an endpoint's scheme matches, so `:ssl_opts`
behind an `http://` endpoint never reaches a socket. Arangox warns at pool
start when you pass an option no configured endpoint can read. An endpoint
list may mix schemes, in which case both socket options are live and each
applies to the endpoints it matches.

`:ssl_opts` also accepts plain socket options. Erlang's `:ssl` forwards what
it does not recognise to `:gen_tcp`, so one list can carry both:

```elixir
Arangox.start_link(
  endpoints: "https://db.example.com:8529",
  ssl_opts: [cacertfile: "/etc/my_app/ca.pem", nodelay: true]
)
```

`:client_opts` takes the shape the library itself takes — a keyword list for
Mint, a map for Gun. Each client's documentation says what it accepts and how
it combines with the two socket options. Both HTTP clients merge it per key,
so setting one transport option does not discard the rest.

### Deadlines and retries

`:timeout` is the caller's total budget, beginning before it queues for a pool
connection. `:request_timeout` is a ceiling on the socket wait. Arangox uses
whichever limit expires first.

A request that times out after being written retires its connection and is not
automatically retried. Retrying a write is an application decision because the
server may already have applied it.

### Multiple endpoints

Pass an ordered endpoint list to let each pooled connection find an available
server:

```elixir
Arangox.start_link(
  endpoints: [
    "https://coordinator-1.example.com:8529",
    "https://coordinator-2.example.com:8529"
  ],
  auth: {:bearer, token}
)
```

Arangox checks availability before admitting a connection. In ArangoDB 3.11
active-failover deployments, leader redirects are accepted only when the
target is already configured or explicitly admitted by `:endpoint_mapper`.

## Choose a transport

Most applications should keep the default Mint client.

| Client | Protocols | Server support | Additional dependency |
| --- | --- | --- | --- |
| `Arangox.MintClient` | HTTP/1.1 by default; optional HTTP/2 | ArangoDB 3.11 and 3.12 | `{:mint, "~> 1.9"}` |
| `Arangox.GunClient` | HTTP/1.1 and HTTP/2 | ArangoDB 3.11 and 3.12 | `{:gun, "~> 2.0"}` |
| `Arangox.VelocyClient` | VelocyStream | ArangoDB 3.11 only | `{:velocy, "~> 0.2"}` |

Select another client per pool:

```elixir
Arangox.start_link(client: Arangox.GunClient)
```

Mint's HTTP/2 mode is explicit:

```elixir
Arangox.start_link(client_opts: [protocols: [:http2]])
```

The Mint client sends request bodies whole. Under HTTP/2, a body larger than
the peer's flow-control window is rejected instead of streamed; ArangoDB
typically advertises roughly 64 KiB. Keep Mint on its default HTTP/1.1 for
large documents and bulk writes, or choose Gun. Because Arangox 0.8 is built
on `DBConnection`, HTTP/2 does not yet multiplex concurrent requests on one
connection; concurrency still comes from `:pool_size`.

HTTP pools can encode bodies as VelocyPack independently of the transport:

```elixir
Arangox.start_link(content_type: :velocypack)
```

This requires the optional `:velocy` dependency. Responses are decoded from
their own content type, so JSON responses still work.

## Security defaults

- TLS verifies certificates and hostnames using the system trust store.
- Credentials on a non-loopback cleartext endpoint are refused unless you
  explicitly pass `allow_cleartext_auth: true`.
- Authorization and transaction header values are redacted from returned
  requests, inspected state, and errors.
- Header names and values containing carriage returns, line feeds, or nulls
  are rejected before reaching a transport.
- Response bodies larger than `:max_body_size` are rejected before decoding.

If a private certificate authority signs your ArangoDB certificate, provide
its CA file rather than disabling verification:

```elixir
Arangox.start_link(
  endpoints: "https://db.example.com:8529",
  ssl_opts: [cacertfile: "/etc/my_app/arangodb-ca.pem"]
)
```

## Errors

Arangox reports driver, transport, and server failures with one structure:
`%Arangox.Error{}`.

- `:reason` is the stable atom to pattern-match on.
- `:status` is the HTTP status when the server responded.
- `:error_num` is ArangoDB's numeric error code when present.
- `:endpoint` is redacted.
- `:message` is for people and logs, not branching.

```elixir
case Arangox.API.Documents.get(MyApp.Arango, "products", key) do
  {:ok, document} -> document
  {:error, %Arangox.Error{reason: :arango_conflict}} -> retry_update()
  {:error, %Arangox.Error{} = error} -> raise error
end
```

## Upgrading from 0.7

Version 0.8 modernizes the transport and public contracts. In particular,
Mint is now the default client, TLS verification is enabled, headers are
ordered `{name, value}` lists, and stream transactions use
`%Arangox.Transaction{}` handles.

Read the complete [0.8 migration guide](CHANGELOG.md) — the "Migrating from
v0.7" section — before upgrading an existing application.

## Development

Unit and protocol tests run without Docker:

```console
mix deps.get
mix format --check-formatted
mix test
```

The integration suite uses the services in `docker-compose.yml`:

```console
docker compose up --detach --wait
mix test.integration
```

## Documentation

- [HexDocs](https://hexdocs.pm/arangox)
- [Changelog](CHANGELOG.md)
- [ArangoDB documentation](https://docs.arangodb.com/)
- [`DBConnection` documentation](https://hexdocs.pm/db_connection/)

## License

Arangox is released under the [MIT License](LICENSE).
