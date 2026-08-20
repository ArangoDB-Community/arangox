defmodule Arangox.Connection do
  @moduledoc """
  `DBConnection` implementation for `Arangox`.

  ## The connect pipeline

  `connect/1` walks the configured endpoints in order and runs one linear
  pipeline per endpoint:

      resolve options -> open (do_connect) -> resolve_auth
        -> check_availability -> discover_version -> ready

  Everything after `do_connect` owns an open socket, so every exit from those
  stages other than a successful return closes that socket first. Failing to
  do so leaks a socket per attempt, not per process: `DBConnection` retries
  `connect/1` *in the same process* under backoff, so the leaked sockets pile
  up in a live process instead of dying with it.

  `check_availability` has a fourth outcome besides ok/next/error: a `503`
  naming the current leader in `x-arango-endpoint` re-enters the walk at that
  leader, once the redirect admission policy has admitted it. See the comments
  above `redirect/3` for the policy and `Arangox.start_link/1` for the
  user-facing rules and the `:endpoint_mapper` trust boundary.

  No stage raises. Endpoint parsing goes through `Arangox.Endpoint.parse/1`
  and response bodies are decoded with a non-raising decoder, because a raise
  here escapes the `DBConnection` callback and turns an orderly backoff into a
  supervisor crash loop.

  ## Credentials never reach state, an error or a log

  `new/4` stores `Arangox.Endpoint.redact/1` of the configured endpoint, not the
  configured endpoint. That single substitution covers three exits at once: the
  `:endpoint` field of every `Arangox.Error` built here, `Exception.message/1`
  (which prepends `[endpoint] `), and the `failed to connect` line
  `DBConnection` logs on every backoff cycle.

  Redacting only at render would have left `inspect(state)` leaking, and
  `DBConnection`'s own `:show_sensitive_data_on_connection_error` does not help:
  it sanitizes only exceptions that **escape** `connect/1`, and this
  module never lets one escape — it returns `{:error, exception}`, which
  `DBConnection` logs unsanitized. There is no opt-out, so the redaction is
  unconditional and there is no option to turn it off.

  `:auth` and the resolved `authorization` header still hold the credential in
  state, because the request path needs them; the `Inspect` implementation at
  the bottom of this file redacts both.

  ## Cost of the walk

  The walk is per connect *attempt*, and a connect attempt is retried on the
  usual `:backoff_min`/`:backoff_max` schedule for as long as the pool lives.
  With N endpoints that are all down, every backoff cycle of every pool process
  costs N connection attempts, N `:failover_callback` invocations and one
  `failed to connect` log line. A pool of 10 against 3 dead endpoints at the
  default one-second minimum backoff is therefore ~30 connection attempts and
  ~30 callback invocations per second. Keep `:failover_callback` cheap and
  non-blocking, and raise `:backoff_min` if the log volume matters.
  """

  use DBConnection

  alias Arangox.{
    Client,
    Endpoint,
    Errno,
    Error,
    Query,
    Request,
    Response,
    Transaction,
    VelocyClient
  }

  # The canonical defaults for the two per-pool options. They live here
  # because this module owns both the connection struct they end up in and
  # `resolve_options/1`, which fills them.
  # `Arangox.json_library/0` and `Arangox.VelocyClient.vst_maxsize/0` read them
  # back out through the `fallback_*` functions below.
  @default_json_library Jason
  @default_vst_maxsize 30_720

  # JSON stays the default; VelocyPack is opt-in per pool.
  @default_content_type :json

  # The raw-size bound applied to every response body before it reaches a
  # codec, 128 MiB. The bound exists to stop a hostile or broken server from
  # feeding the decoder without limit, so `:max_body_size` raises it per pool;
  # cursor batches stream in far smaller pieces, so an ordinary workload never
  # meets it.
  @default_max_body_size 134_217_728

  @type t :: %__MODULE__{
          socket: any,
          client: module,
          endpoint: Arangox.endpoint(),
          parsed_endpoint: Endpoint.t() | nil,
          failover?: boolean,
          database: binary,
          auth: Arangox.Auth.t(),
          headers: Arangox.headers(),
          trx_id: binary | nil,
          disconnect_on_error_codes: [integer],
          read_only?: boolean,
          cursors: map,
          server_version: Version.t() | nil,
          json_library: module,
          content_type: :json | :velocypack,
          max_body_size: pos_integer,
          vst_maxsize: pos_integer,
          request_timeout: pos_integer | nil
        }

  @type failover? :: boolean

  @enforce_keys [:socket, :client, :endpoint]

  defstruct [
    :socket,
    :client,
    :endpoint,
    :parsed_endpoint,
    :failover?,
    :database,
    :cursors,
    :auth,
    :server_version,
    headers: [],
    # The in-flight stream transaction (begin/commit/rollback). A bearer
    # capability: the `Inspect` implementation below must redact it.
    trx_id: nil,
    disconnect_on_error_codes: [401, 405, 503, 505],
    read_only?: false,
    json_library: @default_json_library,
    content_type: @default_content_type,
    max_body_size: @default_max_body_size,
    vst_maxsize: @default_vst_maxsize,
    # `nil` means "unresolved": `resolve_options/1` always fills it for a real
    # connection, and `Arangox.Client.request_timeout/2` falls back to
    # `Arangox.Client.default_request_timeout/0` for state built by hand.
    request_timeout: nil
  ]

  @doc false
  # The deprecated application-config fallbacks, read without
  # warning. The warning belongs to the once-per-pool path in
  # `Arangox.start_link/1`, not here: this runs on every connect attempt.
  @spec fallback_json_library() :: module
  def fallback_json_library,
    do: Application.get_env(:arangox, :json_library, @default_json_library)

  @doc false
  @spec fallback_vst_maxsize() :: pos_integer
  def fallback_vst_maxsize,
    do: Application.get_env(:arangox, :vst_maxsize, @default_vst_maxsize)

  @doc false
  # Builds connection state from an open socket and the resolved config.
  #
  # It takes the config map rather than the raw options because options with a
  # connect-time fallback cannot survive a bare `struct(opts)`: that reads the
  # option, finds it absent, and leaves the struct default in place, silently
  # discarding both the deprecated application-config fallback and anything a
  # later stage resolved. Resolved values are merged last so they win.
  #
  # The endpoint is stored **redacted**. Everything downstream --
  # errors, `Exception.message/1`, `inspect/1`, the connect-failure log line --
  # reads it from here, so redacting at the store covers all of them at once.
  # A redacted binary does not parse, so anything that needs the origin --
  # the redirect same-origin check, the downgrade refusal -- reads
  # `:parsed_endpoint`, never the display binary.
  @spec new(Client.socket(), Arangox.endpoint(), Endpoint.t(), config) :: t
  def new(socket, endpoint, %Endpoint{} = parsed, %{} = config) do
    __MODULE__
    |> struct(config.opts)
    |> Map.merge(%{
      socket: socket,
      endpoint: Endpoint.redact(endpoint),
      parsed_endpoint: parsed,
      client: config.client,
      failover?: config.failover?,
      json_library: config.json_library,
      content_type: config.content_type,
      max_body_size: config.max_body_size,
      vst_maxsize: config.vst_maxsize,
      request_timeout: config.request_timeout,
      cursors: %{},
      # `struct/2` above reads the raw option list, which can name *any*
      # struct key — including fields no option may set. Every
      # internal-only field must be re-asserted in this merge, or a start
      # option can preload it: `trx_id:` in the options would attach a
      # transaction nobody began to every request the connection serves.
      trx_id: nil,
      server_version: nil
    })
  end

  # HTTP via Mint is the sole default transport. ArangoDB removed
  # VelocyStream in 3.12, so a VST default cannot connect to any current
  # server; VelocyClient remains fully supported as an explicit opt-in for
  # 3.11 deployments.
  @default_client Arangox.MintClient
  @default_endpoints "http://localhost:8529"
  # The redirect budget is spent per connect *attempt*, not per endpoint: it is
  # carried in the config map that `walk/2` threads through the whole walk, so a
  # cycle between two endpoints that redirect to each other terminates.
  @max_redirects 3
  @header_redirect "x-arango-endpoint"
  @header_trx_id "x-arango-trx-id"
  @header_dirty_read {"x-arango-allow-dirty-read", "true"}
  @request_ping %Request{method: :get, path: "/_admin/server/availability"}
  @request_availability %Request{method: :get, path: "/_admin/server/availability"}
  @request_mode %Request{method: :get, path: "/_admin/server/mode"}
  @request_version %Request{method: :get, path: "/_api/version"}
  @exception_no_prepare %Error{
    message:
      "ArangoDB has no prepared statements. To reuse a query plan, pass " <>
        "use_plan_cache: true (requires 3.12.4+): the server caches plans by statement " <>
        "text, so the reuse comes from running the same query again, not from holding a " <>
        "value. Run queries with Arangox.query/4 or Arangox.cursor/4; see Arangox.Query"
  }

  @exception_not_a_query %Error{
    message: "only an %Arangox.Query{} can be closed. Run queries with Arangox.query/4"
  }
  @exhausted "all endpoints are unavailable"

  # DECISION: the connect-pipeline probes are bounded by `:connect_timeout`,
  # and by **one** budget of it for all of them together.
  #
  # They are arangox's own requests, not a caller's, so they carry no caller
  # options and there is no caller deadline to inherit —
  # `c:Arangox.Client.request/3`'s options argument is documented as the
  # *caller's* options. "No caller" cannot mean "no bound": a server that
  # completes the TCP/TLS handshake and then goes silent would wedge `connect/1`
  # on the first probe, with no backoff, no endpoint walk, and a socket held
  # open where the suite's port-count assertion cannot see it. The auth,
  # availability and version stages each add an exposure.
  #
  # `:connect_timeout` is the option that already governs every other wait in
  # this pipeline, so it is the one that governs here. A budget stamped fresh
  # per stage would bound each probe without bounding the handshake: the worst
  # case would be `:connect_timeout` × the number of stages, and it would grow
  # silently every time a stage was added — and the stage count has already
  # tripled once. So the budget is established once per endpoint attempt, when the
  # socket opens, and each stage derives its wait from what is *left* of it,
  # exactly as `run_execute/4` does for a caller's request. This is the shape
  # Postgrex and MyXQL use (`handshake_timeout`, armed once around the whole
  # handshake); they need an external timer for it because their handshake
  # receives pass `:infinity`, while arangox already derives every wait from a
  # deadline, so carrying one deadline through the stages is the whole of it.
  #
  # Worst case per endpoint is therefore `:connect_timeout` for the socket open
  # plus `:connect_timeout` for all probes together — the socket open belongs to
  # the client, which applies the option itself, and this module cannot read it
  # back out (see the mirrored default below). The pool's `:request_timeout`
  # still caps each derived wait, so a single probe's wait is the lower of the
  # two.
  #
  # DECISION: the budget is per **endpoint attempt**, not per `walk/2`. One
  # budget spanning the walk would leave the second and later endpoints nothing
  # to spend and would silently disable failover — the walk exists so that
  # an endpoint that is down does not end the connect attempt. It also matches
  # Postgrex and MyXQL, whose handshake budget is per socket, and it keeps the
  # probe budget consistent with the socket-open budget beside it, which is
  # already per endpoint. A redirect (`{:redirect, ...}`) opens a new socket and
  # so starts a new budget; `@max_redirects` is what bounds *those*.
  #
  # `connect_timeout: :infinity` is legal for `:gen_tcp.connect/4` but cannot
  # bound a probe, so such a pool's probes fall back to its `:request_timeout`.
  #
  # Mirrors the default in `Arangox.MintClient.connect/2` and
  # `Arangox.VelocyClient.connect/2`; it is theirs to apply to the socket open,
  # and this module cannot read it back out of them.
  @default_connect_timeout 5_000

  @typedoc false
  @type config :: %{
          client: module,
          endpoints: [Arangox.endpoint()],
          endpoint_mapper: Arangox.endpoint_mapper() | nil,
          redirects_left: non_neg_integer,
          failover?: boolean,
          json_library: module,
          content_type: :json | :velocypack,
          max_body_size: pos_integer,
          vst_maxsize: pos_integer,
          request_timeout: pos_integer,
          show_sensitive?: boolean,
          opts: [Arangox.start_option()]
        }

  @impl true
  def connect(opts) do
    config = resolve_options(opts)

    case walk(config.endpoints, config) do
      {:ok, %__MODULE__{}} = connected -> connected
      {:error, exception} -> {:error, reveal(exception, config)}
    end
  end

  # Redaction's single exception, and the only place credentials can come back.
  #
  # Redaction is applied where the endpoint is *stored*, so an error leaving the
  # walk already carries the redacted form and `inspect/1` on connection state
  # can never leak. A pool that opts into `:show_sensitive_data_on_connection_error`
  # gets the configured value back here — in the connect-time error only.
  # Request-time errors read the endpoint out of state, which stays redacted, and
  # so does `inspect/1`; neither has an opt-out.
  #
  # DBConnection's own sanitizer does not cover this path. It wraps only
  # exceptions *raised* out of `connect/1` (`db_connection/connection.ex:80-85`),
  # and arangox returns instead of raising, so a returned error is
  # logged verbatim through `Exception.format_banner/3`.
  #
  # The match is by redacted form rather than by carrying the raw value through
  # the walk, so no code path between here and `new/4` ever holds it. Several
  # userinfo endpoints sharing a scheme redact to the same form; the first
  # configured match is revealed, which is still one of the caller's own
  # values. An endpoint
  # reached by redirect is not among the configured ones and stays as it is —
  # a server-advertised endpoint carries no credentials to reveal.
  defp reveal(%Error{endpoint: endpoint} = exception, %{show_sensitive?: true} = config)
       when is_binary(endpoint) do
    case Enum.find(config.endpoints, &(is_binary(&1) and Endpoint.redact(&1) == endpoint)) do
      nil -> exception
      configured -> %{exception | endpoint: configured}
    end
  end

  defp reveal(exception, _config), do: exception

  # `Resolve`. The single option-resolution stage: every later stage reads what
  # it needs from the config map rather than reaching back into `opts`. New
  # connect-time options belong here, not inside a stage.
  @spec resolve_options([Arangox.start_option()]) :: config
  defp resolve_options(opts) do
    given = Keyword.get(opts, :endpoints, @default_endpoints)

    %{
      client: Keyword.get(opts, :client, @default_client),
      endpoints: List.wrap(given),
      # The redirect admission policy is decided from the configured
      # endpoints and this mapper, so both are resolved once, here, rather than
      # read out of `opts` from inside `check_availability/3`.
      endpoint_mapper: Keyword.get(opts, :endpoint_mapper),
      redirects_left: @max_redirects,
      # A list of endpoints means failover: one endpoint being unusable moves
      # the walk on instead of failing the connect. A single binary endpoint
      # has nowhere to move on to, so its failures are reported as-is.
      failover?: is_list(given),
      # Per-pool, not global. The start option wins; the application-config
      # read is the deprecated fallback and is silent here (see the note on
      # `Arangox.start_link/1` for where the deprecation warning is emitted and
      # why it is not emitted from this function).
      json_library: Keyword.get_lazy(opts, :json_library, &fallback_json_library/0),
      vst_maxsize: Keyword.get_lazy(opts, :vst_maxsize, &fallback_vst_maxsize/0),
      # No application-config fallback: this option is new in 0.8, so there
      # is no deprecated source to honour.
      content_type: Keyword.get(opts, :content_type, @default_content_type),
      # Same: new in 0.8, no fallback source.
      max_body_size: Keyword.get(opts, :max_body_size, @default_max_body_size),
      # `Arangox.start_link/1` rejects an invalid value; this cannot — a raise
      # here escapes the `DBConnection` callback and turns backoff into a
      # crash loop — so a pool started through `DBConnection` directly with a
      # nonsense value degrades to the default rather than to an unbounded wait.
      request_timeout: resolve_request_timeout(opts),
      # DBConnection's option, honoured for connect-time errors only.
      show_sensitive?: Keyword.get(opts, :show_sensitive_data_on_connection_error, false) == true,
      opts: opts
    }
  end

  defp resolve_request_timeout(opts) do
    value = Keyword.get(opts, :request_timeout, Client.default_request_timeout())

    case Client.validate_request_timeout(value) do
      :ok -> value
      {:error, _message} -> Client.default_request_timeout()
    end
  end

  # `Resolve -> Exhausted`.
  defp walk([], _config), do: {:error, %Error{message: @exhausted}}

  # `Resolve -> Open`.
  #
  # The probe budget is stamped here, on the successful open, and covers every
  # stage that follows for *this* endpoint. Each subsequent endpoint reached
  # through the walk comes back through this clause and gets its own.
  defp walk([endpoint | rest], config) do
    case do_connect(endpoint, config) do
      {:ok, state} ->
        probe_opts = connect_probe_opts(config)
        owning_socket(state, rest, config, connect_stages(config, probe_opts))

      {:next, _reason} ->
        walk(rest, config)

      {:error, exception} ->
        {:error, exception}
    end
  end

  # `Open`. Returns `{:ok, state}` holding an open socket, `{:next, reason}` to
  # continue the walk or `{:error, exception}` to stop it. No socket exists on
  # either error return, so there is nothing to close.
  defp do_connect(endpoint, %{client: client, opts: opts} = config) do
    case Endpoint.parse(endpoint) do
      {:ok, parsed} ->
        case Client.connect(client, parsed, opts) do
          {:ok, socket} ->
            # The socket is open but nothing owns it until this returns
            # `{:ok, state}`, and connect/1 must not raise. This
            # state is reachable without `Arangox.start_link/1`'s validation —
            # `DBConnection.start_link(Arangox.Connection, ...)` skips it — so
            # a header list of the wrong shape is refused here, described,
            # rather than left to crash mid-request.
            state = new(socket, endpoint, parsed, config)

            case check_connection_headers(state) do
              :ok ->
                {:ok, state}

              {:error, exception} ->
                close(state)
                open_failed(endpoint, exception, config)
            end

          {:error, reason} ->
            open_failed(endpoint, reason, config)
        end

      {:error, message} ->
        # A malformed endpoint is a configuration error, but it still must not
        # raise out of connect/1: the process backs off instead.
        open_failed(endpoint, message, config)
    end
  end

  # A header value may be a credential, so the refusal reports the shape
  # rule and never an element.
  defp check_connection_headers(%__MODULE__{headers: headers}) when is_list(headers) do
    if Enum.all?(headers, fn
         {name, value} -> is_binary(name) and is_binary(value)
         _other -> false
       end) do
      :ok
    else
      {:error, headers_shape_error()}
    end
  end

  defp check_connection_headers(%__MODULE__{}), do: {:error, headers_shape_error()}

  defp headers_shape_error do
    %Error{
      reason: :client_error,
      message: ":headers must be a list of {name, value} tuples of strings since 0.8"
    }
  end

  defp open_failed(endpoint, reason, %{failover?: true, opts: opts}) do
    exception = connect_exception(endpoint, reason)
    failover_callback(exception, opts)

    {:next, exception}
  end

  defp open_failed(endpoint, reason, %{failover?: false}) do
    {:error, connect_exception(endpoint, reason)}
  end

  # A conforming client returns `{:error, %Arangox.Error{}}` with `:endpoint`
  # unset -- it was handed a parsed endpoint and cannot know the configured
  # binary -- so the redacted binary is filled in here.
  #
  # The second clause is the legacy adapter for a third-party client still
  # returning a bare reason. The behaviour cannot be enforced at compile time,
  # and a client that predates the contract should degrade to a slightly poorer
  # error rather than to a `BadMapError`. Everything arangox ships takes the
  # first clause.
  defp connect_exception(endpoint, %Error{} = exception),
    do: %{exception | endpoint: Endpoint.redact(endpoint)}

  defp connect_exception(endpoint, reason),
    do: %{legacy_error(reason) | endpoint: Endpoint.redact(endpoint)}

  # Turns whatever a pre-contract client returned into the one error struct,
  # keeping as much of it as can be recovered. A library exception carrying a
  # `:reason` atom -- `%Mint.TransportError{reason: :closed}`, say -- keeps that
  # atom, so such a client still forces a disconnect through
  # `Arangox.Client.connection_lost?/1` rather than silently losing the signal.
  defp legacy_error(%{__exception__: true, reason: reason} = exception) when is_atom(reason),
    do: %Error{reason: reason, message: Exception.message(exception)}

  defp legacy_error(%{__exception__: true} = exception),
    do: %Error{message: Exception.message(exception)}

  defp legacy_error(reason),
    do: %Error{reason: if(is_atom(reason), do: reason), message: reason}

  # The stages that run against an open socket, in order. Inserting a stage
  # here is the supported way to extend the connect pipeline. A stage that needs
  # anything from the resolved config closes over it here, so every stage stays
  # a one-argument function of the state.
  #
  # `probe_opts` is the one budget the stages share; a stage that makes a
  # request passes it straight to `Arangox.Client.request/3`. Adding a stage
  # therefore costs no extra budget, which is the point.
  defp connect_stages(config, probe_opts) do
    [
      &resolve_auth(&1, probe_opts),
      &check_availability(&1, config, probe_opts),
      &discover_version(&1, probe_opts)
    ]
  end

  # The probe budget for one endpoint attempt, as an absolute instant every
  # stage derives its remaining wait from. Stamped once, by `walk/2`, on the
  # open — not per stage. See the note above `@default_connect_timeout` for why
  # `:connect_timeout` is the option that governs here and why the budget spans
  # the stages rather than each of them.
  defp connect_probe_opts(%{opts: opts, request_timeout: request_timeout}) do
    budget =
      case Keyword.fetch(opts, :connect_timeout) do
        {:ok, timeout} when is_integer(timeout) and timeout > 0 -> timeout
        {:ok, _unbounded} -> request_timeout
        :error -> @default_connect_timeout
      end

    [deadline: Client.monotonic_ms() + budget]
  end

  # Explicit socket ownership. From here the socket is open, so the only
  # exit that does not close it is `{:ok, state}` with no stages left.
  defp owning_socket(state, _rest, _config, []), do: {:ok, state}

  defp owning_socket(state, rest, config, [stage | stages]) do
    case run_stage(stage, state) do
      {:ok, %__MODULE__{} = state} ->
        owning_socket(state, rest, config, stages)

      # `CloseAndNext`: this endpoint is unusable, the next one may not be.
      {:next, reason, %__MODULE__{} = state} ->
        close(state)
        notify_failover(state, exception(state, reason), config)
        walk(rest, config)

      # `CloseAndRedirect`: the server named the current leader and the policy
      # admitted it. The walk re-enters at the leader and keeps the
      # remaining configured endpoints behind it, so a leader that is itself
      # unreachable still falls back to the ordinary walk.
      #
      # This deliberately does not call `notify_failover/3`. Following a leader
      # is normal operation, not an endpoint rejection: arangojs re-queues the
      # task on `503 && leaderEndpoint` before reaching any error path, and the
      # Java driver's `failIfNotMatch` only marks a failure when the redirect
      # target is not the host it was already talking to.
      {:redirect, endpoint, %__MODULE__{} = state} ->
        close(state)
        walk([endpoint | rest], spend_redirect(config))

      # `CloseAndFail`: stop the walk.
      {:error, exception, %__MODULE__{} = state} ->
        close(state)
        notify_failover(state, exception, config)
        {:error, exception}
    end
  end

  # A stage runs user-pluggable code — `:json_library` decodes the probe
  # responses — inside `connect/1` while `owning_socket/4` holds the only
  # reference to the open socket. A crash of any kind must come back as
  # the walk's own `CloseAndFail` shape, which closes it. A crash is a bug in
  # that code, not an endpoint being unavailable, so it stops the walk rather
  # than spending the remaining endpoints on the same crash.
  defp run_stage(stage, state) do
    stage.(state)
  rescue
    exception ->
      {:error, %Error{reason: :client_error, message: Exception.message(exception)}, state}
  catch
    kind, reason ->
      {:error, %Error{reason: :client_error, message: "#{kind}: #{inspect(reason)}"}, state}
  end

  # Every rejection of an endpoint drawn from a failover list is reported,
  # whether the socket never opened, the credentials were refused, or the
  # server answered and declared itself unusable. All four official ArangoDB
  # drivers classify a reachable-but-unavailable server as the same kind of
  # failure as an unreachable one, and this follows them.
  #
  # The socket is already closed when this runs, so a callback that blocks
  # holds no resource. A single configured endpoint has nothing to fail over
  # to and reports through the returned error alone.
  defp notify_failover(%__MODULE__{failover?: true}, %Error{} = exception, %{opts: opts}) do
    _ = failover_callback(exception, opts)
    :ok
  end

  defp notify_failover(%__MODULE__{}, _exception, _config), do: :ok

  # Closing must not raise either: a client may be handed a socket the peer has
  # already torn down.
  defp close(%__MODULE__{socket: nil}), do: :ok

  defp close(%__MODULE__{} = state) do
    _ = Client.close(state)
    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  # An endpoint that answered but is not usable. Under failover the walk goes
  # on; on a single endpoint there is nothing to go on to.
  defp unavailable(%__MODULE__{failover?: true} = state, reason), do: {:next, reason, state}
  defp unavailable(%__MODULE__{} = state, reason), do: {:error, exception(state, reason), state}

  # The callback is user code running inside `connect/1`. A raise here escapes
  # a `DBConnection` callback, so an endpoint outage plus one buggy callback
  # is a worker restart loop rather than an ordinary failed connect with
  # backoff — it exhausts the supervisor's restart intensity and takes
  # the pool down. Its failure is not the connect's to report, so it is
  # swallowed rather than turned into a different error.
  defp failover_callback(%Error{} = exception, opts) do
    try do
      case Keyword.get(opts, :failover_callback) do
        # The guards keep a malformed tuple out of `apply/3`, whose raise the
        # rescue below would swallow. `Arangox.start_link/1` refuses malformed
        # callbacks, but this state is reachable without its validation.
        {mod, fun, args} when is_atom(mod) and is_atom(fun) and is_list(args) ->
          apply(mod, fun, [exception | args])

        fun when is_function(fun, 1) ->
          fun.(exception)

        _absent_or_invalid ->
          nil
      end
    rescue
      _exception -> nil
    catch
      _kind, _reason -> nil
    end

    exception
  end

  # `Authenticate`. A rejected authentication is not an availability problem,
  # so it closes the socket and stops the walk rather than trying the next
  # endpoint with the same bad credentials. It still reports through
  # `:failover_callback`, because the endpoint was rejected.
  # The supported `:auth` shapes with every credential a binary — the only
  # inputs the authorization-header interpolation and the VST auth message are
  # defined for.
  defguardp is_renderable_auth(auth)
            when is_nil(auth) or
                   (is_tuple(auth) and tuple_size(auth) == 3 and elem(auth, 0) == :basic and
                      is_binary(elem(auth, 1)) and is_binary(elem(auth, 2))) or
                   (is_tuple(auth) and tuple_size(auth) == 2 and elem(auth, 0) == :bearer and
                      is_binary(elem(auth, 1)))

  # This state is reachable without `Arangox.start_link/1`'s validation — a
  # caller can hand `Arangox.Connection` to `DBConnection.start_link/2`
  # directly — and letting the value reach interpolation raises a message that
  # renders it, which the pool then logs. Refused *described* instead,
  # before any client-specific clause, so the rule covers VelocyStream too.
  defp resolve_auth(%__MODULE__{auth: auth} = state, _probe_opts)
       when not is_renderable_auth(auth) do
    {:error,
     %Error{
       message:
         "the :auth option expects {:basic, username, password} or {:bearer, token} " <>
           "with every credential a string; got: " <> Arangox.Auth.describe(auth)
     }, state}
  end

  defp resolve_auth(%__MODULE__{client: VelocyClient} = state, probe_opts) do
    case apply(VelocyClient, :maybe_authenticate, [state, probe_opts]) do
      :ok ->
        {:ok, state}

      {:error, %Error{} = exception} ->
        {:error, exception, state}

      {:error, reason} ->
        {:error, exception(state, reason), state}
    end
  end

  defp resolve_auth(%__MODULE__{auth: {:basic, un, pw}} = state, _probe_opts) do
    base64_encoded = Base.encode64("#{un}:#{pw}")
    {:ok, put_header(state, {"authorization", "Basic #{base64_encoded}"})}
  end

  defp resolve_auth(%__MODULE__{auth: {:bearer, token}} = state, _probe_opts) do
    {:ok, put_header(state, {"authorization", "Bearer #{token}"})}
  end

  defp resolve_auth(%__MODULE__{} = state, _probe_opts) do
    {:ok, state}
  end

  # `CheckAvailability` for a read-only pool: only a server reporting readonly
  # mode is acceptable, so anything else is "try the next endpoint". A read-only
  # pool never follows a leader redirect — landing on the leader is the one
  # thing `read_only?: true` exists to avoid — so it does not go near
  # `redirect/3`.
  defp check_availability(%__MODULE__{read_only?: true} = state, _config, probe_opts) do
    state = put_header(state, @header_dirty_read)
    request = assemble_headers(@request_mode, nil, state)

    case Client.request(request, probe_opts, state) do
      {:ok, %Response{status: 200} = response, state} ->
        if readonly?(response, state) do
          {:ok, state}
        else
          unavailable(state, "not a readonly server")
        end

      {:ok, %Response{}, state} ->
        unavailable(state, "not a readonly server")

      {:error, reason, state} ->
        unavailable(state, reason)
    end
  end

  defp check_availability(%__MODULE__{} = state, config, probe_opts) do
    request = assemble_headers(@request_availability, nil, state)

    case Client.request(request, probe_opts, state) do
      # 503 means unavailable. In an active-failover cluster it also carries an
      # `x-arango-endpoint` header naming the current leader.
      {:ok, %Response{status: 503} = response, state} ->
        redirect(response, state, config)

      {:ok, %Response{}, state} ->
        {:ok, state}

      # A transport error against one endpoint must not abort the walk.
      {:error, reason, state} ->
        unavailable(state, reason)
    end
  end

  ## Leader redirects

  # A follower in an active-failover setup answers 503 and names the current
  # leader in `x-arango-endpoint`. Following that header means handing the
  # pool's credentials to whatever host the server named, so the target is
  # admitted by policy rather than trusted:
  #
  #   1. it must parse, through `Endpoint.parse/1` — never `Endpoint.new/1`,
  # which raises, and a raise here costs the process its backoff;
  #   2. its normalized origin must already appear in the configured
  #      `:endpoints`, or an explicitly configured `:endpoint_mapper` must
  #      admit it;
  #   3. an encrypted connection may not be redirected to a cleartext one;
  #   4. the number of redirects in one connect attempt is bounded.
  #
  # "Normalized origin" is the parsed `{addr, ssl?}` pair, which is exactly the
  # encryption class, host and port with the scheme vocabulary collapsed. That
  # collapse is required, not a nicety: the server advertises its own vocabulary
  # (`tcp://`, `ssl://`) while users configure `http://`/`https://`, so a
  # literal scheme comparison would refuse every legitimate redirect and the
  # feature would never fire.
  #
  # The comparison is on the *full* origin and not just the host. A configured
  # `db.internal:8529` must not authorize a redirect to `db.internal:9999`,
  # which is a different service on the same machine that would then be sent
  # the pool's credentials.
  #
  # A refused redirect is reported as exactly what it is — an endpoint that
  # answered and is not usable — so it goes through `unavailable/2` like every
  # other such answer: the walk moves on under failover, `:failover_callback`
  # fires, and a single configured endpoint returns the refusal as its error.
  defp redirect(%Response{} = response, %__MODULE__{} = state, config) do
    case redirect_header(response) do
      nil -> unavailable(state, "service unavailable")
      advertised -> admit(advertised, state, config)
    end
  end

  defp redirect_header(%Response{headers: headers}) when is_map(headers) or is_list(headers) do
    Enum.find_value(headers, fn
      {name, value} when is_binary(value) and value != "" ->
        if header_name(name) == @header_redirect, do: value

      _other ->
        nil
    end)
  end

  defp redirect_header(%Response{}), do: nil

  defp header_name(name) when is_binary(name), do: String.downcase(name)
  defp header_name(name), do: name |> to_string() |> String.downcase()

  defp spend_redirect(%{redirects_left: left} = config),
    do: %{config | redirects_left: left - 1}

  defp admit(advertised, %__MODULE__{} = state, %{redirects_left: left}) when left <= 0 do
    unavailable(
      state,
      refused(advertised, "more than #{@max_redirects} redirects in one connect attempt")
    )
  end

  defp admit(advertised, %__MODULE__{} = state, config) do
    case admit_target(advertised, state, config) do
      {:ok, target} ->
        if same_origin?(target, state.parsed_endpoint) do
          # The server named itself while answering 503, which is what an
          # election in progress looks like. Reconnecting would fetch the same
          # 503, and spending redirect budget on it would starve a legitimate
          # redirect later in the walk, so this is simply an unavailable
          # endpoint. The Java driver draws the same line: `failIfNotMatch`
          # only acts when the target differs from the host already in hand.
          unavailable(state, "service unavailable")
        else
          {:redirect, target, state}
        end

      {:error, message} ->
        unavailable(state, message)
    end
  end

  # The current endpoint arrives parsed, never as a binary: the stored binary
  # is redacted and a redacted value does not parse. Fails closed -- an
  # unparseable target, or a state built without a parsed endpoint, is not the
  # same origin.
  defp same_origin?(target, %Endpoint{} = current) do
    case Endpoint.parse(target) do
      {:ok, parsed} -> origin(parsed) == origin(current)
      {:error, _message} -> false
    end
  end

  defp same_origin?(_target, _current), do: false

  defp admit_target(advertised, %__MODULE__{} = state, config) do
    with {:ok, parsed} <- parse_advertised(advertised),
         {:ok, target, target_parsed} <- resolve_target(advertised, parsed, config),
         :ok <- refuse_downgrade(state, target, target_parsed) do
      {:ok, target}
    end
  end

  defp parse_advertised(advertised) do
    case Endpoint.parse(advertised) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, message} -> {:error, refused(advertised, message)}
    end
  end

  # The membership check is against the *configured* `:endpoints`, never against
  # an endpoint an earlier redirect arrived at, so a redirect cannot bootstrap
  # itself into trusting further redirects.
  defp resolve_target(advertised, %Endpoint{} = parsed, config) do
    if configured?(parsed, config) do
      {:ok, advertised, parsed}
    else
      map_target(advertised, parsed, config)
    end
  end

  defp configured?(%Endpoint{} = parsed, %{endpoints: endpoints}) do
    origin = origin(parsed)

    Enum.any?(endpoints, fn endpoint ->
      case Endpoint.parse(endpoint) do
        {:ok, configured} -> origin(configured) == origin
        {:error, _message} -> false
      end
    end)
  end

  # The normalized origin: encryption class, host and port. `Endpoint.parse/1`
  # consumes the scheme into exactly these two fields, so `tcp://` and `http://`
  # (and `ssl://`, `tls://` and `https://`) have already collapsed by the time
  # they are compared.
  defp origin(%Endpoint{addr: addr, ssl?: ssl?}), do: {addr, ssl?}

  defp map_target(advertised, _parsed, %{endpoint_mapper: nil}) do
    {:error,
     refused(
       advertised,
       "its origin is not among the configured :endpoints and no :endpoint_mapper is configured"
     )}
  end

  # An admitted mapper output is validated the same way — it must parse and it
  # must not downgrade encryption — but it is deliberately *not* re-checked
  # against `:endpoints`: remapping to an address the user never configured is
  # the entire point of the option (the container case). That is what makes
  # `:endpoint_mapper` a trust boundary rather than a convenience.
  defp map_target(advertised, parsed, %{endpoint_mapper: mapper}) do
    case call_mapper(mapper, advertised, parsed) do
      {:ok, mapped} ->
        case Endpoint.parse(mapped) do
          {:ok, mapped_parsed} ->
            {:ok, mapped, mapped_parsed}

          {:error, message} ->
            {:error,
             refused(
               advertised,
               ":endpoint_mapper returned #{inspect(Endpoint.redact(mapped))}, which is not a valid " <>
                 "endpoint: " <>
                 message
             )}
        end

      {:refused, why} ->
        {:error, refused(advertised, why)}
    end
  end

  # A mapper is user code running inside `connect/1`. It must fail closed —
  # anything that is not an endpoint binary refuses the redirect — and it must
  # not be able to raise out of the `DBConnection` callback.
  defp call_mapper(mapper, advertised, parsed) when is_map(mapper) do
    case Map.fetch(mapper, advertised) do
      {:ok, mapped} -> {:ok, mapped}
      :error -> lookup_by_origin(mapper, parsed)
    end
  end

  defp call_mapper(mapper, advertised, _parsed) when is_function(mapper, 1),
    do: guarded(fn -> mapper.(advertised) end)

  defp call_mapper({mod, fun, args}, advertised, _parsed)
       when is_atom(mod) and is_atom(fun) and is_list(args),
       do: guarded(fn -> apply(mod, fun, [advertised | args]) end)

  defp call_mapper(invalid, _advertised, _parsed) do
    {:refused,
     ":endpoint_mapper is not a map, a one-argument function or an " <>
       "{module, function, args} tuple, got: #{inspect(invalid)}"}
  end

  # A lookup miss refuses; it never falls through to the advertised value. The
  # keys are matched on their normalized origin as well as literally, because
  # the vocabulary a server advertises in is not the one a user writes: a map
  # keyed `"http://leader:8529"` still answers an advertised
  # `"tcp://leader:8529"`.
  defp lookup_by_origin(mapper, %Endpoint{} = parsed) do
    origin = origin(parsed)

    Enum.find_value(mapper, {:refused, ":endpoint_mapper has no entry for it"}, fn
      {key, mapped} when is_binary(key) ->
        case Endpoint.parse(key) do
          {:ok, key_parsed} -> if origin(key_parsed) == origin, do: {:ok, mapped}
          {:error, _message} -> nil
        end

      _other ->
        nil
    end)
  end

  defp guarded(fun) do
    case fun.() do
      mapped when is_binary(mapped) ->
        {:ok, mapped}

      other ->
        {:refused, ":endpoint_mapper did not admit it, it returned #{inspect(other)}"}
    end
  rescue
    exception ->
      {:refused, ":endpoint_mapper raised #{Exception.message(exception)}"}
  catch
    kind, reason ->
      {:refused, ":endpoint_mapper #{kind}ed with #{inspect(reason)}"}
  end

  # Whether the current connection is encrypted comes from the parsed
  # endpoint; the stored binary is for display only. The target may be a
  # mapper's output -- user code, so it can carry anything -- and is redacted
  # like every endpoint that reaches a message.
  defp refuse_downgrade(
         %__MODULE__{parsed_endpoint: %Endpoint{ssl?: true}} = state,
         target,
         %Endpoint{ssl?: false}
       ) do
    {:error,
     "refused redirect from #{inspect(state.endpoint)} to " <>
       "#{inspect(Endpoint.redact(target))}: an encrypted connection may not be " <>
       "redirected to a cleartext endpoint"}
  end

  defp refuse_downgrade(%__MODULE__{}, _target, %Endpoint{}), do: :ok

  # The advertised value comes off the wire, so it is redacted like any other
  # endpoint before it reaches a message.
  defp refused(advertised, why),
    do: "refused redirect to #{inspect(Endpoint.redact(advertised))}: #{why}"

  defp readonly?(%Response{} = response, %__MODULE__{} = state) do
    case decode_body(response, state) do
      {:ok, %Response{body: %{"mode" => "readonly"}}} -> true
      _other -> false
    end
  end

  # `Ready`. Read the server version once and cache it in connection state, so
  # version-gated behaviour reads it from there instead of probing per request.
  # Anything unreadable or unparseable stays `nil`: unknown is a real answer
  # and gates fail closed on it, where a guessed version would open them.
  defp discover_version(%__MODULE__{} = state, probe_opts) do
    request = assemble_headers(@request_version, nil, state)

    case Client.request(request, probe_opts, state) do
      {:ok, %Response{status: 200} = response, state} ->
        {:ok, %{state | server_version: version_from(response, state)}}

      {:ok, %Response{}, state} ->
        {:ok, %{state | server_version: nil}}

      # The socket just failed mid-connect, so it is not usable. Treat it like
      # any other unavailable endpoint rather than handing a dead socket back.
      {:error, reason, state} ->
        unavailable(state, reason)
    end
  end

  defp version_from(%Response{} = response, %__MODULE__{} = state) do
    case decode_body(response, state) do
      {:ok, %Response{body: %{"version" => version}}} -> parse_version(version)
      _other -> nil
    end
  end

  defp parse_version(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, parsed} -> parsed
      :error -> parse_version_prefix(version)
    end
  end

  defp parse_version(_version), do: nil

  # ArangoDB mostly reports semver ("3.12.5", "3.12.5-1", "3.13.0-devel"), but
  # accept a leading "major.minor" too rather than calling such a server
  # unknown.
  defp parse_version_prefix(version) do
    case Regex.run(~r/^(\d+)\.(\d+)(?:\.(\d+))?/, version) do
      [_match, major, minor] -> build_version(major, minor, "0")
      [_match, major, minor, patch] -> build_version(major, minor, patch)
      nil -> nil
    end
  end

  defp build_version(major, minor, patch) do
    %Version{
      major: String.to_integer(major),
      minor: String.to_integer(minor),
      patch: String.to_integer(patch)
    }
  end

  # Non-raising body decode, for the connect pipeline only. `maybe_decode_body/2`
  # uses `decode!/1`; a server answering a connect probe with a non-JSON body
  # would raise out of `connect/1` and cost the process its backoff.
  defp decode_body(%Response{} = response, %__MODULE__{client: VelocyClient}), do: {:ok, response}

  defp decode_body(%Response{body: nil} = response, %__MODULE__{}), do: {:ok, response}

  defp decode_body(%Response{body: body} = response, %__MODULE__{json_library: json_library})
       when is_binary(body) do
    case json_library.decode(body) do
      {:ok, decoded} -> {:ok, %{response | body: decoded}}
      {:error, _reason} -> :error
    end
  end

  defp decode_body(%Response{} = response, %__MODULE__{}), do: {:ok, response}

  @impl true
  def disconnect(_reason, %__MODULE__{} = state), do: Client.close(state)

  @impl true
  def checkout(%__MODULE__{} = state), do: {:ok, state}

  # Transaction handlers
  #
  # The four `DBConnection` transaction callbacks. Requests are built by
  # `Arangox.Transaction`; the transaction in flight is tracked in
  # `state.trx_id`, which header assembly turns into an `x-arango-trx-id`
  # header on every request, so queries running between begin and
  # commit/rollback join the server-side transaction automatically.
  #
  # "No transaction in flight" is a normal answer, not a failure: each of
  # status/commit/rollback resolves it in its own function head, locally
  # and without a request. Only genuine request failures share the error
  # clauses.

  @impl true
  def handle_begin(_opts, %__MODULE__{trx_id: id} = state) when is_binary(id),
    do: {:transaction, state}

  def handle_begin(opts, %__MODULE__{} = state) do
    request = opts |> Transaction.begin_body() |> Transaction.begin()

    case execute_request(request, opts, state) do
      {:ok, _request, %Response{status: 201, body: %{"result" => %{"id" => id}}} = response,
       state}
      when is_binary(id) ->
        # The identifier is echoed into a request path and a header, so it is
        # held to the same shape the handle form requires rather
        # than trusted because it arrived from the server.
        if Transaction.valid_id?(id) do
          {:ok, response, %{state | trx_id: id}}
        else
          # `{:error, exception, state}` is not among `handle_begin/2`'s
          # documented returns, and `DBConnection` would raise it out of
          # `Arangox.transaction/3` rather than rolling back. A server that
          # answers 201 with an identifier this driver cannot address has
          # left a transaction running that nothing can commit or abort, so
          # the connection goes rather than the call.
          {:disconnect,
           exception(state, "the server returned a malformed transaction identifier"), state}
        end

      # Any other success — including a 201 whose body does not name the
      # transaction — leaves nothing to address later, so it is a failed
      # begin, not a crash.
      {:ok, _request, %Response{}, state} ->
        {:error, state}

      {:error, _exception, state} ->
        {:error, state}

      # Deliberately collapsed, unlike the other three callbacks.
      # DBConnection retires the connection either way: `run_begin`
      # turns any `{status, state}` return into a disconnect with a
      # `DBConnection.TransactionError` (db_connection.ex,
      # `status_disconnect/3`), so this collapse cannot leak a dead socket
      # back into the pool. What it chooses is the caller-facing shape of
      # `Arangox.transaction/3`: a status return becomes `{:error,
      # :rollback}`, while a propagated `{:disconnect, exception, state}`
      # would make `transaction/3` *raise* the underlying `Arangox.Error`.
      # The `{:error, :rollback}` contract is what the integration suite
      # and every caller of `transaction/3` are written against, so it
      # stays.
      {:disconnect, _exception, state} ->
        {:error, state}
    end
  end

  # `handle_status` keeps its server round-trip rather
  # than answering from local state. The transaction is server-side state,
  # and a local answer can lie in both directions — the server aborts
  # transactions on its own (TTL, failover), and a transaction can be
  # finished through another handle to it. The cost concern does not bite:
  # DBConnection's pool-management paths (`DBConnection.run/3` brackets
  # every pool checkout with two status calls) reach this callback on
  # connections with no transaction in flight, which the first head answers
  # locally with no request. The round-trip happens only when a transaction
  # is actually in flight — a caller inside `Arangox.transaction/3` asking
  # a real question — and `Arangox.status/1` documents itself as fetching
  # the status from the database.
  @impl true
  def handle_status(_opts, %__MODULE__{trx_id: nil} = state), do: {:idle, state}

  def handle_status(opts, %__MODULE__{trx_id: id} = state) do
    trx_request(Transaction.status(id), opts, state, :keep, fn response, state ->
      # A transaction committed or aborted through another handle answers
      # `:idle`. Keeping its identifier in state would then send a finished
      # transaction's header on every later request in this checkout, and the
      # next `handle_begin/2` would report a transaction already in flight.
      case trx_status(response.body) do
        :idle -> {:idle, %{state | trx_id: nil}}
        status -> {status, state}
      end
    end)
  end

  @impl true
  def handle_commit(_opts, %__MODULE__{trx_id: nil} = state), do: {:idle, state}

  def handle_commit(opts, %__MODULE__{trx_id: id} = state) do
    trx_request(Transaction.commit(id), opts, state, :strip, fn response, state ->
      {:ok, response, state}
    end)
  end

  @impl true
  def handle_rollback(_opts, %__MODULE__{trx_id: nil} = state), do: {:idle, state}

  def handle_rollback(opts, %__MODULE__{trx_id: id} = state) do
    trx_request(Transaction.abort(id), opts, state, :strip, fn response, state ->
      {:ok, response, state}
    end)
  end

  # The shared shape of status/commit/rollback: one request against
  # the transaction, expecting 200. The callbacks differ on exactly three
  # axes — the request (its HTTP method), whether the outgoing request
  # still carries the transaction header, and what a 200 becomes — so those
  # are the parameters; everything else is identical, including the
  # expected status.
  #
  # `wire` is `:keep` for status (the probe runs inside the transaction, as
  # it always has) and `:strip` for commit/rollback (the terminal request
  # addresses the transaction by path and has never carried the header).
  #
  # The transaction header leaves *state* only when the server
  # acknowledges the request. On any failure short of a disconnect the
  # returned state still names the transaction, so DBConnection's follow-up
  # rollback — its response to `{:error, state}` from `handle_commit` —
  # addresses the real server-side transaction instead of finding none in
  # flight. Dropping the header before that acknowledgment strands the
  # server-side transaction: it stays alive holding its locks until the server
  # times it out, with nothing left able to name it.
  # The identifier is read off the state itself rather than passed alongside
  # it: a second copy could disagree, and `retain_trx/3` would then rewrite
  # state to name a different transaction than the one in flight.
  defp trx_request(%Request{} = request, opts, %__MODULE__{trx_id: id} = state, wire, on_200) do
    request_state = if wire == :strip, do: %{state | trx_id: nil}, else: state

    case execute_request(request, opts, request_state) do
      {:ok, _request, %Response{status: 200} = response, state} ->
        on_200.(response, state)

      {:ok, _request, %Response{}, state} ->
        {:error, retain_trx(state, id, wire)}

      {:error, _exception, state} ->
        {:error, retain_trx(state, id, wire)}

      {:disconnect, exception, state} ->
        {:disconnect, exception, state}
    end
  end

  defp retain_trx(state, _id, :keep), do: state
  defp retain_trx(state, id, :strip), do: %{state | trx_id: id}

  # `GET /_api/transaction/{id}` answers 200 for any transaction the server
  # still remembers; the actual state is in the body:
  #
  #     {"code":200,"error":false,"result":{"id":"...","status":"running"}}
  #
  # The status line is not the answer: a 200 means the server answered, not
  # that a transaction is running, so matching on it alone reports
  # :transaction for one the server has already aborted or committed.
  # "committed" means no transaction is in flight any more, which in
  # DBConnection's vocabulary is :idle; "aborted" — and any status this
  # driver does not recognize — reports :error, DBConnection's "inside an
  # aborted transaction", whose recovery path (a rollback) is safe in
  # either case.
  defp trx_status(%{"result" => %{"status" => "running"}}), do: :transaction
  defp trx_status(%{"result" => %{"status" => "committed"}}), do: :idle
  defp trx_status(_aborted_or_unrecognized), do: :error

  # The cursor collection, and the path a single cursor is addressed at. The
  # latter is shared with `encode_cursor_id/1`, which is the only thing that
  # percent-encodes what follows it; a second spelling of that prefix
  # would silently escape the encoding.
  @cursor_collection "/_api/cursor"
  @cursor_path @cursor_collection <> "/"

  @impl true
  def handle_declare(%Query{} = query, params, opts, %__MODULE__{} = state) do
    # The plan cache stays opt-in for a streamed query, though the cache is
    # server-side and keyed by the statement, so a cursor would benefit from
    # one exactly as a drained execution does.
    #
    # ArangoDB has no
    # server-side prepare, so asking for the plan cache is the only observable
    # difference between a prepared execution and any other, and defaulting it
    # on here would erase that difference entirely. It would also put every
    # streamed query behind the plan cache's version gate, which fails closed below the
    # plan-cache floor — the 3.11 tier this driver still supports. A caller who
    # wants it on a cursor passes `use_plan_cache: true` like any other option.
    with {:ok, body} <- Query.body(query, params, opts),
         :ok <- gate_plan_cache(body, state) do
      request = %Request{method: :post, path: @cursor_collection, body: body}

      case execute_request(request, opts, state) do
        {:ok, _req, %Response{body: %{"id" => cursor}} = initial, state} ->
          {:ok, query, cursor, %{state | cursors: Map.put(state.cursors, cursor, initial)}}

        # Unaddressable: no request can ever name the batches the server is
        # holding back, so streaming would deliver this first batch and then
        # have nowhere to go. The response was fully read; the connection is
        # healthy and stays checked in.
        {:ok, _req, %Response{body: %{"hasMore" => true}}, state} ->
          {:error,
           %Error{
             message:
               "the server promised more batches (hasMore) without a cursor id, " <>
                 "so the rest of the result can never be fetched"
           }, state}

        # A single-batch result: the server issued no id, so this cursor
        # exists only in driver memory. A reference keys it — a reference
        # cannot be interpolated into a request path even by accident, and
        # `handle_fetch/4`/`handle_deallocate/4` answer it locally.
        {:ok, _req, %Response{} = initial, state} ->
          cursor = make_ref()
          {:ok, query, cursor, %{state | cursors: Map.put(state.cursors, cursor, initial)}}

        {call, exception, state} when call in [:error, :disconnect] ->
          {call, exception, state}
      end
    else
      {:error, %Error{} = exception} -> {:error, exception(state, exception), state}
    end
  end

  # Written as the two questions it actually asks. An `else` on a
  # `with` here must not match its own head's success shapes, and a bare
  # `error -> error` clause would forward `handle_execute/4`'s four-tuple
  # where `DBConnection` expects `{:cont | :halt, result, state}` whenever a
  # batch response carries no `hasMore` key at all.
  #
  # The first question is whether the initial response from `handle_declare/4`
  # is still undelivered — it is held in `state.cursors` precisely so the first
  # batch is not fetched twice. The second is what the server said. A response
  # that does not promise more is the last one either way, which is what the
  # missing `hasMore` key now means instead of a leaked tuple.
  @impl true
  def handle_fetch(_query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    case Map.pop(cursors, cursor) do
      {%Response{} = initial, remaining} ->
        deliver(initial, cursor, remaining, state)

      # An absent entry means the next batch lives on the server — for a
      # cursor the server issued. A reference is driver-local: its single
      # batch was already delivered (or never stored), and there is nothing on
      # the server to ask.
      {nil, _cursors} when is_reference(cursor) ->
        {:error, %Error{message: "a driver-local cursor has no further batches to fetch"}, state}

      {nil, _cursors} ->
        fetch_batch(cursor, opts, state)
    end
  end

  defp fetch_batch(cursor, opts, %__MODULE__{} = state) do
    request = %Request{method: :put, path: @cursor_path <> cursor}

    case execute_request(request, opts, state) do
      {:ok, _req, %Response{} = response, state} ->
        deliver(response, cursor, state.cursors, state)

      {call, exception, state} when call in [:error, :disconnect] ->
        {call, exception, state}
    end
  end

  # A cursor the server has finished with is marked `:noop` rather than
  # forgotten, so `handle_deallocate/4` knows there is nothing left to delete.
  defp deliver(%Response{body: %{"hasMore" => true}} = response, _cursor, cursors, state),
    do: {:cont, response, %{state | cursors: cursors}}

  defp deliver(%Response{} = response, cursor, cursors, state),
    do: {:halt, response, %{state | cursors: Map.put(cursors, cursor, :noop)}}

  @impl true
  def handle_deallocate(_query, cursor, opts, %__MODULE__{cursors: cursors} = state) do
    state = %{state | cursors: Map.delete(cursors, cursor)}

    case cursors do
      %{^cursor => :noop} ->
        {:ok, :noop, state}

      # A driver-local cursor was never issued by the server — abandoned
      # before its batch was delivered, there is still nothing to delete.
      _ when is_reference(cursor) ->
        {:ok, :noop, state}

      _ ->
        request = %Request{method: :delete, path: @cursor_path <> cursor}

        case execute_request(request, opts, state) do
          {:ok, _req, response, state} ->
            {:ok, response, state}

          {call, exception, state} when call in [:error, :disconnect] ->
            {call, exception, state}
        end
    end
  end

  # DECISION: `ping/1` is bounded by the pool's `:request_timeout`.
  #
  # It runs on `DBConnection`'s idle cycle, in the *connection* process, with no
  # caller and therefore no deadline to inherit — the third budget case
  # alongside caller requests and connect probes. It is a request, so the
  # request bound is the one that fits: `run_execute/4` establishes a
  # request-local deadline of `:request_timeout` for any request that arrives
  # without one, which is exactly this path. A ping is deliberately *not* given
  # the connect budget: it is not part of connecting, and an idle pool whose
  # server has gone quiet should retire the connection on the same clock a real
  # request would.
  @impl true
  def ping(%__MODULE__{} = state) do
    case execute_request(@request_ping, [], state) do
      {:ok, _request, %Response{}, state} ->
        {:ok, state}

      {call, exception, state} when call in [:error, :disconnect] ->
        {:disconnect, exception, state}
    end
  end

  # Two honest clauses. A prepared query builds its own request and hands
  # the *query* back in the callback's query position, so `decode/3` dispatches
  # on the query rather than on a request and the caller gets the struct they
  # prepared back for reuse.
  #
  # Must not match on the query argument, which is what required extracting the
  # request first: the three cursor callbacks pass their own query
  # alongside the request they built, and a query-matching clause catches all
  # three here and sends a cursor body in place of that request.
  @impl true
  def handle_execute(%Query{} = query, params, opts, %__MODULE__{} = state) do
    with {:ok, body} <- Query.body(query, params, opts),
         :ok <- gate_plan_cache(body, state) do
      request = %Request{method: :post, path: @cursor_collection, body: body}

      case execute_request(request, opts, state) do
        {:ok, _req, %Response{} = response, state} ->
          drain(query, response, opts, state)

        {call, exception, state} when call in [:error, :disconnect] ->
          {call, exception, state}
      end
    else
      {:error, %Error{} = exception} -> {:error, exception(state, exception), state}
    end
  end

  def handle_execute(_q, %Request{} = request, opts, %__MODULE__{} = state),
    do: execute_request(request, opts, state)

  # A cursor response carrying `hasMore: true` would otherwise leak a
  # server-side cursor and silently truncate the result, so execute stays a
  # complete-result function and drains the batches here. Callers who want the
  # batches lazily use `Arangox.cursor/4`, which is the same server cursor read
  # one batch at a time.
  #
  # The initial response is what carries the query's own metadata, so it is the
  # one handed back, with the accumulated rows in place of its first batch and
  # `hasMore` answered honestly. Nothing deletes the cursor afterwards because
  # a fully drained cursor no longer exists server-side.
  defp drain(%Query{} = query, %Response{} = initial, opts, %__MODULE__{} = state) do
    case collect(initial, [rows(initial)], opts, state) do
      {:ok, rows, state} ->
        body = initial.body |> Map.put("result", rows) |> Map.put("hasMore", false)
        {:ok, query, %{initial | body: body}, state}

      {call, exception, state} ->
        {call, exception, state}
    end
  end

  # The accumulator is a list of batches, newest first, flattened once at the
  # end: appending each batch to a flat list instead re-copies everything
  # collected so far on every batch, which is quadratic in exactly the
  # many-batch case draining exists for.
  defp collect(%Response{body: %{"hasMore" => true, "id" => id}}, batches, opts, state) do
    request = %Request{method: :put, path: @cursor_path <> id}

    case execute_request(request, opts, state) do
      {:ok, _req, %Response{} = next, state} ->
        collect(next, [rows(next) | batches], opts, state)

      {call, exception, state} when call in [:error, :disconnect] ->
        {call, exception, state}
    end
  end

  # `hasMore` with no cursor to fetch it from is a promise the server cannot
  # keep. Returning the rows collected so far would truncate the result
  # silently, so it is an error instead.
  defp collect(%Response{body: %{"hasMore" => true}}, _batches, _opts, state) do
    {:error,
     exception(
       state,
       %Error{message: "the server reported more batches but named no cursor to fetch them from"}
     ), state}
  end

  defp collect(%Response{}, batches, _opts, state),
    do: {:ok, batches |> Enum.reverse() |> Enum.concat(), state}

  defp rows(%Response{body: %{"result" => rows}}) when is_list(rows), do: rows
  defp rows(%Response{}), do: []

  ## The plan cache's version gate

  # The floor `usePlanCache` was introduced at. Below it the option is not
  # merely unsupported — it is *ignored*, measured: 3.11 answers 201 with the
  # full result, no key, and no complaint, exactly as it does for an option name
  # invented on the spot. So a caller who asked for plan caching and did not get
  # it would never find out from the server. That silence is the whole reason
  # this gate exists, and the reason it cannot be relaxed into letting the
  # server object for itself.
  @plan_cache_floor Version.parse!("3.12.4")

  # Gates on what is actually about to be sent rather than on how the option was
  # resolved, so a plan-cache request arriving through `:properties` is caught
  # on the same rule as one that came through `use_plan_cache`.
  #
  # A query that did not ask is never gated, which is what keeps every other
  # query working against servers below the floor.
  defp gate_plan_cache(body, %__MODULE__{} = state) do
    if plan_cache_requested?(body), do: plan_cache_supported?(state), else: :ok
  end

  # `:properties` passes body attributes through verbatim under the server's
  # own names, so `%{"options" => %{"usePlanCache" => true}}` is valid input
  # and asks for the cache as surely as the mapped option does. An atom-only
  # lookup misses it, and the request then reaches a server below the floor
  # that ignores the option silently — the outcome this gate exists to prevent.
  defp plan_cache_requested?(body) do
    # Both containers are examined, not just the first one present: a mapped
    # option writes `:options` while `:properties` merges `"options"`
    # verbatim, so one body can carry both and the flag may be in either.
    [Map.get(body, :options), Map.get(body, "options")]
    |> Enum.any?(&plan_cache_flag?/1)
  end

  defp plan_cache_flag?(options) when is_map(options) do
    Map.get(options, :usePlanCache) == true or Map.get(options, "usePlanCache") == true
  end

  defp plan_cache_flag?(_options), do: false

  defp plan_cache_supported?(%__MODULE__{server_version: %Version{} = version}) do
    if Version.compare(version, @plan_cache_floor) == :lt do
      {:error,
       %Error{
         message:
           "the plan cache requires ArangoDB #{@plan_cache_floor} or newer, and this server " <>
             "reports #{version}. Below that the option is ignored rather than refused, so the " <>
             "query would have run uncached without saying so. Drop use_plan_cache to run it " <>
             "anyway"
       }}
    else
      :ok
    end
  end

  # Fails closed. An unknown version means `discover_version/2` could not parse
  # what the server reported, and proceeding optimistically would send the
  # option to a server that may well ignore it — the failure this gate exists to
  # make visible, arrived at by guessing.
  defp plan_cache_supported?(%__MODULE__{server_version: nil}) do
    {:error,
     %Error{
       message:
         "the plan cache requires ArangoDB #{@plan_cache_floor} or newer and this server's " <>
           "version could not be determined, so the requirement cannot be checked. Below the " <>
           "floor the option is ignored rather than refused, so proceeding would risk running " <>
           "uncached without saying so. Drop use_plan_cache to run it anyway"
     }}
  end

  # The shared request seam.
  #
  # Every request this driver makes crosses this function: the hand-written
  # ones `DBConnection` routes through `handle_execute/4`, the transaction
  # callbacks, `ping/1`, the three cursor callbacks, and the `Arangox.Api.*`
  # operations. That is what makes it the one place path interpolation can be
  # validated.
  #
  # The internal call sites reach it *directly* rather than going back through
  # the callback, and that is the point of the extraction rather than a
  # tidiness argument. `handle_declare`, `handle_fetch` and `handle_deallocate`
  # each pass their own query along with the request they built; a callback
  # clause dispatching on the query argument
  # would therefore intercept all three and send a cursor body in place of the
  # request they intended. Calling this function removes the hazard by
  # construction, and there is no `nil` query left to pass.
  #
  # The `:transaction` per-request option is applied here for the same
  # reason. The header goes onto the *request struct* and never into
  # `state.headers`: a transaction written to connection state would ride the
  # checked-in connection to whichever unrelated caller draws it next, which
  # is exactly the leak the handle form exists to prevent. The request is a
  # local value, and the returned state is whatever `Client.request/3` hands
  # back — nothing in this path constructs a new state from the transaction.
  #
  # It is applied *before* the state-header merge, whose merge order lets the
  # request's own headers win, so a per-request handle deliberately overrides
  # a closure-form transaction the connection may be inside of — per-request
  # identity is the more specific of the two.
  #
  # An invalid option is a plain `{:error, exception, state}`: the request
  # never reaches the wire, and the connection — which was never touched —
  # stays checked in and healthy. Raising here instead would make DBConnection
  # retire a perfectly good connection over a caller's typo.
  defp execute_request(%Request{} = request, opts, %__MODULE__{} = state) do
    with :ok <- check_request_timeout(opts),
         {:ok, option_trx} <- transaction_option(opts),
         {:ok, %Request{} = request} <- interpolate_path(request, opts, state) do
      run_execute(request, option_trx, opts, state)
    else
      {:error, %Error{} = exception} -> {:error, exception(state, exception), state}
    end
  end

  # `:request_timeout` is validated per request as well as at pool start.
  # Like an invalid `:transaction`, an invalid value is a plain
  # `{:error, exception, state}` — nothing reached the wire, so the connection
  # is healthy and stays checked in.
  defp check_request_timeout(opts) do
    case Keyword.fetch(opts, :request_timeout) do
      :error ->
        :ok

      {:ok, value} ->
        case Client.validate_request_timeout(value) do
          :ok -> :ok
          {:error, message} -> {:error, %Error{message: message}}
        end
    end
  end

  defp run_execute(%Request{} = request, option_trx, opts, %__MODULE__{} = state) do
    # The codec is chosen from the request's *own* headers, before assembly:
    # after it, the caller's content-type could not be told apart from one
    # configured on the pool's `:headers` list, whose entries ride the wire
    # but never select a codec (the `:content_type` option does that).
    codec = effective_request_codec(request, state)

    case request |> assemble_headers(option_trx, state) |> maybe_encode_body(codec, state) do
      {:ok, %Request{} = request} ->
        request = accept_header(request, state)
        opts = with_deadline(opts, state)

        case Client.socket_timeout(Keyword.fetch!(opts, :deadline), opts, state) do
          {:ok, _timeout} -> do_run_execute(request, opts, state)
          :elapsed -> {:error, exception(state, elapsed_error()), state}
        end

      {:error, %Error{} = exception} ->
        {:error, exception(state, exception), state}
    end
  end

  ## The timeout budget

  # Guarantees `opts[:deadline]`: the absolute monotonic instant this request
  # has to be done by, in milliseconds.
  #
  # The caller's own deadline is preferred, because it was stamped when the
  # caller entered the pool and has already been ticking through checkout. The
  # enclosing `Arangox.run/3` or `Arangox.transaction/3` block contributes a
  # second one, which is what keeps a long block's later requests inside the
  # single deadline `DBConnection` armed at the block's checkout — without it,
  # every request in the block would start a fresh budget and the last ones
  # would outlive the connection.
  #
  # Only when neither exists — `ping/1`, or a pool driven through
  # `DBConnection` directly — is one established here, from
  # `:request_timeout`. That is honest rather than lax: there is no earlier
  # instant to measure from on those paths, and the alternative is an
  # unbounded wait.
  #
  # The block's deadline is read **only** when `opts` carries no `:deadline` at
  # all. `Arangox` stamps the key on every request it hands to `DBConnection`,
  # having already decided whether the enclosing block applies to it (see
  # `Arangox.block_deadline/1`), so re-consulting the carrier here could only
  # second-guess a correct decision — and would put back exactly the bug
  # `block_deadline/1` removes, since a request to an unrelated pool arrives
  # here carrying its own correctly-stamped deadline. `deadline: nil` is that
  # decision saying "no block deadline applies", which is why it is answered
  # with the request-local fallback rather than with the carrier.
  #
  # An absent key means the request never passed through `Arangox`: a cursor's
  # per-batch fetches (`DBConnection` invokes `handle_fetch/4` itself, with the
  # stream's option list), the transaction callbacks, `ping/1`. Those are the
  # requests the carrier exists for.
  defp with_deadline(opts, %__MODULE__{} = state) do
    deadline =
      case Keyword.fetch(opts, :deadline) do
        {:ok, stamped} when is_integer(stamped) -> stamped
        {:ok, _decided_unbounded} -> nil
        :error -> caller_deadline()
      end

    deadline =
      if is_integer(deadline),
        do: deadline,
        else: Client.monotonic_ms() + internal_budget(opts, state)

    Keyword.put(opts, :deadline, deadline)
  end

  # The budget for a request that arrives with no caller deadline — `ping/1`
  # and direct `DBConnection` callers. `Client.socket_timeout/3` spends
  # `timeout_margin/0` and refuses to start below `min_socket_timeout/0`, so a
  # `:request_timeout` under their sum could never reach the wire from here:
  # every idle ping would elapse before the send and disconnect a healthy
  # pool once per idle interval, forever. Ordinary requests are unaffected —
  # their deadline is stamped from `:timeout` at pool entry.
  defp internal_budget(opts, state) do
    max(
      Client.request_timeout(opts, state),
      Client.timeout_margin() + Client.min_socket_timeout()
    )
  end

  # A remainder too small to spend is refused before anything
  # is written, so no round trip is started whose answer cannot be read.
  #
  # Deliberately *not* a connection-lost reason: nothing went on the wire, the
  # socket is untouched, and disconnecting here would destroy a healthy
  # connection every time a caller queued too long — precisely when connections
  # are scarce and destroying them makes the queue worse.
  defp elapsed_error do
    %Error{
      reason: :deadline_exceeded,
      message:
        "the request timeout budget was already spent before the request could be sent " <>
          "(less than #{Client.min_socket_timeout()}ms of it remained); no request was made"
    }
  end

  # The caller's deadline for an enclosing `Arangox.run/3` or
  # `Arangox.transaction/3` block, if this process is inside one.
  #
  # It travels in the process dictionary rather than in `opts` because it has to
  # reach requests arangox never sees the options of: a cursor's per-batch
  # fetches, and the `handle_begin`/`handle_status`/`handle_commit` callbacks
  # `DBConnection` invokes with its own option list. Every `handle_*` callback
  # runs in the *caller's* process (`db_connection/holder.ex`, the
  # `## Pool API (invoked by caller)` boundary), and so does the block's
  # function, so the two are always the same process. `ping/1` and the connect
  # pipeline run in the connection process instead, which is why they never see
  # a stale value.
  #
  # It is per *process*, not per pool, so on its own it cannot tell a request
  # that belongs to the block from one issued to an unrelated pool from inside
  # it. That distinction is made where the answer is available — in `Arangox`,
  # which has the `conn` argument and can see whether it is the block's own
  # `%DBConnection{}` — and travels here as a stamped `:deadline`, which is why
  # the reader above consults this carrier only for requests that carry no
  # stamp. Nothing needs `DBConnection`'s private `pool_ref` record for that.
  @caller_deadline_key {__MODULE__, :caller_deadline}

  @doc false
  @spec caller_deadline() :: integer | nil
  def caller_deadline, do: Process.get(@caller_deadline_key)

  @doc false
  @spec put_caller_deadline(integer | nil) :: integer | nil
  def put_caller_deadline(deadline), do: Process.put(@caller_deadline_key, deadline)

  @doc false
  @spec restore_caller_deadline(integer | nil) :: :ok
  def restore_caller_deadline(nil) do
    Process.delete(@caller_deadline_key)
    :ok
  end

  def restore_caller_deadline(deadline) do
    Process.put(@caller_deadline_key, deadline)
    :ok
  end

  defp do_run_execute(%Request{} = request, opts, %__MODULE__{} = state) do
    case Client.request(request, opts, state) do
      {:ok, %Response{status: status} = response, state} when status in 400..599 ->
        {
          err_or_disc(status, state.disconnect_on_error_codes),
          exception(state, response),
          state
        }

      {:ok, response, state} ->
        case maybe_decode_body(response, state) do
          {:ok, response} ->
            {:ok, sanitize_headers(request), response, state}

          # The response was fully read off the socket, so the connection is
          # healthy and stays checked in; only its body failed the codec.
          {:error, %Error{} = exception} ->
            {:error, exception(state, exception), state}
        end

      # The client contract carries the socket-gone signal in
      # `:reason`, replacing the `{:error, :noproc, state}` sentinel. Getting
      # this wrong is not cosmetic: a dead socket returned as an ordinary
      # `{:error, ...}` stays checked into the pool and poisons every later
      # checkout that draws it.
      {:error, %Error{} = exception, state} ->
        {error_or_disconnect(exception), stamp(state, exception), state}

      # Legacy adapter for a third-party client that predates the one-error
      # contract. Everything arangox ships takes the clause above.
      {:error, reason, state} ->
        exception = exception(state, reason)

        {error_or_disconnect(exception), exception, state}
    end
  end

  defp error_or_disconnect(%Error{} = exception) do
    if Client.connection_lost?(exception), do: :disconnect, else: :error
  end

  # A client cannot know the configured endpoint (it is handed a parsed one), so
  # the redacted endpoint is stamped on here rather than left blank.
  defp stamp(%__MODULE__{endpoint: endpoint}, %Error{endpoint: nil} = exception),
    do: %{exception | endpoint: endpoint}

  defp stamp(%__MODULE__{}, %Error{} = exception), do: exception

  defp err_or_disc(status, codes) do
    if status in codes, do: :disconnect, else: :error
  end

  # Resolves the `:transaction` option into a validated identifier for header
  # assembly. Only an `%Arangox.Transaction{}` holding an identifier that
  # passes shape validation is accepted: the identifier is a bearer
  # capability, so a bare binary is refused outright, and a malformed
  # identifier — control characters, anything non-digit — is rejected *here*,
  # before it can touch a header or the wire. The rejected value is never
  # echoed into the error.
  defp transaction_option(opts) do
    case Keyword.fetch(opts, :transaction) do
      :error ->
        {:ok, nil}

      {:ok, %Transaction{} = trx} ->
        Transaction.fetch_id(trx)

      {:ok, other} ->
        {:error,
         %Error{
           message:
             "the :transaction option accepts only an %Arangox.Transaction{} handle " <>
               "(from Arangox.begin_transaction/2 or Arangox.Transaction.new/1), never " <>
               "a bare identifier. Got: #{describe_transaction_value(other)} (the value " <>
               "is not echoed, in case it is a live transaction identifier)."
         }}
    end
  end

  # Describes the type only. A bare binary handed to `:transaction` is most
  # likely a real transaction identifier, which must not reach an error
  # message or a log.
  defp describe_transaction_value(%module{}), do: "a #{inspect(module)} struct"
  defp describe_transaction_value(value) when is_binary(value), do: "a binary"
  defp describe_transaction_value(value) when is_atom(value), do: "an atom"
  defp describe_transaction_value(value) when is_integer(value), do: "an integer"
  defp describe_transaction_value(value) when is_list(value), do: "a list"
  defp describe_transaction_value(value) when is_map(value), do: "a map"
  defp describe_transaction_value(_value), do: "an unsupported value"

  # Prepare and close

  # ArangoDB has no prepared statements. What it has is a plan cache — a
  # server-side memoisation of parsing and planning, keyed by statement text and
  # shared across every caller in the database. Measured against 3.12.4: the
  # first execution populates an entry, the *second* reports the key that served
  # it, and changing a bind value hits that same entry. So the reuse comes from
  # running the same text again, and a value held on the client has no part in
  # it.
  #
  # Implementing `handle_prepare/3` anyway would spend a pool checkout —
  # `DBConnection.prepare/3` runs through `run/4` and never touches the socket —
  # to set a boolean the caller can set directly, while borrowing a word that
  # everywhere else in this ecosystem means a round trip and a server-side
  # handle.
  @impl true
  def handle_prepare(%Query{}, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_no_prepare | endpoint: state.endpoint}, state}

  def handle_prepare(_q, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_not_a_query | endpoint: state.endpoint}, state}

  # Closing is a no-op that issues no request: the server has no
  # per-plan release, and the plan cache is managed as a whole rather than
  # entry by entry. Nothing prepares, so the caller reaching here is either
  # `DBConnection` unwinding after `describe/2` or `encode/3` raised, or someone
  # closing a query they built — neither has anything to release.
  @impl true
  def handle_close(%Query{}, _opts, %__MODULE__{} = state), do: {:ok, :noop, state}

  # Step 9's catch-all. `DBConnection` closes whatever it was handed whenever
  # `describe/2` or `encode/3` raises, including values this driver never
  # produces, so this clause answers instead of raising a second error over the
  # first one.
  def handle_close(_q, _opts, %__MODULE__{} = state),
    do: {:error, %{@exception_not_a_query | endpoint: state.endpoint}, state}

  # Utils

  defp put_header(%__MODULE__{headers: headers} = struct, {_key, _value} = header),
    do: %{struct | headers: headers ++ [header]}

  # The one header-precedence rule (0.8): connection headers first, then the
  # transaction identifier the driver manages, then the request's own headers,
  # order preserved and duplicates delivered as given. Nothing is merged,
  # deduplicated or re-cased — a caller who sends the same name twice sends it
  # twice.
  #
  # A request that already names a transaction header — whatever the casing —
  # runs under that header alone: adding the connection's identifier next to
  # it would put two transaction identities on one request, which the server
  # may bind to either. The per-request `:transaction` option outranks the
  # connection's in-flight identifier the same way.
  defp assemble_headers(%Request{headers: req_headers} = request, option_trx, state) do
    %__MODULE__{headers: conn_headers, trx_id: state_trx} = state

    %{
      request
      | headers: conn_headers ++ trx_entry(option_trx || state_trx, req_headers) ++ req_headers
    }
  end

  defp trx_entry(nil, _req_headers), do: []

  defp trx_entry(id, req_headers) do
    if has_header?(req_headers, @header_trx_id), do: [], else: [{@header_trx_id, id}]
  end

  # `lower_name` must already be lowercase. Tolerates non-tuple entries so a
  # malformed caller list fails at the transport with its own error, not here.
  defp has_header?(headers, lower_name) do
    Enum.any?(headers, fn
      {name, _value} -> String.downcase(to_string(name)) == lower_name
      _other -> false
    end)
  end

  # The request struct echoed back to the caller is precisely the struct people
  # log, so its sensitive values are scrubbed on the way out. What went on the
  # wire is the real thing; only the echo is scrubbed. Which names count lives
  # on `Arangox.Request` so the two `Inspect` implementations and this
  # sanitizer share one definition.

  defp sanitize_headers(%Request{headers: headers} = request) when is_list(headers) do
    headers =
      Enum.map(headers, fn
        {name, value} ->
          if Request.sensitive_header?(name), do: {name, "[redacted]"}, else: {name, value}

        other ->
          other
      end)

    %{request | headers: headers}
  end

  ## Path interpolation

  # The request-time half of path validation. Exactly two values are interpolated into a request
  # path by this driver — the `:database` and the server-supplied cursor
  # identifier — and both are handled here, inside the one function every
  # request crosses. The other half runs at option validation
  # (`Arangox.start_link/1`); both halves share `validate_database/1`, so there
  # is one rule with two entry points rather than two rules that can drift.
  #
  # A rejection is a plain `{:error, %Error{}}`, like an invalid `:transaction`
  # or `:request_timeout`: nothing was written, so the connection is untouched
  # and stays checked in. Raising or disconnecting would retire a healthy
  # connection over a caller's typo.
  #
  # Exposed (undocumented) because the VelocyStream branch below decides what a
  # path *would* carry for a client that cannot be reached without a
  # VelocyStream server.
  @doc false
  @spec interpolate_path(Request.t(), keyword, t) :: {:ok, Request.t()} | {:error, Error.t()}
  def interpolate_path(%Request{} = request, opts, %__MODULE__{} = state) do
    request = encode_cursor_id(request)

    # The option is checked whenever it is present, whether or not this
    # particular path ends up carrying it. A value that cannot name a database
    # is refused either way, so the same call does not start working because of
    # where it happens to point.
    case Keyword.fetch(opts, :database) do
      {:ok, database} -> prepend_validated(request, database, state)
      :error -> do_db_prepend(request, state)
    end
  end

  # The one validate-then-prepend step, shared by the per-request option and
  # the pool's own database so the two cannot drift.
  defp prepend_validated(%Request{} = request, database, %__MODULE__{} = state) do
    case validate_database(database) do
      :ok -> {:ok, prepend_database(request, database, state)}
      {:error, message} -> {:error, %Error{message: message}}
    end
  end

  # VelocyStream reads the connection's database from state rather than from a
  # path, and a `nil` one means the server's default (`_system`).
  defp do_db_prepend(%Request{} = request, %__MODULE__{client: VelocyClient}),
    do: {:ok, request}

  defp do_db_prepend(%Request{} = request, %__MODULE__{database: nil}),
    do: {:ok, request}

  # The connection's own database is validated here too, not only at start-up:
  # a pool started through `DBConnection.start_link/2` directly never crossed
  # `Arangox.start_link/1`'s option validation, and the rule is about what reaches a
  # socket, not about which entry point built the pool.
  defp do_db_prepend(%Request{} = request, %__MODULE__{database: db} = state),
    do: prepend_validated(request, db, state)

  # "Every request that isn't already prepended", as `Arangox.start_link/1`
  # documents it — one rule for the pool option and the per-request one alike.
  # A path the caller already prefixed wins — they named a database explicitly
  # and it is not this function's to override. Prepending regardless produces
  # `/_db/b/_db/a/...`, which no server can answer.
  defp prepend_database(%Request{path: "/_db/" <> _} = request, _database, %__MODULE__{}),
    do: request

  defp prepend_database(%Request{path: path} = request, database, %__MODULE__{} = state),
    do: %{request | path: "/_db/" <> encode_database(database, state) <> path}

  # VelocyStream carries the database as a message field, not as a path
  # segment: `Arangox.VelocyClient.request/3` splits the `/_db/` prefix back
  # off and sends what it finds there as the database. An encoded name would
  # arrive percent-encoded and address a database that does not exist, so for
  # that client the prefix stays raw — it is a carrier, not a URL. Validation
  # still applies: a name that can alter a path is refused whatever the
  # transport, because the same option reaches an HTTP pool unchanged.
  defp encode_database(database, %__MODULE__{client: VelocyClient}), do: database
  defp encode_database(database, %__MODULE__{}), do: encode_segment(database)

  # The cursor identifier is the server's own value echoed straight back into a
  # path. Encoding it here rather than at the two callbacks that build that
  # path is what keeps the one-seam promise: the `Arangox.Api.*` cursor
  # operations interpolate the same identifier into the same path and reach the
  # wire through this function too, so they inherit the encoding instead of
  # needing their own.
  defp encode_cursor_id(%Request{path: @cursor_path <> id} = request) when id != "",
    do: %{request | path: @cursor_path <> encode_segment(id)}

  defp encode_cursor_id(%Request{} = request), do: request

  # Percent-encodes everything outside RFC 3986's unreserved set. Traditional
  # ArangoDB names — letters, digits, `-`, `_` — pass through untouched;
  # extended names carrying spaces or unicode are encoded, which is what makes
  # them legal in a path at all.
  defp encode_segment(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @doc false
  # The interpolation rule, in one place, in the module that owns the seam.
  # `Arangox.start_link/1` raises on a bad value at option validation; the
  # request seam answers with the same message inside an `%Arangox.Error{}`.
  #
  # Rejects only bytes that can alter the request path: the path separator,
  # query and fragment delimiters, the percent-encoding escape and control
  # characters. Anything else — spaces, unicode — is a legal ArangoDB extended
  # database name, answered with encoding rather than rejection.
  @spec validate_database(term) :: :ok | {:error, String.t()}
  def validate_database(database) when not is_binary(database),
    do: {:error, "The :database option expects a binary, got: #{inspect(database)}"}

  def validate_database(database) when database in ["", ".", ".."],
    do: {:error, ~s(The :database option cannot be empty, "." or "..", got: #{inspect(database)})}

  def validate_database(database) do
    if database_has_forbidden_byte?(database) do
      {:error,
       ~s(The :database option cannot contain "/", "?", "#", "%" or control characters, ) <>
         "since they would alter the request path, got: #{inspect(database)}"}
    else
      :ok
    end
  end

  defp database_has_forbidden_byte?(name), do: Client.path_altering_byte?(name)

  ## The content-type seam

  @content_type_json "application/json"
  @content_type_vpack "application/x-velocypack"
  @content_type_dump "application/x-arango-dump"

  # VelocyStream carries its own body encoding, so the codec seam does not apply
  # to it at all: `Arangox.VelocyClient` encodes and decodes inside its own
  # `request/3`.
  defp maybe_encode_body(%Request{} = request, _codec, %__MODULE__{client: VelocyClient}),
    do: {:ok, request}

  defp maybe_encode_body(%Request{body: ""} = request, _codec, %__MODULE__{}), do: {:ok, request}

  defp maybe_encode_body(%Request{body: body} = request, codec, %__MODULE__{} = state) do
    case codec do
      :velocypack ->
        with {:ok, encoded} <- encode_body(fn -> VelocyPack.encode!(body) end) do
          {:ok, put_new_header(%{request | body: encoded}, "content-type", @content_type_vpack)}
        end

      :json ->
        with {:ok, encoded} <- encode_body(fn -> state.json_library.encode!(body) end) do
          {:ok, %{request | body: encoded}}
        end

      :raw when is_binary(body) ->
        {:ok, request}

      :raw ->
        {:error,
         %Error{
           reason: :encode_error,
           message:
             "a request whose content-type names neither JSON nor VelocyPack " <>
               "must carry its body already encoded, as a binary"
         }}
    end
  end

  # A `content-type` on the individual request selects the codec, not just the
  # label. That header is what the server reads to decide how to parse the
  # body, so encoding by the pool's setting while labelling by the caller's
  # puts mislabelled bytes on the wire — a documented per-request override
  # turned into a parse error at the server. With no such header the
  # pool's `:content_type` decides. A type that names neither codec —
  # `text/plain` for `/_api/import`, `application/octet-stream`, multipart
  # uploads — is the caller saying the body is already in its wire form.
  defp effective_request_codec(%Request{headers: headers}, %__MODULE__{content_type: fallback}) do
    case request_content_type(headers) do
      nil -> fallback
      @content_type_vpack -> :velocypack
      media -> if Client.json_media?(media), do: :json, else: :raw
    end
  end

  # First matching entry wins, any casing. Runs on the request's own headers,
  # before assembly — see the note in `run_execute/4`.
  defp request_content_type(headers) do
    Enum.find_value(headers, fn
      {name, value} ->
        if String.downcase(to_string(name)) == "content-type", do: media_type(value)

      _other ->
        nil
    end)
  end

  # Both codecs are driven through their raising variants — `:json_library`'s
  # contract only requires `encode!/1` — so an unencodable body arrives here as
  # an exception. It is the caller's data, not a connection fault: the request
  # never reached the wire, and the answer is an error tuple on a healthy
  # connection.
  defp encode_body(encode) do
    {:ok, encode.()}
  rescue
    exception ->
      {:error, %Error{reason: :encode_error, message: Exception.message(exception)}}
  end

  # The accept header goes on every request a VelocyPack pool makes, body or
  # not: a GET has nothing to encode but still wants a VelocyPack answer.
  # `maybe_encode_body/3` only sees requests that have a body, so bodyless ones
  # are covered by the call in `run_execute/4`.
  defp accept_header(%Request{} = request, %__MODULE__{client: VelocyClient}), do: request

  defp accept_header(%Request{} = request, %__MODULE__{content_type: :velocypack}),
    do: put_new_header(request, "accept", @content_type_vpack)

  defp accept_header(%Request{} = request, %__MODULE__{}), do: request

  # A header anyone set wins, whatever its casing: `:content_type` is a pool
  # default, a header is the documented way to override it, and the driver
  # never puts a second copy of a name on the wire. Runs after assembly, so a
  # pool-configured entry suppresses the label too. Appends at the end —
  # `name` must be lowercase.
  defp put_new_header(%Request{headers: headers} = request, name, value) do
    if has_header?(headers, name) do
      request
    else
      %{request | headers: headers ++ [{name, value}]}
    end
  end

  defp maybe_decode_body(%Response{} = response, %__MODULE__{client: VelocyClient}),
    do: {:ok, response}

  defp maybe_decode_body(%Response{body: nil} = response, %__MODULE__{}), do: {:ok, response}

  # Decoding follows the *response's* content type rather than the pool's. A
  # server that declines VelocyPack answers in JSON, and a pool that asked for
  # VelocyPack still has to read that.
  defp maybe_decode_body(%Response{body: body} = response, %__MODULE__{max_body_size: max})
       when is_binary(body) and byte_size(body) > max do
    {:error,
     %Error{
       reason: :body_too_large,
       status: response.status,
       message:
         "response body of #{byte_size(body)} bytes exceeds :max_body_size (#{max}); " <>
           "raise the pool option if the workload is legitimate"
     }}
  end

  defp maybe_decode_body(
         %Response{body: body, headers: headers} = response,
         %__MODULE__{} = state
       ) do
    case response_content_type(headers) do
      @content_type_vpack ->
        with :ok <- check_length_prefix(body, response) do
          decode_body_with(response, fn -> VelocyPack.decode!(body) end)
        end

      @content_type_dump ->
        decode_body_with(response, fn -> decode_dump(body, state.json_library) end)

      media ->
        if Client.json_media?(media) do
          decode_body_with(response, fn -> state.json_library.decode!(body) end)
        else
          # A declared non-JSON body — Prometheus text, a multipart batch, a
          # Foxx zip bundle — is already in its wire form; the JSON decoder
          # would turn every such success into `:decode_error`. An absent
          # content type still decodes as JSON: `response_content_type/1`
          # answers JSON when no header names one.
          {:ok, response}
        end
    end
  end

  # A VelocyPack compact container (0x13 array, 0x14 object) leads with its
  # total size as a variable-length integer: 7 payload bits per byte, the high
  # bit set on every byte but the last. A 64-bit byte count fits in
  # ceil(64 / 7) = 10 such bytes, so an 11th continuation byte cannot be a
  # bigger number — only malformed input, and, under a decoder with the known
  # quadratic length parsing, CPU the sender controls. Rejecting the run here
  # keeps it away from the codec regardless of which codec version is
  # installed.
  defp check_length_prefix(
         <<compact, prefix::binary-size(11), _::binary>>,
         %Response{} = response
       )
       when compact in [0x13, 0x14] do
    if continuation_bytes_only?(prefix) do
      {:error,
       %Error{
         reason: :invalid_length,
         status: response.status,
         message:
           "VelocyPack length prefix runs past 10 continuation bytes; the body is malformed"
       }}
    else
      :ok
    end
  end

  defp check_length_prefix(_body, %Response{}), do: :ok

  defp continuation_bytes_only?(<<>>), do: true

  defp continuation_bytes_only?(<<byte, rest::binary>>) when byte >= 0x80,
    do: continuation_bytes_only?(rest)

  defp continuation_bytes_only?(_), do: false

  # The body is server-supplied bytes, so decode failure is a normal outcome,
  # not a crash: any raise from the codec becomes a structured error carrying
  # the response status.
  defp decode_body_with(%Response{} = response, decode) do
    {:ok, %{response | body: decode.()}}
  rescue
    exception ->
      {:error,
       %Error{
         reason: :decode_error,
         status: response.status,
         message: Exception.message(exception)
       }}
  end

  # First matching entry, any casing. Every client arangox ships answers a
  # list since 0.8; the map clause tolerates a third-party client that still
  # builds one, because misreading its content type would decode a VelocyPack
  # body as JSON rather than fail loudly.
  defp response_content_type(headers) when is_list(headers) or is_map(headers) do
    Enum.find_value(headers, @content_type_json, fn
      {name, value} when is_binary(name) ->
        if header_name(name) == "content-type", do: media_type(value)

      _other ->
        nil
    end)
  end

  defp response_content_type(_headers), do: @content_type_json

  # Content types arrive with parameters (`application/json; charset=utf-8`),
  # so the media type is matched rather than the whole header value.
  defp media_type(value) do
    value
    |> to_string()
    |> String.split(";", parts: 2)
    |> hd()
    |> String.trim()
    |> String.downcase()
  end

  defp decode_dump(body, json_library) do
    body
    |> String.split("\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line -> json_library.decode!(line) end)
  end

  ## Where an error picks up the endpoint
  #
  # Every error that leaves this module is stamped with the redacted endpoint
  # here. An error built anywhere else must be passed through `exception/2`
  # before it is returned, or it reaches the caller with `:endpoint` nil and
  # renders without the prefix every other error carries.

  # How many bytes of an undecodable response body are quoted back.
  @body_excerpt 256

  # A client's error, already conforming. Only the endpoint is missing.
  defp exception(state, %Error{} = exception), do: stamp(state, exception)

  defp exception(state, %Response{body: nil} = response),
    do: %Error{endpoint: state.endpoint, status: response.status}

  defp exception(state, %Response{} = response) do
    # An error body is a body: it crosses the same seam every other one does,
    # so `:max_body_size` bounds it and its own content type decodes it. Using
    # the connect-time JSON decoder here instead cost both — an oversized
    # error body was decoded anyway, and a VelocyPack error lost its
    # `errorNum` and arrived as a binary excerpt. `maybe_decode_body/2`
    # returns an error rather than raising, so an HTML 502 page from a proxy
    # still becomes a structured error carrying the status.
    case maybe_decode_body(response, state) do
      {:ok, %Response{body: %{} = body}} ->
        from_body(state, response.status, body)

      # A body refused *before* decoding says something the excerpt cannot,
      # and quoting an oversized body back into the message would defeat the
      # bound that just rejected it.
      {:error, %Error{reason: reason} = refusal} when reason in [:body_too_large, :invalid_length] ->
        %{refusal | endpoint: state.endpoint}

      _undecodable ->
        %Error{
          endpoint: state.endpoint,
          status: response.status,
          message: excerpt(response.body)
        }
    end
  end

  defp exception(state, reason),
    do: %{legacy_error(reason) | endpoint: state.endpoint}

  # Status and `errorNum` travel together whenever the body supplies them,
  # plus the atom reason derived from `errorNum`. An `errorNum` the vendored
  # table does not contain yields `Arangox.Errno.unknown/0` rather than `nil` or
  # a crash, so a newer server cannot break a caller matching on `:reason`.
  defp from_body(state, status, %{"errorNum" => error_num} = body) when is_integer(error_num) do
    %Error{
      endpoint: state.endpoint,
      status: status,
      error_num: error_num,
      reason: Errno.reason(error_num),
      message: body["errorMessage"]
    }
  end

  defp from_body(state, status, %{} = body) do
    %Error{
      endpoint: state.endpoint,
      status: status,
      error_num: body["errorNum"],
      message: body["errorMessage"]
    }
  end

  defp excerpt(body) when is_binary(body) and byte_size(body) <= @body_excerpt, do: body

  defp excerpt(body) when is_binary(body) do
    binary_part(body, 0, @body_excerpt) <> "... (truncated, #{byte_size(body)} bytes)"
  end

  defp excerpt(body), do: inspect(body, printable_limit: @body_excerpt, limit: 20)
end

# Credentials live in state because the request path needs them, so
# `inspect/1` is redacted rather than the state being emptied.
#
# This is a hand-written implementation rather than
# `@derive {Inspect, except: [:auth, :headers]}` because dropping `:headers`
# entirely would also hide the stream-transaction id and every user-configured
# header, which is most of what anyone inspects connection state for. Only the
# `authorization` value goes.
#
# `:endpoint` needs nothing here: `new/4` already stored it redacted, which is
# also what keeps `Arangox.Error.message/1` and the connect-failure log clean.
defimpl Inspect, for: Arangox.Connection do
  import Inspect.Algebra

  @redacted "[redacted]"

  def inspect(%Arangox.Connection{} = state, opts) do
    fields =
      state
      |> Map.from_struct()
      |> Map.put(:auth, redact_auth(state.auth))
      |> Map.put(:headers, redact_headers(state.headers))
      |> Map.put(:trx_id, redact_trx_id(state.trx_id))
      |> Map.to_list()

    container_doc("%Arangox.Connection{", fields, "}", opts, &field/2,
      separator: ",",
      break: :strict
    )
  end

  defp field({key, value}, opts) do
    concat([Atom.to_string(key), ": ", to_doc(value, opts)])
  end

  # The username goes too. It is authentication material, and the marker still
  # says a credential was configured.
  defp redact_auth({:basic, _username, _password}), do: {:basic, @redacted, @redacted}
  defp redact_auth({:bearer, _token}), do: {:bearer, @redacted}
  defp redact_auth(nil), do: nil
  defp redact_auth(_other), do: @redacted

  # The in-flight transaction identifier is a bearer capability; the
  # marker still says a transaction is open.
  defp redact_trx_id(nil), do: nil
  defp redact_trx_id(_id), do: @redacted

  # The list lives on `Arangox.Request` so this implementation, the request's
  # own, and the echoed-request sanitizer cannot drift apart. The transaction
  # identifier is in state's headers whenever a transaction is open, so it is
  # as much connection material as the credential.
  defp redact_headers(headers) when is_map(headers) do
    Map.new(headers, fn {name, value} ->
      if Arangox.Request.sensitive_header?(name), do: {name, @redacted}, else: {name, value}
    end)
  end

  defp redact_headers(headers) when is_list(headers) do
    Enum.map(headers, fn
      {name, _value} = pair ->
        if Arangox.Request.sensitive_header?(name), do: {name, @redacted}, else: pair

      other ->
        other
    end)
  end

  defp redact_headers(headers), do: headers
end
