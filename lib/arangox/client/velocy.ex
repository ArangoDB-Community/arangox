if Code.ensure_loaded?(VelocyPack) do
  defmodule Arangox.VelocyClient do
    @moduledoc """
    The [VelocyStream](https://github.com/arangodb/velocystream) client, an
    explicit opt-in for ArangoDB 3.11 deployments
    (`client: Arangox.VelocyClient`) — the server removed the protocol in
    3.12, and `Arangox.MintClient` over HTTP is the default.

    Conforms to the `Arangox.Client` error contract: every failure is an
    `Arangox.Error` carrying a `:reason` atom, and neither `connect/2` nor
    `request/3` raises or exits, whatever the transport does with the options it
    is given.

    VelocyStream carries headers as a map in *both* directions, so this
    client cannot express a repeated header name. Outbound, it builds the map
    from the merged list itself: the right-most occurrence of a name wins and
    the others are dropped. Inbound, the list on `Arangox.Response` is built
    from the server's map: no repeated name can arrive, and the order is the
    map's key order, not the order the server wrote them. Casing is preserved
    in both directions — unlike the HTTP clients, which lowercase names.

    URI query parsing functions proudly stolen from Plataformatec and
    licensed under Apache 2.0.
    """

    require Logger

    alias Arangox.{
      Client,
      Connection,
      Endpoint,
      Errno,
      Error,
      Request,
      Response
    }

    @behaviour Client

    @vst_version 1.1
    @vst_version_trunc trunc(@vst_version)

    # Fixed by the VelocyStream 1.1 protocol, unlike the chunk size. Mirrored
    # as `@vst_chunk_header_size` in `Arangox`, which validates `:vst_maxsize`
    # against it whether or not this module was compiled. Keep them equal.
    @chunk_header_size 24

    @doc """
    Returns the _VelocyStream_ chunk size from the deprecated application config,
    or `30_720`.

    Deprecated in 0.8 and removed in 0.9 along with the application-config read it
    reports on. It answers the *fallback*, not what any particular pool uses:
    since 0.8 the chunk size is a per-pool start option, resolved at connect and
    held in `Arangox.Connection`, so two pools can disagree and neither has to
    agree with this. Pass `:vst_maxsize` to `Arangox.start_link/1` instead.

    Emits a deprecation warning on every call.
    """
    @deprecated "Pass :vst_maxsize to Arangox.start_link/1 instead"
    @spec vst_maxsize() :: pos_integer()
    def vst_maxsize do
      Logger.warning("""
      Arangox.VelocyClient.vst_maxsize/0 is deprecated and will be removed in \
      arangox 0.9. The chunk size is a per-pool start option now, and this \
      function cannot see it:

          Arangox.start_link(vst_maxsize: 12_345)
      """)

      Connection.fallback_vst_maxsize()
    end

    @spec maybe_authenticate(Connection.t(), [Client.request_option()]) ::
            :ok | {:error, Error.t()}
    def maybe_authenticate(state, opts \\ [])

    def maybe_authenticate(%Connection{auth: {:basic, username, password}} = state, opts),
      do:
        do_maybe_authenticate(
          state,
          opts,
          [@vst_version_trunc, 1000, "plain", username, password]
        )

    def maybe_authenticate(%Connection{auth: {:bearer, token}} = state, opts),
      do: do_maybe_authenticate(state, opts, [@vst_version_trunc, 1000, "jwt", token])

    def maybe_authenticate(%Connection{}, _opts), do: :ok

    # Same boundary as `connect/2` and `request/3`: this runs inside the connect
    # pipeline, on bytes a server chose, so a raise here escapes a
    # `DBConnection` callback and costs the process its backoff. A
    # chunk header declaring a length below the 24-byte header, for one,
    # reaches `recv` with a negative length.
    defp do_maybe_authenticate(state, opts, auth_msg) do
      do_authenticate(state, opts, auth_msg)
    rescue
      exception ->
        {:error, %Error{reason: :client_error, message: Exception.message(exception)}}
    catch
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"}}

      :throw, value ->
        {:error, %Error{reason: :client_error, message: "threw: #{inspect(value)}"}}
    end

    defp do_authenticate(
           %Connection{socket: socket, endpoint: endpoint, vst_maxsize: vst_maxsize} = state,
           opts,
           auth_msg
         ) do
      deadline = Client.deadline(opts, state)

      with(
        {:ok, encoded_message} <-
          VelocyPack.encode(auth_msg),
        :ok <-
          send_stream(socket, build_stream(encoded_message, vst_maxsize), deadline, opts, state),
        {:ok, header} <-
          recv_header(socket, deadline, opts, state),
        {:ok, stream} <-
          recv_stream(socket, header, deadline, opts, state),
        {:ok, [[@vst_version_trunc, 2, 200, _headers] | _body]} <-
          decode_stream(stream)
      ) do
        :ok
      else
        {:ok, [[@vst_version_trunc, 2, status, _headers] | [body | _]]} ->
          error_num = body["errorNum"]

          {:error,
           %Error{
             status: status,
             error_num: error_num,
             reason: error_num && Errno.reason(error_num),
             message: body["errorMessage"],
             endpoint: endpoint
           }}

        {:error, reason} ->
          {:error, normalize(reason)}

        other ->
          {:error, malformed(other)}
      end
    end

    @impl true
    def connect(%Endpoint{addr: addr, ssl?: ssl?}, opts) do
      mod = if ssl?, do: :ssl, else: :gen_tcp
      given = Keyword.get(opts, if(ssl?, do: :ssl_opts, else: :tcp_opts), [])
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)

      # Options reach `:ssl`/`:gen_tcp` as written. `packet`, `mode` and
      # `active` are merged last and stay forced: this client's framing depends
      # on them. No TLS defaults are added here — since OTP 26 `:ssl` verifies
      # peers and refuses to connect without trust material, so a TLS endpoint
      # needs `ssl_opts: [cacertfile: ...]` or, knowingly,
      # `[verify: :verify_none]`. Why no defaults belong here is argued in
      # docs/solutions/architecture-patterns/transport-tls-defaults-are-not-the-drivers-to-supply.md.
      # Send bounds go under the caller's options so they can be overridden;
      # the framing options go over them because this client's chunking
      # depends on them. The connect-time send bound covers the handshake and
      # auth writes; `send_stream/5` replaces it per chunk with the request's
      # remaining budget.
      # The zero linger makes every close an abort: a close with bytes still
      # queued to a peer that stopped reading otherwise blocks the closing
      # process for the driver's multi-second flush wait. Sockets here are
      # only ever closed when they are being retired.
      options =
        [send_timeout: 15_000, send_timeout_close: true, linger: {true, 0}]
        |> Keyword.merge(given)
        |> Keyword.merge(packet: :raw, mode: :binary, active: false)

      # The handshake write is a second failure point *after* the port exists,
      # so it cannot share the connect failure's `else`: nothing else owns the
      # port yet, and a caller that only sees `{:error, _}` cannot close it.
      case mod.connect(addr_for(addr), port_for(addr), options, connect_timeout) do
        {:ok, port} ->
          case mod.send(port, "VST/#{@vst_version}\r\n\r\n") do
            :ok ->
              {:ok, {mod, port}}

            {:error, reason} ->
              mod.close(port)
              {:error, normalize(reason)}
          end

        {:error, reason} ->
          {:error, normalize(reason)}
      end
    rescue
      exception ->
        {:error, %Error{reason: :client_error, message: Exception.message(exception)}}
    catch
      # `:gen_tcp.connect/4` exits with `:badarg` on an unrecognised option
      # (`tcp_opts: [verify: :verify_peer]`, say). This callback must not raise
      # or exit.
      :exit, reason ->
        {:error, %Error{reason: caught_reason(reason), message: "exited: #{inspect(reason)}"}}

      :throw, value ->
        {:error, %Error{reason: :client_error, message: "threw: #{inspect(value)}"}}
    end

    defp addr_for({:unix, path}), do: {:local, to_charlist(path)}
    defp addr_for({:tcp, host, _port}), do: to_charlist(host)

    defp port_for({:unix, _path}), do: 0
    defp port_for({:tcp, _host, port}), do: port

    @impl true
    def request(
          %Request{method: method, path: path, headers: headers, body: body},
          opts,
          %Connection{socket: socket, database: database, vst_maxsize: vst_maxsize} = state
        )
        when is_list(opts) do
      %{path: path, query: query} = URI.parse(path)

      {database, path} =
        case path do
          "/_db/" <> rest ->
            [database, path] = :binary.split(rest, "/")

            {database, "/" <> path}

          _ ->
            {database || "", path}
        end

      # One deadline for the whole exchange, re-derived before every
      # receive. A response arrives as a header and a payload per chunk, so a
      # per-`recv` timeout would let an N-chunk response take N budgets.
      deadline = Client.deadline(opts, state)

      with(
        {:ok, method_code} <-
          method_for(method),
        {:ok, request} <-
          encode_term([
            @vst_version_trunc,
            1,
            database,
            method_code,
            path,
            query_for(query),
            headers_for(headers)
          ]),
        {:ok, body} <-
          body_for(body),
        :ok <-
          send_stream(socket, build_stream(request <> body, vst_maxsize), deadline, opts, state),
        {:ok, header} <-
          recv_header(socket, deadline, opts, state),
        {:ok, stream} <-
          recv_stream(socket, header, deadline, opts, state),
        {:ok, [[@vst_version_trunc, 2, status, headers] | body]} <-
          decode_stream(stream)
      ) do
        {:ok,
         %Response{status: status, headers: response_headers(headers), body: body_from(body)},
         state}
      else
        {:unsupported_method, method} ->
          {:error,
           %Error{
             reason: :client_error,
             message:
               "VelocyStream defines no method #{inspect(method)}; expected one of " <>
                 ":get, :head, :delete, :post, :put, :patch or :options"
           }, state}

        # `:closed` is in `Arangox.Client.connection_lost_reasons/0` and so
        # forces a disconnect.
        {:error, reason} ->
          {:error, normalize(reason), state}

        # Decoded, but not a VelocyStream response message. Without this
        # clause a `WithClauseError` escapes the callback.
        other ->
          {:error, malformed(other), state}
      end
    rescue
      # A raise here can land after the request was written — a response the
      # framing math chokes on arrives with unread bytes still on the socket —
      # so the connection cannot be resynchronised and must not go back to the
      # pool. `:closed` is in `connection_lost_reasons/0`, which forces the
      # disconnect. Encoding failures on caller data never reach this
      # clause: `encode_term/1` catches them before anything is written.
      exception ->
        {:error, %Error{reason: :closed, message: Exception.message(exception)}, state}
    catch
      :exit, reason ->
        {:error,
         %Error{reason: retiring(caught_reason(reason)), message: "exited: #{inspect(reason)}"},
         state}

      :throw, value ->
        {:error, %Error{reason: :closed, message: "threw: #{inspect(value)}"}, state}
    end

    # An exit mid-request leaves the socket in an unknown state, so a reason
    # the pool would not retire on is replaced with one it does; `:noproc` and
    # friends keep their more precise selves.
    defp retiring(reason) do
      if Client.connection_lost?(reason), do: reason, else: :closed
    end

    # `Arangox.method/0` names seven methods and nothing enforces that at
    # runtime, so the fallback is reachable. It must not answer a sentinel
    # integer: VelocyStream defines no such method, so the request would go
    # out, the server could not reply, and the caller would wait out its budget
    # for a `:timeout`.
    # It returns rather than raises because `request/3` must not raise,
    # which `Arangox.ClientContractTest` pins for every client.
    defp method_for(:delete), do: {:ok, 0}
    defp method_for(:get), do: {:ok, 1}
    defp method_for(:post), do: {:ok, 2}
    defp method_for(:put), do: {:ok, 3}
    defp method_for(:head), do: {:ok, 4}
    defp method_for(:patch), do: {:ok, 5}
    defp method_for(:options), do: {:ok, 6}
    defp method_for(method), do: {:unsupported_method, method}

    # ------- Begin Query Parsing Functions (Plataformatec) --------

    defp query_for(nil), do: %{}

    defp query_for(query) do
      parts = :binary.split(query, "&", [:global])

      Enum.reduce(Enum.reverse(parts), %{}, &decode_www_pair(&1, &2))
    end

    defp decode_www_pair("", acc), do: acc

    defp decode_www_pair(binary, acc) do
      current =
        case :binary.split(binary, "=") do
          [key, value] ->
            {decode_www_form(key), decode_www_form(value)}

          [key] ->
            {decode_www_form(key), nil}
        end

      decode_pair(current, acc)
    end

    defp decode_www_form(value), do: URI.decode_www_form(value)

    defp decode_pair({key, value}, acc) do
      if key != "" and :binary.last(key) == ?] do
        subkey = :binary.part(key, 0, byte_size(key) - 1)

        assign_split(:binary.split(subkey, "["), value, acc, :binary.compile_pattern("]["))
      else
        assign_map(acc, key, value)
      end
    end

    defp assign_split(["", rest], value, acc, pattern) do
      parts = :binary.split(rest, pattern)

      case acc do
        [_ | _] -> [assign_split(parts, value, :none, pattern) | acc]
        :none -> [assign_split(parts, value, :none, pattern)]
        _ -> acc
      end
    end

    defp assign_split([key, rest], value, acc, pattern) do
      parts = :binary.split(rest, pattern)

      case acc do
        %{^key => current} ->
          Map.put(acc, key, assign_split(parts, value, current, pattern))

        %{} ->
          Map.put(acc, key, assign_split(parts, value, :none, pattern))

        _ ->
          %{key => assign_split(parts, value, :none, pattern)}
      end
    end

    defp assign_split([""], nil, acc, _pattern) do
      case acc do
        [_ | _] -> acc
        _ -> []
      end
    end

    defp assign_split([""], value, acc, _pattern) do
      case acc do
        [_ | _] -> [value | acc]
        :none -> [value]
        _ -> acc
      end
    end

    defp assign_split([key], value, acc, _pattern) do
      assign_map(acc, key, value)
    end

    defp assign_map(acc, key, value) do
      case acc do
        %{^key => _} -> acc
        %{} -> Map.put(acc, key, value)
        _ -> %{key => value}
      end
    end

    # ------- End Query Parsing Functions --------

    # VelocyStream carries request headers as a VPack *map*, so the wire
    # format itself cannot express a repeated name: `:maps.from_list/1` keeps
    # the right-most occurrence and drops the rest, and names keep whatever
    # casing the caller used. This collapse is this client's own — the HTTP
    # clients deliver the list as given.
    defp headers_for(%{} = headers), do: headers
    defp headers_for(headers) when is_list(headers), do: :maps.from_list(headers)

    # VelocyStream delivers response headers as a VPack map, so the list is
    # built from it: no repeated name can arrive, and the order is the map's
    # key order, not the order the server wrote them. Names keep the server's
    # casing.
    defp response_headers(headers) when is_map(headers), do: Map.to_list(headers)
    defp response_headers(headers), do: headers

    defp body_for(""), do: {:ok, ""}
    defp body_for(body), do: encode_term(body)

    # `VelocyPack.encode/1` raises rather than returning `{:error, _}` for a
    # term it has no encoder for — a struct with no `Enumerable`, say. That is
    # the caller's data failing before anything reached the wire, so it must
    # not take the `request/3` rescue, whose reason retires the connection.
    defp encode_term(term) do
      VelocyPack.encode(term)
    rescue
      exception ->
        {:error, %Error{reason: :encode_error, message: Exception.message(exception)}}
    end

    defp body_from([]), do: nil
    defp body_from([body]), do: body
    defp body_from(body), do: body

    # The chunk size is resolved per pool at connect and arrives from
    # connection state, so it is an argument rather than a module attribute.
    defp build_stream(message, vst_maxsize) do
      [first_chunk | rest_chunks] =
        chunks = chunk_every(message, vst_maxsize - @chunk_header_size)

      n_chunks = length(chunks)
      msg_length = byte_size(message) + n_chunks * @chunk_header_size

      # The first chunk carries the chunk *count* and the rest carry their own
      # index from 1, which is how a reader learns how many to wait for.
      numbered_rest =
        rest_chunks
        |> Enum.with_index(1)
        |> Enum.map(fn {chunk, n} -> prepend_chunk(chunk, n, 0, 0, msg_length) end)

      [prepend_chunk(first_chunk, n_chunks, 1, 0, msg_length) | numbered_rest]
    end

    # Always a list, one element included. `build_stream/2` and `send_stream/2`
    # both depend on that: a bare binary for the single-chunk case forces a
    # second branch in each, and makes the numbering comprehension build a
    # descending range for a message that fits in one chunk.
    defp chunk_every(bytes, size) when byte_size(bytes) <= size, do: [bytes]

    defp chunk_every(bytes, size) do
      <<chunk::binary-size(size), rest::binary>> = bytes

      [chunk | chunk_every(rest, size)]
    end

    defp prepend_chunk(chunk, chunk_n, is_first, msg_id, msg_length) do
      <<
        @chunk_header_size + byte_size(chunk)::little-32,
        :binary.decode_unsigned(<<chunk_n::31, is_first::1>>, :little)::32,
        msg_id::little-64,
        msg_length::little-64,
        chunk::binary
      >>
    end

    # Stops at the first chunk that fails and answers with its reason. Must be
    # an error return rather than a throw: the caller cannot match on a throw.
    #
    # The write half of the deadline: each chunk's send is bounded by the budget remaining
    # *at that chunk*, re-derived through a per-chunk `setopts`. A fixed bound
    # would let an N-chunk stream against a peer that stopped reading block
    # for N bounds, with the deadline consulted only at the first receive.
    defp send_stream({mod, port}, chunks, deadline, opts, state) do
      Enum.reduce_while(chunks, :ok, fn chunk, :ok ->
        case Client.socket_timeout(deadline, opts, state) do
          :elapsed ->
            {:halt,
             {:error,
              %Error{
                reason: :timeout,
                message: "the request timeout elapsed before the request was fully sent"
              }}}

          {:ok, remaining} ->
            _ = set_send_timeout(mod, port, remaining)

            case mod.send(port, chunk) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end
        end
      end)
    end

    # Best-effort: a socket `setopts` cannot reach is about to fail its send
    # anyway, with a better-typed error than this call could build. A
    # transport module other than the two real ones (the config suite drives
    # this client over a fake) bounds its own sends.
    defp set_send_timeout(:gen_tcp, port, timeout),
      do: :inet.setopts(port, send_timeout: timeout)

    defp set_send_timeout(:ssl, port, timeout),
      do: :ssl.setopts(port, send_timeout: timeout)

    defp set_send_timeout(_transport, _port, _timeout), do: :ok

    # The receive bound. Both receives must use the three-argument
    # `recv/3`; the two-argument form takes no timeout and waits forever.
    defp timeout_for(deadline, opts, state) do
      case Client.socket_timeout(deadline, opts, state) do
        {:ok, timeout} ->
          {:ok, timeout}

        :elapsed ->
          {:error,
           %Error{
             reason: :timeout,
             message: "the request timeout elapsed before the response was fully received"
           }}
      end
    end

    defp recv_header(socket, deadline, opts, state) do
      case timeout_for(deadline, opts, state) do
        {:ok, timeout} -> do_recv_header(socket, timeout)
        {:error, _reason} = error -> error
      end
    end

    defp do_recv_header({mod, port}, timeout) do
      case mod.recv(port, @chunk_header_size, timeout) do
        {:ok,
         <<
           chunk_length::little-32,
           chunk_x::32,
           msg_id::little-64,
           msg_length::little-64
         >>}
        when chunk_length >= @chunk_header_size ->
          <<chunk_n::31, is_first::1>> = <<chunk_x::little-32>>

          {:ok, [chunk_length, chunk_n, is_first, msg_id, msg_length]}

        # A length field smaller than the header it arrived in cannot come
        # from a conforming peer: these bytes are mid-stream garbage and the
        # socket cannot be resynchronised.
        {:ok, _header} ->
          {:error,
           %Error{reason: :closed, message: "malformed VelocyStream chunk header received"}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    # TODO: this could be refactored to decode streams as they are received
    defp recv_stream(socket, [chunk_length, 1, 1, _msg_id, _msg_length], deadline, opts, state),
      do: recv_chunk(socket, chunk_length, deadline, opts, state)

    defp recv_stream(
           socket,
           [chunk_length, n_chunks, 1, _msg_id, _msg_length],
           deadline,
           opts,
           state
         ) do
      with(
        {:ok, buffer} <-
          recv_chunk(socket, chunk_length, deadline, opts, state),
        {:ok, stream} <-
          recv_stream(socket, n_chunks, buffer, deadline, opts, state)
      ) do
        {:ok, stream}
      end
    end

    defp recv_stream(socket, n_chunks, buffer, deadline, opts, state) do
      Enum.reduce_while(1..(n_chunks - 1), buffer, fn n, buffer ->
        with(
          {:ok, [chunk_length, _, _, _, _]} <-
            recv_header(socket, deadline, opts, state),
          {:ok, chunk} <-
            recv_chunk(socket, chunk_length, deadline, opts, state)
        ) do
          if n == n_chunks - 1 do
            {:halt, {:ok, buffer <> chunk}}
          else
            {:cont, buffer <> chunk}
          end
        else
          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)
    end

    defp recv_chunk({mod, port}, chunk_length, deadline, opts, state) do
      case timeout_for(deadline, opts, state) do
        {:ok, timeout} -> mod.recv(port, chunk_length - @chunk_header_size, timeout)
        {:error, _reason} = error -> error
      end
    end

    defp decode_stream(stream, acc \\ [])

    defp decode_stream("", acc), do: {:ok, acc}

    defp decode_stream(stream, acc) do
      case VelocyPack.decode(stream) do
        {:ok, {term, rest}} ->
          decode_stream(rest, acc ++ [term])

        {:ok, term} ->
          {:ok, acc ++ [term]}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl true
    def alive?(%Connection{} = state) do
      case request(%Request{method: :options, path: "/"}, [], state) do
        {:ok, _response, _state} ->
          true

        {:error, _reason, _state} ->
          false
      end
    end

    @impl true
    def close(%Connection{socket: {mod, port}}), do: mod.close(port)

    ## Error normalization

    # The one place a transport or VelocyPack failure becomes an
    # `Arangox.Error`. `:endpoint` stays `nil` on everything built here: this
    # module only ever sees a parsed `Arangox.Endpoint`, which carries no
    # userinfo, and `Arangox.Connection` fills in the redacted configured
    # endpoint.
    defp normalize(%Error{} = error), do: error

    # `:gen_tcp`/`:ssl` speak in bare POSIX atoms, including `:closed`, which is
    # in `Arangox.Client.connection_lost_reasons/0`.
    defp normalize(reason) when is_atom(reason),
      do: %Error{reason: reason, message: inspect(reason)}

    defp normalize(exception) when is_exception(exception),
      do: %Error{reason: :client_error, message: Exception.message(exception)}

    # Since OTP 26 `:ssl` verifies peers by default but supplies no trust
    # material of its own, so a TLS connection with no `:ssl_opts` fails on the
    # options rather than on the handshake. The raw tuple names neither the
    # cause nor the fix, and this is the first thing anyone enabling TLS on this
    # client meets. Reporting it is this driver's job; supplying a default
    # answer to it is not.
    defp normalize({:options, :incompatible, details} = reason) do
      if Keyword.get(details, :cacerts) == :undefined and
           Keyword.get(details, :verify) == :verify_peer do
        %Error{
          reason: :options,
          message:
            "TLS is enabled but no trust material was given, and :ssl verifies peers by " <>
              "default. Pass the authority that signed the server's certificate with " <>
              "ssl_opts: [cacertfile: \"/path/to/ca.pem\"], or ssl_opts: [verify: :verify_none] " <>
              "to connect without checking. Got: #{inspect(reason)}"
        }
      else
        %Error{reason: :options, message: inspect(reason)}
      end
    end

    # `:ssl` reports option and handshake failures as `{:options, details}`,
    # `{:tls_alert, details}` and friends. The tag is the part worth matching on.
    defp normalize(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
      case elem(reason, 0) do
        tag when is_atom(tag) -> %Error{reason: tag, message: inspect(reason)}
        _other -> %Error{reason: :client_error, message: inspect(reason)}
      end
    end

    defp normalize(reason), do: %Error{reason: :client_error, message: inspect(reason)}

    defp malformed(other) do
      %Error{
        reason: :client_error,
        message: "malformed VelocyStream response: #{inspect(other)}"
      }
    end

    defp caught_reason(reason) when is_atom(reason), do: reason
    defp caught_reason(_reason), do: :client_error
  end
end
