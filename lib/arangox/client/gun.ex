if Code.ensure_loaded?(:gun) do
  defmodule Arangox.GunClient do
    @moduledoc """
    An HTTP client implementation of the \
    [`:gun`](https://ninenines.eu/docs/en/gun/2.1/guide "documentation") \
    library. Requires [`:gun`](https://hex.pm/packages/gun "hex.pm") to be added
    as a dependency.

    Speaks HTTP/1.1 and HTTP/2 over TCP, TLS (Transport Layer Security) and unix
    domain sockets. The driver sets no `protocols` option, so `:gun`'s own
    defaults apply: HTTP/1.1 on cleartext, and on TLS an ALPN
    (Application-Layer Protocol Negotiation) offer of both protocols with
    HTTP/2 preferred. `client_opts: %{protocols: [:http2]}` asserts HTTP/2 on
    cleartext by prior knowledge, or pins TLS to it.

    The request-body size bound documented on `Arangox.MintClient` does not
    apply here: `:gun` queues a request body and honours `WINDOW_UPDATE`
    itself, so this client carries a body of any size under HTTP/2.

    The merged header list is delivered to `:gun` as given — order kept,
    duplicates kept, names as written. Response headers come back as the
    parsed list on `Arangox.Response` — names lowercased, order and repeats
    as received.

    The per-request socket write bounds documented on `Arangox.MintClient`
    deliberately do not apply here: `:gun` writes from its own process, so a
    caller can never block inside a socket send, and every caller wait is
    bounded by the request deadline. The socket still carries the same
    teardown hygiene as the other clients — a bounded driver queue and an
    abort on close — protecting `:gun`'s process rather than the caller.

    `Arangox.MintClient` is the default and the one the documentation assumes.
    This client is supported for applications already using it.

    Conforms to the `Arangox.Client` error contract: every failure is an
    `Arangox.Error` carrying a `:reason` atom, and neither `connect/2` nor
    `request/3` raises or exits.

    ### Options

    `:client_opts` is a map, merged over the options below. Gun takes its
    transport options under `:tcp_opts` and `:tls_opts`; `:ssl_opts` given to
    `Arangox.start_link/1` reaches the latter.

    [__Hex.pm__](https://hex.pm/packages/gun)

    [__Documentation__](https://ninenines.eu/docs/en/gun/2.1/guide)
    """

    alias :gun, as: Gun

    alias Arangox.{
      Client,
      Connection,
      Endpoint,
      Error,
      Request,
      Response
    }

    @behaviour Client

    # Gun writes from its own process, so the per-request send bounds the
    # other clients derive from the deadline do not apply here — a caller can
    # never block inside a socket send, and every caller wait is already
    # deadline-bounded. These bound the socket itself: the send timeout bounds
    # gun's write attempts, the watermark bounds the inet driver's queue when
    # a peer stops reading, and the zero linger makes a retirement close an
    # abort rather than a multi-second flush wait toward a dead peer.
    @default_send_opts [
      send_timeout: 15_000,
      send_timeout_close: true,
      high_watermark: 65_536,
      linger: {true, 0}
    ]

    @impl true
    def connect(%Endpoint{addr: addr, ssl?: ssl?}, opts) do
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
      client_opts = Keyword.get(opts, :client_opts, %{})

      options =
        Map.merge(
          %{
            http_opts: %{keepalive: :infinity},
            retry: 0,
            transport: if(ssl?, do: :tls, else: :tcp),
            # Gun applies `{send_timeout, 15000}` only when `:tcp_opts` is
            # *absent* from its options map (gun.erl `domain_lookup/3`), and
            # this key is always present — so the bounds are merged under the
            # caller's list rather than used as its default. Supplying
            # `tcp_opts: [nodelay: true]` would otherwise remove the write
            # bound as surely as passing an empty list did.
            tcp_opts: Keyword.merge(@default_send_opts, Keyword.get(opts, :tcp_opts, [])),
            tls_opts: Keyword.get(opts, :ssl_opts, []),
            connect_timeout: connect_timeout
          },
          client_opts
        )

      with {:ok, pid} <- open(addr, options),
           {:ok, _protocol} <- await_up(pid, connect_timeout) do
        {:ok, pid}
      else
        {:error, reason} -> {:error, normalize(reason)}
      end
    rescue
      exception ->
        {:error, %Error{reason: :client_error, message: Exception.message(exception)}}
    catch
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"}}

      :throw, value ->
        {:error, %Error{reason: :client_error, message: "threw: #{inspect(value)}"}}
    end

    defp open({:unix, path}, options), do: Gun.open_unix(to_charlist(path), options)
    defp open({:tcp, host, port}, options), do: Gun.open(to_charlist(host), port, options)

    # `await_up/2` leaves the connection process running when it gives up, and
    # that process would outlive the failed connect.
    defp await_up(pid, timeout) do
      case Gun.await_up(pid, timeout) do
        {:ok, protocol} ->
          {:ok, protocol}

        {:error, reason} ->
          Gun.close(pid)
          {:error, reason}
      end
    end

    @impl true
    def request(
          %Request{method: method, path: path, headers: headers, body: body},
          opts,
          %Connection{socket: pid} = state
        )
        when is_list(opts) do
      deadline = Client.deadline(opts, state)

      if Process.alive?(pid) do
        ref =
          Gun.request(
            pid,
            method_string(method),
            path,
            headers,
            body || ""
          )

        await_response(pid, ref, deadline, opts, state)
      else
        {:error, %Error{reason: :closed, message: "the connection process is gone"}, state}
      end
    rescue
      exception ->
        {:error, %Error{reason: :client_error, message: Exception.message(exception)}, state}
    catch
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"},
         state}

      :throw, value ->
        {:error, %Error{reason: :client_error, message: "threw: #{inspect(value)}"}, state}
    end

    # The budget covers the whole exchange, so it is re-derived
    # between the response and the body rather than applied to each.
    defp await_response(pid, ref, deadline, opts, state) do
      with {:ok, timeout} <- timeout_for(deadline, opts, state),
           {:response, fin, status, headers} <- Gun.await(pid, ref, timeout) do
        case fin do
          :fin ->
            {:ok, %Response{status: status, headers: headers}, state}

          :nofin ->
            await_body(pid, ref, status, headers, deadline, opts, state)
        end
      else
        # A 1xx is not the response; the real one follows on the same stream,
        # and the deadline keeps a server streaming 1xx forever bounded.
        {:inform, _status, _headers} -> await_response(pid, ref, deadline, opts, state)
        {:error, reason} -> {:error, normalize(reason), state}
        %Error{} = error -> {:error, error, state}
      end
    end

    # One chunk at a time, re-deriving the remaining budget before each receive.
    # `:gun.await_body/3` cannot be used here: it loops internally and re-arms
    # the *same* duration after every `nofin` chunk (gun.erl `await_body/5`),
    # so a peer sending one byte before each expiry holds the connection
    # forever. A bound applied per receive is not a bound on the request.
    defp await_body(pid, ref, status, headers, deadline, opts, state, acc \\ []) do
      with {:ok, timeout} <- timeout_for(deadline, opts, state),
           {:data, fin, data} <- Gun.await(pid, ref, timeout) do
        acc = [data | acc]

        case fin do
          :fin -> {:ok, response(status, headers, acc), state}
          :nofin -> await_body(pid, ref, status, headers, deadline, opts, state, acc)
        end
      else
        # Trailers end the body; the driver does not surface them here.
        {:trailers, _trailers} -> {:ok, response(status, headers, acc), state}
        {:error, reason} -> {:error, normalize(reason), state}
        %Error{} = error -> {:error, error, state}
        other -> {:error, normalize(other), state}
      end
    end

    defp response(status, headers, acc) do
      %Response{
        status: status,
        headers: headers,
        body: acc |> Enum.reverse() |> IO.iodata_to_binary()
      }
    end

    # `:elapsed` mid-response means the stream was abandoned part-read, so the
    # reason has to be one that retires the connection.
    defp timeout_for(deadline, opts, state) do
      case Client.socket_timeout(deadline, opts, state) do
        {:ok, timeout} ->
          {:ok, timeout}

        :elapsed ->
          %Error{
            reason: :timeout,
            message: "the request timeout elapsed before the response was fully received"
          }
      end
    end

    @impl true
    def alive?(%Connection{socket: pid}), do: Process.alive?(pid)

    @impl true
    def close(%Connection{socket: pid}), do: Gun.close(pid)

    ## Error normalization

    defp normalize(%Error{} = error), do: error

    defp normalize({:shutdown, reason}), do: normalize(reason)

    # `await_up/2` reports a failed connect as the connection process going
    # down, carrying the transport reason. Flattening it to `:closed` would
    # report every refused port and bad hostname as a lost connection.
    defp normalize({:down, reason}) when reason in [:normal, :shutdown],
      do: %Error{reason: :closed, message: "the connection process exited"}

    defp normalize({:down, reason}), do: normalize(reason)

    # Gun wraps whatever ended the stream. The inner reason is the one that says
    # whether the connection survived, so flattening it here would lose the
    # distinction between a reset stream and a closed socket.
    # Gun reports a connection-level failure (a GOAWAY, a socket that died
    # mid-stream) as `{:connection_error, reason}` from `await/3` and
    # `await_body/3`. It has to keep the transport's own reason: falling
    # through to the catch-all below would report `:client_error`, which is
    # not in `Arangox.Client.connection_lost_reasons/0`, and the unusable
    # connection would go back into the pool.
    # The transport's own reason is kept only when it already retires the
    # connection. HTTP/2 reports these as cow_http2 atoms — `:protocol_error`,
    # `:internal_error` — which are not in `connection_lost_reasons/0`, so
    # keeping them verbatim would leave a failed connection checked in, which
    # is the defect this clause exists to fix.
    defp normalize({:connection_error, {reason, _human_readable}}),
      do: connection_error(reason)

    defp normalize({:connection_error, reason}), do: connection_error(reason)

    defp normalize({:stream_error, reason}), do: normalize(reason)

    defp normalize({:stream_error, _reason, _message}),
      do: %Error{reason: :server_closed_request, message: "the server reset the stream"}

    # Gun reports an unusable option as `{:options, term}` and a bad argument as
    # `{:badarg, term}`. The term can hold whatever the caller passed, so it is
    # described rather than inspected wholesale.
    defp normalize({:options, term}),
      do: %Error{reason: :client_error, message: "invalid option: #{option_name(term)}"}

    defp normalize({:badarg, _term}),
      do: %Error{reason: :client_error, message: "invalid argument"}

    defp normalize(reason) when is_atom(reason),
      do: %Error{reason: reason, message: inspect(reason)}

    defp normalize(reason),
      do: %Error{reason: :client_error, message: inspect(reason)}

    defp connection_error(reason) when is_atom(reason) do
      if Client.connection_lost?(%Error{reason: reason}),
        do: %Error{reason: reason, message: inspect(reason)},
        else: %Error{reason: :closed, message: "the connection failed: #{inspect(reason)}"}
    end

    defp connection_error(reason),
      do: %Error{reason: :closed, message: "the connection failed: #{inspect(reason)}"}

    defp option_name({name, _value}) when is_atom(name), do: inspect(name)
    defp option_name(name) when is_atom(name), do: inspect(name)
    defp option_name(_term), do: "unknown"

    defp caught_reason({reason, _stack}) when is_atom(reason), do: reason
    defp caught_reason(reason) when is_atom(reason), do: reason
    defp caught_reason(_reason), do: :client_error

    # `Arangox.method/0` is a closed set. Converting through it rather than
    # through `to_string/1` keeps a caller's bad argument an argument error:
    # a protocol failure here would raise past the rescue below, which reads
    # any raise as a dead socket and retires a healthy connection.
    defp method_string(:get), do: "GET"
    defp method_string(:post), do: "POST"
    defp method_string(:put), do: "PUT"
    defp method_string(:patch), do: "PATCH"
    defp method_string(:delete), do: "DELETE"
    defp method_string(:head), do: "HEAD"
    defp method_string(:options), do: "OPTIONS"
  end
end
