defmodule Arangox.Error do
  @moduledoc """
  The one error struct arangox produces.

  Every `Arangox.Client` callback that fails returns one of these, and every
  error `Arangox` hands back is one of these. There is no second error shape.

  ## Fields

    * `:reason` - an atom for pattern matching. Either a code from
      `Arangox.Errno` (`:arango_document_not_found`, `:arango_conflict`, ...)
      when the server supplied an `errorNum`, or a transport reason
      (`:econnrefused`, `:closed`, ...) when the failure happened below HTTP.
      `nil` only when neither is known. See `Arangox.Client` for which reasons
      mean the socket is gone. Two of them are arangox's own: `:timeout`,
      a request that ran out of time on the socket — which retires the
      connection, since arangox cannot tell where the abandoned response ended
      — and `:deadline_exceeded`, a request that was never sent because the
      caller's budget was already spent queueing for a connection, which leaves
      the connection healthy and checked in.
    * `:status` - the HTTP status, when the server responded.
    * `:error_num` - the raw ArangoDB `errorNum`, when the body supplied one.
      Always present together with `:status`, and preserved even when the
      number is absent from the vendored table and `:reason` is therefore
      `:unknown`.
    * `:endpoint` - the endpoint the failure happened against, **with any
      userinfo stripped**. See `Arangox.Endpoint.redact/1`.
    * `:message` - the human-readable message.

  ## Branch on `:reason`, not on `:message`

  `:message` is usually **the server's own message, verbatim**. ArangoDB
  controls its wording and changes it between releases, and it may contain
  values from the request. It is for humans and logs. `:reason` (and `:status`
  and `:error_num`) is the machine-readable surface:

      case Arangox.get(conn, path) do
        {:error, %Arangox.Error{reason: :arango_document_not_found}} -> :gone
        {:error, %Arangox.Error{reason: :arango_conflict}} -> retry()
      end

  Because the message is server-controlled it is **length-bounded when
  rendered**: `Exception.message/1` truncates at `message_limit/0` bytes, so a
  pathological body cannot flood a log line. The `:message` field itself is
  untouched.

  ## Nothing here carries credentials

  Redaction is unconditional and has no opt-out: no message, no struct inspection and
  no log line arangox produces contains authentication material. The endpoint is
  redacted where it is *stored*, not only where it is rendered, so
  `Exception.message/1`, `inspect/1` and the `failed to connect` line
  `DBConnection` logs are all covered by the same fix.
  """

  alias Arangox.Errno

  @type t :: %__MODULE__{
          endpoint: Arangox.endpoint() | nil,
          status: pos_integer | nil,
          error_num: non_neg_integer | nil,
          reason: Errno.t() | atom | nil,
          message: binary
        }

  # Only these join the rendered message prefix. `:reason` deliberately does
  # not: it is the pattern-matching surface, and adding it here would
  # change every existing message string.
  @keys [
    :endpoint,
    :status,
    :error_num
  ]

  @message_limit 2048

  defexception [{:message, "arangox error"}, {:reason, nil} | @keys]

  @doc """
  The maximum number of bytes of `:message` that `message/1` renders.
  """
  @spec message_limit() :: pos_integer
  def message_limit, do: @message_limit

  def message(%__MODULE__{message: message} = exception) when is_binary(message) do
    prepend(exception) <> bound(message)
  end

  def message(%__MODULE__{message: message} = exception) do
    prepend(exception) <> bound(inspect(message))
  end

  # The server controls this string, so it is bounded before it reaches a log.
  @spec bound(binary) :: binary
  defp bound(message) when byte_size(message) <= @message_limit, do: message

  defp bound(message) do
    binary_part(message, 0, codepoint_cut(message, @message_limit)) <>
      "... (truncated, #{byte_size(message)} bytes)"
  end

  # A byte-positioned cut can land inside a multibyte character and turn a
  # valid message into an invalid binary. Backing off past UTF-8 continuation
  # bytes (0b10xxxxxx) lands it on a boundary; input that was never UTF-8 has
  # no boundaries to respect and is cut wherever the walk stops.
  @spec codepoint_cut(binary, non_neg_integer) :: non_neg_integer
  defp codepoint_cut(message, position) when position > 0 do
    case :binary.at(message, position) do
      byte when byte >= 0x80 and byte < 0xC0 -> codepoint_cut(message, position - 1)
      _boundary -> position
    end
  end

  defp codepoint_cut(_message, position), do: position

  @spec prepend(t) :: binary
  defp prepend(%__MODULE__{} = exception) do
    for key <- @keys, into: "" do
      exception
      |> Map.get(key)
      |> format_key()
    end
  end

  @spec format_key(term) :: binary
  defp format_key(nil), do: ""
  defp format_key(value), do: "[#{value}] "
end
