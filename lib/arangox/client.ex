defmodule Arangox.Client do
  @moduledoc """
  Client behaviour for `Arangox`. Arangox uses client implementations to
  perform all its connection and execution operations.

  To use a library other than `:velocy` or `:mint`, implement this behaviour in
  a module and pass that module to the `:client` start option.

  ## One error contract

  Every callback that can fail returns `%Arangox.Error{}` and nothing else — not
  a POSIX atom, not a library exception struct, not a bare binary:

      {:ok, socket} | {:error, Arangox.Error.t()}                     # connect/2
      {:ok, Response.t(), state} | {:error, Arangox.Error.t(), state} # request/3

  `Arangox.Connection` no longer classifies whatever a client happened to
  return; it reads `:reason` off the struct. Populate `:reason` with the
  transport's own atom (`:econnrefused`, `:closed`, ...) so applications can
  match on it.

  ### The socket-gone signal

  A client that detects a lost connection must be able to force a disconnect.
  Before, that was the `{:error, :noproc, state}` sentinel; now it is a
  **reason class**, listed by `connection_lost_reasons/0` and tested by
  `connection_lost?/1`. The connection's execute callback maps any error
  whose reason is in that set to `{:disconnect, ...}`, which retires the socket
  and reconnects.

  Getting this wrong is not a cosmetic error: a dead socket returned to the pool
  as an ordinary `{:error, ...}` stays checked in and fails every later checkout
  that draws it.

  The set covers the socket genuinely being gone (`:closed`, `:econnreset`,
  `:epipe`, ...) and also `:timeout`/`:etimedout`, because a request/response
  exchange that timed out leaves an unread reply on the socket: the next request
  on it would read the previous request's answer. `:noproc` is in the set too,
  so a third-party client written against the old sentinel keeps forcing
  disconnects.

  ## Credentials

  A client is where authentication material is closest to the wire, so it is
  where redaction has to happen. Two rules:

    * never put a header **value** in an error — `:mint` echoes the offending
      value in `{:invalid_header_value, name, value}`, which for an
      `authorization` header is the credential itself. `request/3` refuses a
      header carrying a carriage return, line feed, or null before any client
      sees it, reporting the name alone;
    * never put a configured endpoint binary in an error — it may carry
      userinfo. Clients receive an already-parsed `t:Arangox.Endpoint.t/0`,
      which never has any, and `Arangox.Connection` fills in the (redacted)
      endpoint on the way out.

  ## Request timeouts

  No client may wait on a socket indefinitely. The budget reaches a client as
  two keys in the per-request options:

    * `:deadline` — `DBConnection`'s own option: the **absolute monotonic
      instant, in milliseconds**, by which the caller expects to be done.
      Arangox stamps it when the caller enters the pool, before checkout can
      spend any of the budget.
    * `:request_timeout` — a per-request override of the pool's
      `:request_timeout`. A *ceiling* on the derived wait, never a replacement
      for it.

  A client derives its socket wait from those and from the `:request_timeout`
  in `t:Arangox.Connection.t/0`, and it derives it **again before every
  receive** — a bound applied per `recv` call is not a bound on the request,
  since a response arriving in N chunks would get N budgets:

      deadline = Arangox.Client.deadline(opts, state)

      case Arangox.Client.socket_timeout(deadline, opts, state) do
        {:ok, timeout} -> transport_recv(socket, timeout)
        :elapsed -> {:error, %Arangox.Error{reason: :timeout}, state}
      end

  `deadline/2` falls back to a request-local deadline when the caller
  established none, so a client called outside arangox's own request path is
  bounded too.

  **The remaining budget, never a duration.** The caller's clock starts when it
  asks for a connection, not when one comes free, so a caller that queued out
  most of its allowance must get the remainder. Reading `opts[:timeout]` inside
  a callback and using it as a socket wait restarts a clock that has already
  been running; see
  `docs/solutions/architecture-patterns/dbconnection-timeout-is-a-deadline-not-a-duration.md`.

  **A timeout disconnects.** Report it with `:reason` `:timeout`, which is in
  `connection_lost_reasons/0`. A timed-out HTTP/1.1 connection has unread bytes
  and an open request reference on it; returned to the pool, the next checkout
  reads the *previous* response.

  ## Optional callbacks

  `c:alive?/1` is optional. A client that does not export it is treated as
  alive; see `alive?/1`.
  """

  alias Arangox.{
    Connection,
    Endpoint,
    Error,
    Request,
    Response
  }

  @type socket :: any

  @typedoc """
  Per-request options. The same keyword list `Arangox.request/6` and friends
  were given, so a client can honour caller-supplied settings, plus the two
  keys the timeout budget travels in (see "Request timeouts"). Unknown keys are
  ignored.
  """
  @type request_option :: {atom, any}

  ## Request timeouts

  # The two documented bounds on the derived socket wait.
  #
  # `@timeout_margin` is the slack between arangox's own timeout and
  # `DBConnection`'s checkout deadline. It exists because that deadline fires on
  # the *pool* process and disconnects without unblocking a caller sitting in
  # `recv` -- so arangox has to lose the race deliberately, and by enough that a
  # loaded scheduler cannot flip the order.
  #
  # `@min_socket_timeout` is the smallest wait worth starting. Below it the
  # request is refused instead: issuing one whose answer nobody will read costs
  # a round trip and, on HTTP/1.1, a connection.
  @timeout_margin 100
  @min_socket_timeout 25

  # Matches `DBConnection`'s own default `:timeout` (`db_connection/holder.ex`,
  # `@timeout`), so an unconfigured pool and an unconfigured caller agree.
  @default_request_timeout 15_000

  # Reasons that mean the socket cannot be reused. Kept as an attribute so the
  # membership test compiles to a literal match rather than a list walk.
  @connection_lost_reasons [
    :closed,
    :econnaborted,
    :econnreset,
    :ehostdown,
    :ehostunreach,
    :enetdown,
    :enetreset,
    :enetunreach,
    :enotconn,
    :epipe,
    :etimedout,
    :noproc,
    :timeout
  ]

  @doc """
  Receives an `Arangox.Endpoint` struct and all the start options from
  `Arangox.start_link/1`.

  The `socket` returned from this callback gets placed in the `:socket` field of
  an `Arangox.Connection` struct (a connection's state) to be used by the other
  callbacks as needed. It can be anything — a tuple, another struct, whatever
  the client needs.

  It's up to the client to consolidate the `:connect_timeout`, `:transport_opts`
  and `:client_opts` options.

  Must not raise or exit, whatever the transport does with the options it was
  given: the connection's connect is a `DBConnection` callback, and an
  exception escaping it costs the process its backoff. Leave `:endpoint`
  on the returned error `nil` — the caller knows the configured endpoint and
  fills in a redacted copy.
  """
  @callback connect(endpoint :: Endpoint.t(), start_options :: [Arangox.start_option()]) ::
              {:ok, socket} | {:error, Error.t()}

  @doc """
  Whether the socket in the given state is still usable.

  **Optional.** A client that does not export it is treated as alive, since the
  request path detects a lost socket through the error contract anyway. Do not
  call it directly on a `:client` module; call `alive?/1`, which checks.
  """
  @callback alive?(state :: Connection.t()) :: boolean

  @doc """
  Receives an `Arangox.Request` struct, the caller's per-request options and a
  connection's state (an `Arangox.Connection` struct), and returns an
  `Arangox.Response` struct or an `Arangox.Error`, along with the new state
  (which doesn't necessarily need to change).

  Arangox handles the encoding and decoding of request and response bodies, and
  merging headers.

  If the connection is lost, return an error whose `:reason` is one of
  `connection_lost_reasons/0` to force a disconnect. Otherwise an attempt to
  reconnect may not be made until the next request hitting this process fails.

  **Every receive must be bounded.** Derive the wait with `deadline/2` and
  `socket_timeout/3`; see "Request timeouts" in the module documentation. A
  request that was fully written is never retried automatically, so a client
  does not have to make its writes idempotent — but it does have to report a
  timeout as `:timeout` so the connection is retired rather than reused.

  > #### Signature change in 0.8 {: .warning}
  >
  > This callback took `(request, state)` before 0.8. The options argument is
  > now second. A client still exporting `request/2` raises when called.
  """
  @callback request(
              request :: Request.t(),
              options :: [request_option],
              state :: Connection.t()
            ) ::
              {:ok, Response.t(), Connection.t()} | {:error, Error.t(), Connection.t()}

  @callback close(state :: Connection.t()) :: :ok

  @optional_callbacks alive?: 1

  # API

  @doc """
  Opens a connection through `client`.
  """
  @spec connect(module, Endpoint.t(), [Arangox.start_option()]) ::
          {:ok, socket} | {:error, Error.t()}
  def connect(client, endpoint, start_options), do: client.connect(endpoint, start_options)

  @doc """
  Whether the connection in `state` is still usable.

  Returns `true` for a client that does not implement `c:alive?/1`: the callback
  is optional, and a liveness probe that cannot be asked answers optimistically
  rather than retiring a working connection. Implement `c:alive?/1` if a client
  can answer more cheaply or more accurately than a request would.

  The export check runs `Code.ensure_loaded?/1` first. `function_exported?/3`
  answers `false` for a module that merely has not been **loaded** yet, which
  under lazy loading is any module nothing has called into — so the bare check
  would report a client as not implementing a callback it does implement, and
  the first request against a fresh node would silently take the default.
  """
  @spec alive?(Connection.t()) :: boolean
  def alive?(%Connection{client: client} = state) do
    if implements_alive?(client), do: client.alive?(state), else: true
  end

  @doc """
  Whether `client` implements the optional `c:alive?/1` callback.
  """
  @spec implements_alive?(module) :: boolean
  def implements_alive?(client) when is_atom(client) do
    Code.ensure_loaded?(client) and function_exported?(client, :alive?, 1)
  end

  @doc """
  Runs `request` through the state's client with the caller's options.

  Header names and values are checked here first: one carrying a carriage
  return, line feed, or null is refused with `:invalid_header_value` and never
  reaches a transport.

  The return type is wider than `c:request/3`'s on purpose: this function
  dispatches to a module the user supplied, so what actually comes back is
  whatever that module returned. A client that predates the one-error contract
  can still return a bare reason, and `Arangox.Connection` adapts it. The
  callback's contract is the strict one — implement that.
  """
  @spec request(Request.t(), [request_option], Connection.t()) ::
          {:ok, Response.t(), Connection.t()}
          | {:error, Error.t(), Connection.t()}
          | {:error, term, Connection.t()}
  def request(%Request{} = request, opts, %Connection{client: client} = state)
      when is_list(opts) do
    case check_headers(request.headers) do
      :ok -> client.request(request, opts, state)
      {:error, %Error{} = exception} -> {:error, exception, state}
    end
  rescue
    exception in UndefinedFunctionError ->
      reraise translate_legacy_arity(exception, client), __STACKTRACE__
  end

  ## Header bounds

  # Every request and every connect probe crosses this function, which is why
  # the rule lives here rather than in a client. The transports do not agree:
  # HTTP/1.1 refuses such a value locally, while under HTTP/2 the header is
  # HPACK-encoded and only the server objects — so a transport-level check
  # would name the offending header on one protocol and answer
  # `:protocol_error` on the other, and the byte would reach the wire.
  #
  # The offending value is never echoed: for `authorization` it is the
  # credential itself, so only the header name is reported.
  defp check_headers(headers) when is_map(headers) or is_list(headers) do
    Enum.find_value(headers, :ok, fn
      {name, value} when (is_binary(name) or is_atom(name)) and is_binary(value) ->
        name = to_string(name)

        if smuggling_byte?(name) or smuggling_byte?(to_string(value)) do
          {:error,
           %Error{
             reason: :invalid_header_value,
             message:
               "the #{inspect(name)} header carries a carriage return, line feed, or null, " <>
                 "which cannot be sent; the value is not echoed here because it may be a " <>
                 "credential"
           }}
        end

      # A malformed entry is the caller's mistake on a healthy connection:
      # refused described — the entry may carry a credential — rather than
      # left to raise out of the callback, which would retire the connection.
      _other ->
        {:error,
         %Error{
           reason: :invalid_header_value,
           message:
             "a header entry is not a {name, value} tuple; the entry is not echoed " <>
               "here because it may carry a credential"
         }}
    end)
  end

  defp check_headers(_headers), do: :ok

  @doc false
  # The header-injection byte class. Applied to every request here and to the
  # `:headers` option in `Arangox.Api.Client`; one implementation, so the two
  # refusals cannot drift apart.
  @spec smuggling_byte?(binary) :: boolean
  def smuggling_byte?(<<byte, _rest::binary>>) when byte in [?\r, ?\n, 0], do: true
  def smuggling_byte?(<<_byte, rest::binary>>), do: smuggling_byte?(rest)
  def smuggling_byte?(<<>>), do: false

  @doc false
  # The byte class that can alter a request path when interpolated into it.
  # Applied by `Arangox.Connection` to the `:database` name and by
  # `Arangox.Api.Client` to path parameters; one implementation, so neither
  # seam can become the bypass of the other.
  @spec path_altering_byte?(binary) :: boolean
  def path_altering_byte?(<<byte, _rest::binary>>)
      when byte in [?/, ??, ?#, ?%] or byte < 0x20 or byte == 0x7F,
      do: true

  def path_altering_byte?(<<_byte, rest::binary>>), do: path_altering_byte?(rest)
  def path_altering_byte?(<<>>), do: false

  @doc false
  # The one JSON test both codec seams apply: `Arangox.Connection` when
  # deciding whether a response body decodes as JSON, `Arangox.Api.Client`
  # when deciding whether a declared request media type needs a content-type
  # header. Takes a bare, lowercased media type.
  @spec json_media?(binary) :: boolean
  def json_media?(media), do: media == "application/json" or String.ends_with?(media, "+json")

  @doc """
  Closes the connection in `state`.
  """
  @spec close(Connection.t()) :: :ok
  def close(%Connection{client: client} = state), do: client.close(state)

  ## Request timeouts

  @doc """
  The `:request_timeout` a pool falls back to, in milliseconds.

  Deliberately the same number as `DBConnection`'s default `:timeout`, so an
  unconfigured pool and an unconfigured caller expire together rather than one
  silently masking the other.
  """
  @spec default_request_timeout() :: pos_integer
  def default_request_timeout, do: @default_request_timeout

  @doc """
  Milliseconds by which a derived socket wait is kept short of the caller's
  deadline, so arangox's own timeout error wins the race against
  `DBConnection`'s.
  """
  @spec timeout_margin() :: pos_integer
  def timeout_margin, do: @timeout_margin

  @doc """
  The shortest socket wait worth starting, in milliseconds. A budget that
  cannot cover it is refused instead of spent.
  """
  @spec min_socket_timeout() :: pos_integer
  def min_socket_timeout, do: @min_socket_timeout

  @doc """
  Whether `value` is usable as a `:request_timeout`, with the message to report
  when it is not.

  Only a positive finite number of milliseconds is admitted. `:infinity` is
  refused as loudly as `0` and negatives: an unbounded request timeout is the
  condition the option exists to remove, not a way to configure it.

      iex> Arangox.Client.validate_request_timeout(5_000)
      :ok

      iex> {:error, message} = Arangox.Client.validate_request_timeout(:infinity)
      iex> message =~ ":request_timeout"
      true
  """
  @spec validate_request_timeout(term) :: :ok | {:error, binary}
  def validate_request_timeout(value) when is_integer(value) and value > 0, do: :ok

  def validate_request_timeout(value) do
    {:error,
     "The :request_timeout option expects a positive integer number of milliseconds, " <>
       "got: #{inspect(value)}. Zero, negative values and :infinity are refused — a " <>
       "request that cannot time out is the thing this option exists to prevent."}
  end

  @doc """
  The `:request_timeout` in force for one request: the per-request override if
  the caller gave one, otherwise the pool's.

  An override *replaces* the pool value rather than being capped by it, so a
  single slow request can be given room without loosening the pool. It is still
  only a ceiling on the derived wait — the caller's deadline outranks it.
  """
  @spec request_timeout([request_option], Connection.t()) :: pos_integer
  def request_timeout(opts, %Connection{request_timeout: pool}) when is_list(opts) do
    case Keyword.get(opts, :request_timeout) do
      value when is_integer(value) and value > 0 ->
        value

      _absent_or_invalid ->
        if is_integer(pool) and pool > 0, do: pool, else: @default_request_timeout
    end
  end

  @doc """
  The absolute monotonic instant, in milliseconds, this request has to be
  finished by.

  Prefers the caller's `:deadline` — stamped when the caller entered the pool,
  so it already accounts for time spent queueing — and falls back to a
  request-local one when there is none, which is what bounds the pool's ping, a
  client used directly, and any path that did not enter through `Arangox`.
  """
  @spec deadline([request_option], Connection.t()) :: integer
  def deadline(opts, %Connection{} = state) when is_list(opts) do
    case Keyword.get(opts, :deadline) do
      deadline when is_integer(deadline) -> deadline
      _absent -> monotonic_ms() + request_timeout(opts, state)
    end
  end

  @doc """
  The socket wait to use for the next receive, derived from the *remaining*
  budget.

  Returns `:elapsed` when what is left cannot cover `min_socket_timeout/0`.
  Callers before the request is written should report that as an ordinary
  error — nothing was sent, so the connection is still good. Callers already
  mid-response must report it with a connection-lost reason, because the
  response stream has been abandoned part-read.
  """
  @spec socket_timeout(integer, [request_option], Connection.t()) ::
          {:ok, pos_integer} | :elapsed
  def socket_timeout(deadline, opts, %Connection{} = state)
      when is_integer(deadline) and is_list(opts) do
    remaining = deadline - monotonic_ms()
    timeout = min(remaining - @timeout_margin, request_timeout(opts, state))

    if timeout >= @min_socket_timeout, do: {:ok, timeout}, else: :elapsed
  end

  @doc false
  @spec monotonic_ms() :: integer
  def monotonic_ms, do: System.monotonic_time(:millisecond)

  @doc """
  Every reason that means the socket cannot be reused, sorted.

  An `Arangox.Error` carrying one of these forces a disconnect rather than an
  ordinary error return. See the module documentation.
  """
  @spec connection_lost_reasons() :: [atom]
  def connection_lost_reasons, do: @connection_lost_reasons

  @doc """
  Whether an error means the socket is gone and must not be reused.

      iex> Arangox.Client.connection_lost?(%Arangox.Error{reason: :closed})
      true

      iex> Arangox.Client.connection_lost?(%Arangox.Error{reason: :arango_conflict})
      false
  """
  @spec connection_lost?(Error.t() | atom) :: boolean
  def connection_lost?(%Error{reason: reason}), do: connection_lost?(reason)
  def connection_lost?(reason) when reason in @connection_lost_reasons, do: true
  def connection_lost?(_reason), do: false

  # A third-party client written against the pre-0.8 two-argument callback
  # fails here rather than as a bare UndefinedFunctionError at first request.
  defp translate_legacy_arity(
         %UndefinedFunctionError{module: client, function: :request, arity: 3} = exception,
         client
       ) do
    if Code.ensure_loaded?(client) and function_exported?(client, :request, 2) do
      %UndefinedFunctionError{
        exception
        | message: """
          #{inspect(client)} implements the pre-v0.8 Arangox.Client.request/2 \
          callback. Since v0.8 the callback takes the caller's per-request \
          options as its second argument:

              @impl true
              def request(%Arangox.Request{} = request, opts, %Arangox.Connection{} = state)

          It must also return {:ok, %Arangox.Response{}, state} or \
          {:error, %Arangox.Error{}, state}; a bare reason atom or a library \
          exception struct is no longer accepted.
          """
      }
    else
      exception
    end
  end

  defp translate_legacy_arity(exception, _client), do: exception
end
