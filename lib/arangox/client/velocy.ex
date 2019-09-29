if Code.ensure_compiled?(Velocy) do
  defmodule Arangox.VelocyClient do
    @moduledoc """
    The default client. Implements the \
    [VelocyStream](https://github.com/arangodb/velocystream) \
    protocol.

    URI query parsing functions proudly stolen from Plataformatec and
    licensed under Apache 2.0.
    """

    alias Arangox.{
      Client,
      Connection,
      Endpoint,
      Error,
      Request,
      Response
    }

    @behaviour Client

    @vst_version 1.1
    @trunc_vst_version Kernel.trunc(@vst_version)
    @chunk_header_size 24

    @doc """
    Returns the configured maximum size (in bytes) for a _VelocyPack_ chunk.

    To change the chunk size, include the following in your `config/config.exs`:

        config :arangox, :vst_maxsize, 12_345

    Defaults to `30_720`.
    """
    @spec vst_maxsize() :: pos_integer()
    def vst_maxsize, do: Application.get_env(:arangox, :vst_maxsize, 30_720)

    @spec authorize(Connection.t()) :: :ok | {:error, Error.t()}
    def authorize(%Connection{socket: socket, username: un, password: pw} = state) do
      auth = [1, 1000, "plain", un, pw]

      with(
        {:ok, auth} <- Velocy.encode(auth),
        :ok <- send_stream(socket, build_stream(auth)),
        {:ok, header} <- recv_header(socket),
        {:ok, stream} <- recv_stream(socket, header),
        {:ok, [[@trunc_vst_version, 2, 200, _headers] | _body]} <- decode_stream(stream)
      ) do
        :ok
      else
        {:ok, [[@trunc_vst_version, 2, status, _headers] | [body | _]]} ->
          {:error,
           %Error{
             status: status,
             message: body["errorMessage"],
             endpoint: state.endpoint
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl true
    def connect(%Endpoint{addr: addr, ssl?: ssl?}, opts) do
      mod = if ssl?, do: :ssl, else: :gen_tcp
      transport_opts = if ssl?, do: :ssl_opts, else: :tcp_opts
      transport_opts = Keyword.get(opts, transport_opts, [])
      connect_timeout = Keyword.get(opts, :connect_timeout, 5_000)

      options = Keyword.merge(transport_opts, packet: :raw, mode: :binary, active: false)

      open(mod, addr, options, connect_timeout)
    end

    defp open(mod, addr, options, timeout) do
      with(
        {:ok, port} <- mod.connect(addr_for(addr), port_for(addr), options, timeout),
        :ok <- mod.send(port, "VST/#{@vst_version}\r\n\r\n")
      ) do
        {:ok, [mod, port]}
      else
        {:error, reason} ->
          {:error, reason}
      end
    end

    defp addr_for({:unix, path}), do: {:local, to_charlist(path)}
    defp addr_for({:tcp, host, _port}), do: to_charlist(host)

    defp port_for({:unix, _path}), do: 0
    defp port_for({:tcp, _host, port}), do: port

    @impl true
    def request(%Request{} = request, %Connection{socket: socket} = state) do
      uri = URI.parse(request.path)
      body = request.body

      request = [
        @trunc_vst_version,
        1,
        case request.path do
          "/_db/" <> rest ->
            rest
            |> String.split("/")
            |> hd()

          _ ->
            state.database || ""
        end,
        method_for(request.method),
        uri.path,
        query_for(uri.query),
        Map.new(request.headers)
      ]

      with(
        {:ok, request} <- Velocy.encode(request),
        {:ok, body} <- body_for(body),
        :ok <- send_stream(socket, build_stream(request <> body)),
        {:ok, header} <- recv_header(socket),
        {:ok, stream} <- recv_stream(socket, header),
        {:ok, [[@trunc_vst_version, 2, status, headers] | body]} <- decode_stream(stream)
      ) do
        {:ok, %Response{status: status, headers: headers, body: body_from(body)}, state}
      else
        {:error, :closed} ->
          {:error, :noproc, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    end

    defp method_for(:delete), do: 0
    defp method_for(:get), do: 1
    defp method_for(:post), do: 2
    defp method_for(:put), do: 3
    defp method_for(:head), do: 4
    defp method_for(:patch), do: 5
    defp method_for(:options), do: 6
    defp method_for(_), do: -1

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

    defp body_for(""), do: {:ok, ""}
    defp body_for(body), do: Velocy.encode(body)

    defp body_from([]), do: nil
    defp body_from([body]), do: body
    defp body_from(body), do: body

    defp build_stream(message, maxsize \\ vst_maxsize()) do
      unless maxsize > @chunk_header_size,
        do: raise(":vst_maxsize must be greater than #{@chunk_header_size}")

      case chunk_every(message, maxsize - @chunk_header_size) do
        [first_chunk | rest_chunks] ->
          n_chunks = length([first_chunk | rest_chunks])
          msg_length = byte_size(message) + n_chunks * @chunk_header_size

          rest_chunks =
            for n <- 1..length(rest_chunks), rest_chunks != [] do
              rest_chunks
              |> Enum.fetch!(n - 1)
              |> prepend_chunk(n, 0, 0, msg_length)
            end

          [prepend_chunk(first_chunk, n_chunks, 1, 0, msg_length) | rest_chunks]

        only_chunk ->
          prepend_chunk(only_chunk, 1, 1, 0, byte_size(message) + @chunk_header_size)
      end
    end

    defp chunk_every(bytes, size) when byte_size(bytes) <= size, do: bytes

    defp chunk_every(bytes, size) do
      <<chunk::binary-size(size), rest::binary>> = bytes

      [chunk | List.wrap(chunk_every(rest, size))]
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

    defp send_stream([mod, port], chunk) when is_binary(chunk), do: mod.send(port, chunk)

    defp send_stream([mod, port], chunks) when is_list(chunks) do
      for p <- chunks do
        mod.send(port, p)
      end
      |> Enum.filter(&(&1 != :ok))
      |> case do
        [] -> :ok
        errors -> {:error, Enum.map(errors, &elem(&1, 1))}
      end
    end

    defp recv_header([mod, port]) do
      case mod.recv(port, @chunk_header_size) do
        {:ok,
         <<
           chunk_length::little-32,
           chunk_x::32,
           msg_id::little-64,
           msg_length::little-64
         >>} ->
          <<chunk_n::31, is_first::1>> = :binary.encode_unsigned(chunk_x, :little)

          {:ok, [chunk_length, chunk_n, is_first, msg_id, msg_length]}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp recv_stream(socket, [chunk_length, 1, 1, _msg_id, _msg_length]),
      do: recv_chunk(socket, chunk_length)

    defp recv_stream(socket, [chunk_length, n_chunks, 1, _msg_id, _msg_length]) do
      with(
        {:ok, buffer} <- recv_chunk(socket, chunk_length),
        {:ok, stream} <- recv_stream(socket, n_chunks, buffer)
      ) do
        {:ok, stream}
      else
        {:error, reason} ->
          {:error, reason}
      end
    end

    defp recv_stream(socket, n_chunks, buffer) do
      Enum.reduce_while(1..(n_chunks - 1), buffer, fn n, buffer ->
        with(
          {:ok, [chunk_length, _, _, _, _]} <- recv_header(socket),
          {:ok, chunk} <- recv_chunk(socket, chunk_length)
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

    defp recv_chunk([mod, port], chunk_length),
      do: mod.recv(port, chunk_length - @chunk_header_size)

    defp decode_stream(stream, acc \\ [])

    defp decode_stream("", acc), do: {:ok, acc}

    defp decode_stream(stream, acc) do
      case Velocy.decode(stream) do
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
      case request(%Request{method: :options, path: "/"}, state) do
        {:ok, _response, _state} ->
          true

        {:error, _reason, _state} ->
          false
      end
    end

    @impl true
    def close(%Connection{socket: [mod, port]}), do: mod.close(port)
  end
end
