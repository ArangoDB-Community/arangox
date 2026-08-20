if Code.ensure_loaded?(Mint.HTTP) do
  defmodule Arangox.MintClient do
    @moduledoc """
    An HTTP client implementation of the \
    [`:mint`](https://hexdocs.pm/mint/Mint.HTTP.html "documentation") \
    library. Requires [`:mint`](https://hex.pm/packages/mint "hex.pm") to be
    added as a dependency.

    Speaks HTTP/1.1 and HTTP/2 over TCP, TLS (Transport Layer Security) and
    unix domain sockets.

    ### Which protocol gets used

    This client speaks HTTP/1.1 by default on **both** schemes. HTTP/2 is
    opt-in:

        Arangox.start_link(client_opts: [protocols: [:http2]])

    On TLS that offer is settled by ALPN (Application-Layer Protocol
    Negotiation); on cleartext it is prior knowledge, and it fails at connect
    time if the server does not speak HTTP/2.

    ### Why HTTP/2 is not the default

    `request/3` hands the entire encoded body to `Mint.request/5` rather than
    streaming it, and HTTP/2 applies flow control to a request body: one
    larger than the peer's current window is refused outright with
    `:exceeds_window_size` instead of waiting for a `WINDOW_UPDATE`. ArangoDB
    advertises about 64 KiB, so a bulk insert or a large document sits above
    it while the same request succeeds over HTTP/1.1, which has no flow
    control.

    Until request bodies are streamed in window-sized chunks — work that
    belongs with the transport rework, since it means interleaving writes with
    `WINDOW_UPDATE` reads under the request deadline — HTTP/2 costs a size
    bound and buys header compression on a driver whose headers are four
    small fields. It is offered rather than assumed.

    Conforms to the `Arangox.Client` error contract: every failure is an
    `Arangox.Error` carrying a `:reason` atom, and neither `connect/2` nor
    `request/3` raises or exits, whatever the transport does with the options it
    is given.

    ### Headers on the wire

    The merged header list is delivered to `:mint` as given — order kept,
    duplicates kept — and `:mint` lowercases header *names* on the wire
    (HTTP/2 requires lowercase; it applies the same to HTTP/1.1). Values are
    untouched. Response headers come back as the parsed list on
    `Arangox.Response` — names lowercased, order and repeats as received.

    ### Header values never reach an error

    `:mint` reports a rejected header value as
    `{:invalid_header_value, name, value}`, with the whole value. For an
    `authorization` header that value is the credential. This module reports the
    header *name* and drops the value.

    [__Hex.pm__](https://hex.pm/packages/mint)

    [__Documentation__](https://hexdocs.pm/mint/Mint.HTTP.html)
    """

    # Bound here because `Mint` is aliased to `Mint.HTTP` below: written inline,
    # `Mint.HTTPError` would resolve to the non-existent `Mint.HTTP.HTTPError`,
    # so every `normalize/1` clause matching on it would be dead code and every
    # `:mint` error would fall through to the catch-all. The `Elixir.` prefix is
    # the documented escape from alias expansion; bound once here so the mistake
    # cannot be repeated further down.
    @transport_error Elixir.Mint.TransportError
    @http_error Elixir.Mint.HTTPError

    # `Mint.HTTP` dispatches to `Mint.HTTP1` or `Mint.HTTP2` by what the
    # connection negotiated and yields the same response stream either way.
    # Aliasing a specific protocol module here makes the other unreachable.
    alias Mint.HTTP, as: Mint

    alias Arangox.{
      Client,
      Connection,
      Endpoint,
      Error,
      Request,
      Response
    }

    @behaviour Client

    # The connect-time send bound, covering writes made before the first
    # request; each request replaces it with its remaining budget in
    # `request/3`. `send_timeout_close` closes on expiry, which keeps a
    # half-written request from being read as the next one.
    #
    # The watermark bounds the inet driver's queue: without one an oversized
    # write is accepted whole in a single port command, the send returns
    # instantly, and the send timer never runs.
    #
    # The zero linger makes every close an abort. A close with *any* bytes
    # still queued to a peer that stopped reading blocks the closing process
    # for the driver's multi-second flush wait — and `Mint` closes the socket
    # inside its own error handling, so that wait would land on a caller whose
    # budget just expired. This driver only ever closes sockets it is
    # retiring, so there is no half-close anyone waits on; the peer sees a
    # reset instead of an orderly shutdown.
    @default_send_opts [
      send_timeout: 15_000,
      send_timeout_close: true,
      high_watermark: 65_536,
      linger: {true, 0}
    ]

    # `:mint` requires an explicit hostname when the address is not a binary,
    # which a unix domain socket never is. Only ever used as the `host` header.
    @unix_hostname "localhost"

    @impl true
    def connect(%Endpoint{addr: addr, ssl?: ssl?}, opts) do
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)
      given = Keyword.get(opts, if(ssl?, do: :ssl_opts, else: :tcp_opts), [])

      client_opts = Keyword.get(opts, :client_opts, [])
      # `:timeout` bounds the connect; the send options bound a write that
      # blocks on a full peer window, which the request deadline does not
      # cover because it bounds receives. Caller options come last and win.
      transport_opts = [timeout: connect_timeout] ++ @default_send_opts ++ given

      # `:ssl_opts`/`:tcp_opts` reach the transport as written. Mint supplies
      # the TLS defaults — peer verification, hostname checking, a TLS 1.2
      # floor, system trust material — and this driver must add nothing on top
      # and take nothing away. Both halves of that rule are argued in
      # docs/solutions/architecture-patterns/transport-tls-defaults-are-not-the-drivers-to-supply.md.
      #
      # `:client_opts` merges per key. Replacing `:transport_opts` wholesale
      # would drop the caller's trust configuration whenever they set one
      # unrelated transport option.
      options =
        client_opts
        |> Keyword.update(
          :transport_opts,
          transport_opts,
          &Keyword.merge(transport_opts, &1)
        )
        |> Keyword.put_new(:protocols, [:http1])
        |> Keyword.merge(mode: :passive)

      do_connect(addr, ssl?, options)
    rescue
      # `:ssl` raises rather than returns on some option and trust-store
      # problems, and this callback must not raise. It sits on the
      # callback rather than on `do_connect/3` so that resolving trust material
      # is covered too.
      exception ->
        {:error, %Error{reason: :client_error, message: Exception.message(exception)}}
    catch
      # `:gen_tcp.connect/4` exits with `:badarg` on an unrecognised option.
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"}}

      :throw, value ->
        {:error, %Error{reason: :client_error, message: "threw: #{inspect(value)}"}}
    end

    defp do_connect(addr, ssl?, options) do
      case open(addr, ssl?, options) do
        {:ok, conn} ->
          if Mint.open?(conn) do
            {:ok, conn}
          else
            {:error, %Error{reason: :closed, message: "connection lost"}}
          end

        {:error, exception} ->
          {:error, normalize(exception)}
      end
    end

    # A unix domain socket is a `{:local, path}` address with port `0`,
    # supported since `:mint` 1.5.
    defp open({:unix, path}, ssl?, options) do
      scheme = if ssl?, do: :https, else: :http

      Mint.connect(scheme, {:local, path}, 0, Keyword.put_new(options, :hostname, @unix_hostname))
    end

    defp open({:tcp, host, port}, ssl?, options) do
      scheme = if ssl?, do: :https, else: :http

      Mint.connect(scheme, host, port, options)
    end

    @impl true
    def request(
          %Request{method: method, path: path, headers: headers, body: body},
          opts,
          %Connection{socket: socket} = state
        )
        when is_list(opts) do
      # One deadline for the whole request, established before it is
      # written and consulted again before every receive. A per-`recv` bound
      # would give a chunked response one budget per chunk.
      deadline = Client.deadline(opts, state)

      case Client.socket_timeout(deadline, opts, state) do
        :elapsed ->
          # Nothing was written, so the socket is healthy — but `:timeout` is a
          # connection-lost reason, so the pool retires it anyway; the caller's
          # budget is gone either way.
          {:error, elapsed_before_send_error(), state}

        {:ok, remaining} ->
          # The write half of the deadline: `Mint.request/5` performs the socket write
          # synchronously, and a write blocks while the peer's receive window
          # is full — before the deadline-bounded receive loop ever runs. The
          # send bound is therefore the remaining budget, set per request; the
          # connect-time `send_timeout` covers only writes made before the
          # first request.
          _ = set_send_timeout(Mint.get_socket(socket), remaining)

          with(
            {:ok, new_socket, ref} <-
              Mint.request(
                socket,
                Client.method_string(method),
                path,
                with_host(headers, socket),
                body
              ),
            {:ok, new_socket, buffer} <-
              do_recv(new_socket, ref, deadline, opts, state)
          ) do
            do_response(ref, buffer, %{state | socket: new_socket})
          else
            {:error, new_socket, exception} ->
              {:error, retire_if_dead(normalize(exception), new_socket),
               %{state | socket: new_socket}}

            {:error, new_socket, exception, _responses} ->
              {:error, retire_if_dead(normalize(exception), new_socket),
               %{state | socket: new_socket}}
          end
      end
    rescue
      # The moduledoc promises this callback never raises, and it reaches
      # `DBConnection` through `Arangox.Connection`: a raise here retires the
      # connection instead of failing the request. The other two clients carry
      # the same boundary.
      # A raise here can land after the request was written, and `state` still
      # holds the socket from before `Mint.request/5` replaced it — so the
      # connection cannot be resynchronised and must not go back to the pool.
      # `:closed` is in `connection_lost_reasons/0`, which forces the
      # disconnect.
      exception ->
        {:error, %Error{reason: :closed, message: Exception.message(exception)}, state}
    catch
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"},
         state}

      :throw, value ->
        {:error, %Error{reason: :closed, message: "threw: #{inspect(value)}"}, state}
    end

    # `:mint` renders the `host` header as `hostname:port` for any port that is
    # not the scheme's default, so a unix connection would send
    # `host: localhost:0` and an RFC-strict server answers `400` before reading
    # the path. Port `0` only ever means a `{:local, path}` address.
    defp with_host(headers, %{port: 0, host: host}) when is_binary(host) do
      if Enum.any?(headers, fn {name, _value} ->
           String.downcase(to_string(name)) == "host"
         end) do
        headers
      else
        [{"host", host} | headers]
      end
    end

    defp with_host(headers, _socket), do: headers

    # Best-effort: a socket `setopts` cannot reach is about to fail its send
    # anyway, with a better-typed error than this call could build. The
    # `send_timeout_close` set at connect stays in force, so a timed-out write
    # still closes the socket under it.
    defp set_send_timeout(socket, timeout) when is_port(socket),
      do: :inet.setopts(socket, send_timeout: timeout)

    defp set_send_timeout(socket, timeout),
      do: :ssl.setopts(socket, send_timeout: timeout)

    # `Mint.recv/3` yields whatever has arrived, so a response spread over
    # several TCP reads takes several calls. Re-deriving the wait from the
    # remaining deadline is what bounds the request rather than the read.
    #
    # A recv timeout surfaces as `%Mint.TransportError{reason: :timeout}`,
    # which `normalize/1` passes through; the `:elapsed` branch is the same
    # failure noticed between reads and must report the same reason. `:timeout`
    # is in `Arangox.Client.connection_lost_reasons/0`, so both disconnect:
    # bytes are on the wire and the socket cannot be handed on.
    defp do_recv(conn, ref, deadline, opts, state, buffer \\ []) do
      case Client.socket_timeout(deadline, opts, state) do
        :elapsed ->
          {:error, conn, elapsed_error()}

        {:ok, timeout} ->
          case Mint.recv(conn, 0, timeout) do
            # Batches accumulate newest-first and flatten once at the end:
            # appending with `++` copies the whole accumulated list on every
            # socket read, which is quadratic in the number of reads a
            # response takes.
            {:ok, new_conn, next_buffer} ->
              buffer = [next_buffer | buffer]

              if Enum.any?(next_buffer, &final?(&1, ref)) do
                {:ok, new_conn, buffer |> Enum.reverse() |> Enum.concat()}
              else
                do_recv(new_conn, ref, deadline, opts, state, buffer)
              end

            {:error, _, _, _} = error ->
              error
          end
      end
    end

    defp elapsed_error do
      %Error{
        reason: :timeout,
        message: "the request timeout elapsed before the response was fully received"
      }
    end

    # The pre-write refusal must not borrow the receive-phase wording: at this
    # point no request was sent, and an error claiming a response was in
    # flight sends the reader debugging the wrong half of the exchange.
    defp elapsed_before_send_error do
      %Error{
        reason: :timeout,
        message: "the request timeout elapsed before the request was sent"
      }
    end

    # The two ways a request can end. HTTP/2 can abandon one request while the
    # connection stays usable — a stream reset — and reports it as an `:error`
    # for that reference rather than a `:done`. Treating `:done` as the only
    # ending spends the caller's whole budget waiting for one that was already
    # cancelled.
    defp final?({:done, ref}, ref), do: true
    defp final?({:error, ref, _reason}, ref), do: true
    defp final?(_response, _ref), do: false

    # Folded rather than matched on shape: an informational response
    # (`103 Early Hints`) puts a `:status`/`:headers` pair before the real one,
    # and a `FunctionClauseError` here would escape the callback. A later
    # status supersedes an earlier one and its headers.
    defp do_response(ref, buffer, state) do
      case Enum.find(buffer, &match?({:error, ^ref, _reason}, &1)) do
        {:error, ^ref, reason} -> {:error, retire_if_dead(normalize(reason), state.socket), state}
        nil -> assemble(ref, buffer, state)
      end
    end

    # The socket-gone signal travels in `:reason`, and the pool acts
    # on nothing else. HTTP/2 has failures whose reason says nothing a pool
    # retires on while the connection can no longer carry a request — a GOAWAY
    # leaves it write-closed with `:server_closed_connection`, `:unprocessed`
    # or `:closed_for_writing` — so the socket is consulted directly. A stream
    # reset leaves the connection open and keeps its own reason.
    defp retire_if_dead(%Error{} = error, conn) do
      if Client.connection_lost?(error) or Mint.open?(conn) do
        error
      else
        %{error | reason: :closed}
      end
    end

    defp assemble(ref, buffer, state) do
      {status, headers, chunks} =
        Enum.reduce(buffer, {nil, [], []}, fn
          {:status, ^ref, status}, {_status, _headers, chunks} -> {status, [], chunks}
          {:headers, ^ref, headers}, {status, acc, chunks} -> {status, acc ++ headers, chunks}
          {:data, ^ref, data}, {status, headers, chunks} -> {status, headers, [data | chunks]}
          _other, acc -> acc
        end)

      case status do
        nil ->
          {:error, %Error{reason: :client_error, message: "the server sent no response status"},
           state}

        status ->
          body = if chunks == [], do: nil, else: chunks |> Enum.reverse() |> IO.iodata_to_binary()

          {:ok, %Response{status: status, headers: headers, body: body}, state}
      end
    end

    @impl true
    def alive?(%Connection{socket: conn}), do: Mint.open?(conn)

    @impl true
    def close(%Connection{socket: conn}) do
      Mint.close(conn)

      :ok
    end

    ## Error normalization

    # The one place a `:mint` failure becomes an `Arangox.Error`. `:endpoint`
    # stays `nil`: this module only sees a parsed `Arangox.Endpoint`, which
    # carries no userinfo, and `Arangox.Connection` fills in the redacted
    # configured endpoint.

    # Must precede the `is_exception/1` clause — an `Arangox.Error` is an
    # exception, and falling through would flatten `:timeout` into
    # `:client_error` and lose the disconnect signal.
    defp normalize(%Error{} = error), do: error

    # `Mint.HTTP1.format_error/1` renders this reason with the offending
    # value, which for an `authorization` header is the credential. It would
    # reach the exception message, the DBConnection log line, and any report
    # built from either.
    defp normalize(%{__struct__: @http_error, reason: {:invalid_header_value, name, _value}}) do
      %Error{
        reason: :invalid_header_value,
        message:
          "invalid value for header #{inspect(name)} (only printable ASCII characters " <>
            "are allowed); the value is not shown because it may be a credential"
      }
    end

    defp normalize(%{__struct__: struct, reason: reason} = exception)
         when struct in [@transport_error, @http_error] do
      %Error{reason: reason_atom(reason), message: Exception.message(exception)}
    end

    defp normalize(exception) when is_exception(exception) do
      %Error{reason: :client_error, message: Exception.message(exception)}
    end

    # Unreachable through the callers above, which only ever pass the two
    # structs. One clause without a guard rather than two, because a
    # `when is_atom(reason)` clause is one Dialyzer can prove dead, and
    # Dialyzer runs in CI.
    defp normalize(reason) do
      %Error{
        reason: if(is_atom(reason), do: reason, else: :client_error),
        message: inspect(reason)
      }
    end

    # `:mint` reasons are usually a bare atom (`:closed`, `:econnrefused`,
    # `:timeout`), sometimes a tagged tuple (`{:bad_alpn_protocol, protocol}`).
    defp reason_atom(reason) when is_atom(reason), do: reason

    defp reason_atom(reason) when is_tuple(reason) and is_atom(elem(reason, 0)),
      do: elem(reason, 0)

    defp reason_atom(_reason), do: :client_error

    defp caught_reason(reason) when is_atom(reason), do: reason
    defp caught_reason(_reason), do: :client_error
  end
end
