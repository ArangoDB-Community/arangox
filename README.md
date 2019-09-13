# Arangox

[![Build Status](https://travis-ci.org/suazithustra/arangox.svg?branch=master)](https://travis-ci.org/suazithustra/arangox)

An implementation of [`db_connection`](https://hex.pm/packages/db_connection)
for _ArangoDB_, which is silly because _ArangoDB_ is not a transactional database (i.e.
no prepare, commit, rollback, etc.), but whatever, it's a solid connection pooler.

Tested on:

- ArangoDB 3.3.9 - 3.5
- Elixir 1.6 - 1.9
- OTP 20 - 22

Supports [active failover](https://www.arangodb.com/docs/stable/architecture-deployment-modes-active-failover-architecture.html).

### Peer Dependencies

Arangox requires a json library and http client to work, the defaults are `:jason` and
`:gun`:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.1.0"},
    {:jason, "~> 1.1"},
    {:gun, "~> 1.3"}
  ]
end
```

You _might_ need to add `:gun` as an extra application in `mix.exs`:

```elixir
def application() do
  [
    extra_applications: [:logger, :gun])
  ]
end
```

To use a different json library, set the `:json_library` config to the module of your
choice:

```elixir
config :arangox, :json_library, Poison
```

Arangox already has a `Mint` client. To use it, add `:mint` to your deps instead of
`:gun` and set the `:client` start option to `Arangox.Client.Mint`:

```elixir
Arangox.start_link(client: Arangox.Client.Mint)
```

To use something else, you'd have to implement the `Arangox.Client` behaviour in a
module somewhere and set that instead. The `Arangox.Endpoint` module has utilities
for parsing _ArangoDB_ endpoints.

### Examples

```elixir
iex> {:ok, conn} = Arangox.start_link(pool_size: 10)
iex> Arangox.request(conn, :options, "/")
{:ok,
 %Arangox.Request{
   body: "",
   headers: [{"authorization", "..."}],
   method: :options,
   path: "/"
 },
 %Arangox.Response{
   body: nil,
   headers: [
     {"x-content-type-options", "nosniff"},
     {"allow", "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT"},
     {"server", "ArangoDB"},
     {"connection", "Keep-Alive"},
     {"content-type", "text/plain; charset=utf-8"},
     {"content-length", "0"}
   ],
   status: 200
 }}
iex> Arangox.options!(conn)
%Arangox.Response{
  body: nil,
  headers: [
    {"x-content-type-options", "nosniff"},
    {"allow", "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT"},
    {"server", "ArangoDB"},
    {"connection", "Keep-Alive"},
    {"content-type", "text/plain; charset=utf-8"},
    {"content-length", "0"}
  ],
  status: 200
}
```

## Options

Arangox assumes defaults for the `:endpoints`, `:username` and `:password` options,
and [`db_connection`](https://hex.pm/packages/db_connection) assumes a default
`:pool_size` of `1` so the following:

```elixir
Arangox.start_link()
```

Is equivalent to:

```elixir
options = [
  pool_size: 1,
  endpoints: ["http://localhost:8529"],
  username: "root",
  password: ""
]
Arangox.start_link(options)
```

### Endpoints

See the
[arangosh](https://www.arangodb.com/docs/stable/programs-arangosh-examples.html) or
[arangojs](https://www.arangodb.com/docs/stable/drivers/js-reference-database.html)
documentation for examples of supported endpoint formats.

As is common amongst _ArangoDB_ drivers, arangox takes a list of endpoints as binaries:

```elixir
endpoints = [
  "http://localhost:8529",
  "http://localhost:8530",
  "http://localhost:8531"
]
Arangox.start_link(endpoints: endpoints)
```

Arangox will try to establish a connection with the first endpoint it can and
check it's availability (via the _ArangoDB_ api). If an endpoint is in maintenance mode
or is a follower in an _active failover_ setup, it will be skipped.

With the `read_only?` option set to `true`, arangox will try to find a server in
_readonly_ mode instead and add the _x-arango-allow-dirty-read_ header to every request:

```elixir
iex> endpoints = ["http://localhost:8003", "http://localhost:8004", "http://localhost:8005"]
iex> {:ok, conn} = Arangox.start_link(endpoints: endpoints, read_only?: true)
iex> %Arangox.Response{body: body} = Arangox.get!(conn, "/_admin/server/mode")
iex> body["mode"]
"readonly"
iex> {:error, exception} = Arangox.post(conn, "/_api/database", %{name: "newDatabase"})
iex> exception.message
"forbidden"
```

### Authentication

Arangox will generate an authorization header with the `:username` and `:password`
options and add it to every request. To prevent this behavior, set the `:auth?`
option to `false`.

```elixir
iex> {:ok, conn} = Arangox.start_link(auth?: false)
iex> {:error, exception} = Arangox.get(conn, "/_admin/server/mode")
iex> exception.message
"not authorized to execute this request"
```

The header value is obfuscated in transfomed requests returned by arangox, for
obvious reasons:

```elixir
iex> {:ok, conn} = Arangox.start_link()
iex> {:ok, request, _response} = Arangox.options(conn)
iex> request.headers
[{"authorization", "..."}]
```

### Databases

If a value is given to the `:database` option, arangox will prepend `/_db/:value`
to the path of every request that isn't already prepended. If a value is not given,
nothing is prepended (_ArangoDB_ will assume the `_system` database).

```elixir
iex> {:ok, conn} = Arangox.start_link()
iex> {:ok, request, _response} = Arangox.get(conn, "/_admin/time")
iex> request.path
"/_admin/time"
iex> {:ok, conn} = Arangox.start_link(database: "myDatabase")
iex> {:ok, request, _response} = Arangox.get(conn, "/_admin/time")
iex> request.path
"/_db/myDatabase/_admin/time"
iex> {:ok, request, _response} = Arangox.get(conn, "/_db/anotherDatabase/_admin/time")
iex> request.path
"/_db/anotherDatabase/_admin/time"
```

### Headers

Headers are given as lists of two-element tuples:

```elixir
[{"header", "value"}, {"another-header", "another-value"}]
```

When given to the start option they are merged with every request.

```elixir
iex> {:ok, conn} = Arangox.start_link(headers: [{"header", "value"}])
iex> {:ok, request, _response} = Arangox.options(conn)
iex> request.headers
[{"authorization", "..."}, {"header", "value"}]
```

Headers can also be passed as an argument to any request:

```elixir
iex> {:ok, conn} = Arangox.start_link()
iex> {:ok, request, _response} = Arangox.get(conn, "/_admin/time", [{"header", "value"}])
iex> request.headers
[{"header", "value"}, {"authorization", "..."}]
```

Headers given to the start option will not override any of the headers set by Arangox,
but headers passed to requests will.

### Transport

Transport options can be specified via `:tcp_opts` and `:ssl_opts`, for non-encrypted and
encrypted connections respectively. These options are passed directly to the `:transport_opts`
option of `:gun` or `Mint`.

See [`:gen_tcp.connect_option()`](http://erlang.org/doc/man/gen_tcp.html#type-connect_option)
for more information on `:tcp_opts`, or [`:ssl.tls_client_option()`](http://erlang.org/doc/man/ssl.html#type-tls_client_option) for `:ssl_opts`.

The `:client_opts` option can be used to pass client-specific options to `:gun` or `Mint`.
These options are merged with and may override values set by arangox. Some options  cannot be
overridden (i.e. `Mint`'s `:mode` option). If `:transport_opts` is set here it will override
everything given to `:tcp_opts` or `:ssl_opts`, regardless of whether or not a connection is
encrypted.

See the `gun:opts()` type in the [gun docs](https://ninenines.eu/docs/en/gun/1.3/manual/gun/)
or [`connect/4`](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4) in the mint docs for more
information.

## Contributing

```
mix do format, credo
docker-compose up -d
mix test
```

## Roadmap

- A VelocyStream client
- An Ecto adapter
- More descriptive logs

If anyone would like to collaborate, find me on the `elixir-lang` or `arangodb-community` slack.