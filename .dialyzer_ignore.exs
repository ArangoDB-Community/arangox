# Dialyzer warnings that are wrong about this code, each with the reason it is
# wrong. Nothing goes in here to silence a warning that is right.
#
# Format: {file, warning_type} or {file, warning_type, line}. See
# https://hexdocs.pm/dialyxir/readme.html#ignore-warnings
[
  # `Mint.HTTP1.connect/4` is specced for `Mint.Types.address()`, which is
  # `String.t() | :inet.socket_address()` and therefore includes the
  # `{:local, path}` form a unix domain socket needs -- Mint added unix socket
  # support in 1.5.0 and this is how it is used. Dialyzer works from success
  # typings rather than specs, and Mint's inferred typing for that argument
  # narrows to `binary()` because `Mint.Core.Transport.SSL.connect/3` cannot
  # take a `{:local, _}` address even though `Mint.Core.Transport.TCP.connect/3`
  # can, and the transport module is only known at run time.
  #
  # The call works: `Arangox.ClientContractTest` connects to a real unix-socket
  # HTTP server through it and completes a request. There is no public Mint API
  # that avoids the call -- `Mint.HTTP1.initiate/5`, which takes a socket you
  # opened yourself, is `@doc false`.
  #
  # Revisit when Mint's transport dispatch is specced per scheme.
  {"lib/arangox/client/mint.ex", :call},

  # `with_host/2` reads `:host` and `:port` from the Mint connection struct to
  # decide whether this is a unix-domain connection (port 0) that needs an
  # explicit `host` header. Mint declares its connection type opaque and
  # offers no public accessor for either field; `Mint.HTTP.get_socket/1` is
  # public but the local port of a unix socket cannot recover the hostname.
  # The field read has been stable across Mint 1.x. Revisit if Mint grows an
  # address accessor.
  {"lib/arangox/client/mint.ex", :opaque_match},

  # `check_connection_headers/1`'s fallback clause is "dead" only under the
  # struct type's invariant: `Arangox.Connection.new/4` builds state with
  # `struct/2` from raw caller options, so at runtime `:headers` holds
  # whatever was configured — a map, from a caller predating 0.8 who started
  # the pool through `DBConnection.start_link/2` directly. The clause is the
  # connect-must-not-raise guard for exactly the input the type says cannot happen, and
  # `Arangox.ConfigTest` proves it reachable ("map :headers around the
  # validation still fail the connect in order").
  {"lib/arangox/connection.ex", :pattern_match_cov}
]
