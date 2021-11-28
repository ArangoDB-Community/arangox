# Arangox

[![Build Status](https://travis-ci.com/ArangoDB-Community/arangox.svg?branch=master)](https://travis-ci.com/ArangoDB-Community/arangox)

An implementation of [`DBConnection`](https://hex.pm/packages/db_connection) for
[ArangoDB](https://www.arangodb.com).

Supports [VelocyStream](https://www.arangodb.com/2017/08/velocystream-async-binary-protocol/),
[active failover](https://www.arangodb.com/docs/stable/architecture-deployment-modes-active-failover-architecture.html), transactions and streamed cursors.

Tested on:

- **ArangoDB** 3.4 - 3.8
- **Elixir** 1.6 - 1.12
- **OTP** 20 - 24

[Documentation](https://hexdocs.pm/arangox/readme.html)

## Examples

```elixir
iex> {:ok, conn} = Arangox.start_link(pool_size: 10)
iex> Arangox.get(conn, "/_admin/server/availability")
{:ok,
 %Arangox.Response{
  body: %{"code" => 200, "error" => false, "mode" => "default"},
  headers: %{},
  status: 200
}}
iex> Arangox.get(conn, "/invalid")
{:error,
 %Arangox.Error{
   endpoint: "http://localhost:8529",
   error_num: 404,
   message: "unknown path '/invalid'",
   status: 404
 }}
iex> Arangox.get!(conn, "/_admin/server/availability")
%Arangox.Response{
  body: %{"code" => 200, "error" => false, "mode" => "default"},
  headers: %{},
  status: 200
}
iex> Arangox.request(conn, :get, "/_admin/server/availability")
{:ok,
 %Arangox.Request{
   body: "",
   headers: %{},
   method: :get,
   path: "/_admin/server/availability"
 },
 %Arangox.Response{
   body: %{"code" => 200, "error" => false, "mode" => "default"},
   headers: %{},
   status: 200
 }}
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

By default, Arangox communicates with _ArangoDB_ via _VelocyStream_, which requires the `:velocy` library:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.4.0"},
    {:velocy, "~> 0.1"}
  ]
end
```

The default vst chunk size is `30_720`. To change it, you can include the following in your `config/config.exs`:

```elixir
config :arangox, :vst_maxsize, 12_345
```

### HTTP

Arangox has two HTTP clients, `Arangox.GunClient` and `Arangox.MintClient`, they require a json library:

```elixir
def deps do
  [
    ...
    {:arangox, "~> 0.4.0"},
    {:jason, "~> 1.1"},
    {:gun, "~> 1.3.0"} # or {:mint, "~> 0.4.0"}
  ]
end
```

```elixir
Arangox.start_link(client: Arangox.GunClient) # or Arangox.MintClient
```

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.GunClient)
iex> Arangox.options(conn, "/")
{:ok,
 %Arangox.Response{
   body: nil,
   headers: %{
     "allow" => "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT",
     "connection" => "Keep-Alive",
     "content-length" => "0",
     "content-type" => "text/plain; charset=utf-8",
     "server" => "ArangoDB",
     "x-content-type-options" => "nosniff"
   },
   status: 200
 }}
```

**NOTE:** `:mint` doesn't support unix sockets.

**NOTE:** Since `:gun` is an Erlang library, you _might_ need to add it as an extra application in `mix.exs`:

```elixir
def application() do
  [
    extra_applications: [:logger, :gun])
  ]
end
```

To use something else, you'd have to implement the `Arangox.Client` behaviour in a
module somewhere and set that instead.

The default json library is `Jason`. To use a different library, set the `:json_library` config to the module of your choice, i.e:

```elixir
config :arangox, :json_library, Poison
```

### Benchmarks

**pool size** 10  
**parallel processes** 1000  
**system** virtual machine, 1 cpu (not shared), 2GB RAM

| Name         | Latency   |
| ------------ | --------- |
| Velocy: GET  | 179.74 ms |
| Velocy: POST | 201.23 ms |
| Mint: GET    | 207.00 ms |
| Mint: POST   | 216.53 ms |
| Gun: GET     | 222.61 ms |
| Gun: POST    | 243.65 ms |

<sub>Results generated with [`Benchee`](https://hex.pm/packages/benchee).</sub>

## Start Options

Arangox assumes defaults for the `:endpoints`, `:username` and `:password` options,
and [`db_connection`](https://hex.pm/packages/db_connection) assumes a default
`:pool_size` of `1`, so the following:

```elixir
Arangox.start_link()
```

Is equivalent to:

```elixir
options = [
  endpoints: "http://localhost:8529",
  username: "root",
  password: "",
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

With the `:read_only?` option set to `true`, arangox will try to find a server in
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

## Authentication

### Velocy

When using the default client, authorization is resolved with the `:username`
and `:password` options after a connection is established (authorization headers are not used).
This can be disabled by setting the `:auth?` option to `false`.

### HTTP

When using an HTTP client, Arangox will generate a _Basic_ authorization header with the
`:username` and `:password` options and add it to every request. To prevent this
behavior, set the `:auth?` option to `false`.

```elixir
iex> {:ok, conn} = Arangox.start_link(auth?: false, client: Arangox.GunClient)
iex> {:error, exception} = Arangox.get(conn, "/_admin/server/mode")
iex> exception.message
"not authorized to execute this request"
```

The header value is obfuscated in transfomed requests returned by arangox, for
obvious reasons:

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.GunClient)
iex> {:ok, request, _response} = Arangox.request(conn, :options, "/")
iex> request.headers
%{"authorization" => "..."}
```

## Databases

### Velocy

If the `:database` option is set, it can be overridden by prepending the path of a
request with `/_db/:value`. If nothing is set, the request will be sent as-is and
_ArangoDB_ will assume the `_system` database.

### HTTP

When using an HTTP client, arangox will prepend `/_db/:value` to the path of every request
only if it isn't already prepended. If the start option is not set, nothing is prepended.

```elixir
iex> {:ok, conn} = Arangox.start_link(client: Arangox.GunClient)
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_admin/time")
iex> request.path
"/_admin/time"
iex> {:ok, conn} = Arangox.start_link(database: "_system", client: Arangox.GunClient)
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_admin/time")
iex> request.path
"/_db/_system/_admin/time"
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_db/_system/_admin/time")
iex> request.path
"/_db/_system/_admin/time"
```

## Headers

Headers can be given as maps:

```elixir
%{"header" => "value"}
```

Or lists of two binary element tuples:

```elixir
[{"header", "value"}]
```

Headers given to the start option are merged with every request, but will not override
any of the headers set by Arangox:

```elixir
iex> {:ok, conn} = Arangox.start_link(headers: %{"header" => "value"})
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_api/version")
iex> request.headers
%{"header" => "value"}
```

Headers passed to requests will override any of the headers given to the start option
or set by Arangox:

```elixir
iex> {:ok, conn} = Arangox.start_link(headers: %{"header" => "value"})
iex> {:ok, request, _response} = Arangox.request(conn, :get, "/_api/version", "", %{"header" => "new_value"})
iex> request.headers
%{"header" => "new_value"}
```

## Transport

The `:connect_timeout` start option defaults to `5_000`.

Transport options can be specified via `:tcp_opts` and `:ssl_opts`, for unencrypted and
encrypted connections respectively. When using `:gun` or `:mint`, these options are passed
directly to the `:transport_opts` connect option.

See [`:gen_tcp.connect_option()`](http://erlang.org/doc/man/gen_tcp.html#type-connect_option)
for more information on `:tcp_opts`, or [`:ssl.tls_client_option()`](http://erlang.org/doc/man/ssl.html#type-tls_client_option) for `:ssl_opts`.

The `:client_opts` option can be used to pass client-specific options to `:gun` or `:mint`.
These options are merged with and may override values set by arangox. Some options cannot be
overridden (i.e. `:mint`'s `:mode` option). If `:transport_opts` is set here it will override
everything given to `:tcp_opts` or `:ssl_opts`, regardless of whether or not a connection is
encrypted.

See the `gun:opts()` type in the [gun docs](https://ninenines.eu/docs/en/gun/1.3/manual/gun/)
or [`connect/4`](https://hexdocs.pm/mint/Mint.HTTP.html#connect/4) in the mint docs for more
information.

## Request Options

Request options are handled by and passed directly to `:db_connection`. See [execute/4](https://hexdocs.pm/db_connection/DBConnection.html#execute/4) in the `:db_connection` docs for supported options.

Request timeouts default to `15_000`.

```elixir
iex> {:ok, conn} = Arangox.start_link()
iex> Arangox.get!(conn, "/_admin/server/availability", [], timeout: 15_000)
%Arangox.Response{
  body: %{"code" => 200, "error" => false, "mode" => "default"},
  headers: %{},
  status: 200
}
```

## Contributing

```
mix format
mix do format, credo --strict
docker-compose up -d
mix test
```

## Roadmap

- `:get_endpoints` and `:port_mappings` options
- An Ecto adapter
- More descriptive logs
