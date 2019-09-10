defmodule Arangox.Error do
  defexception [
    :status,
    :endpoint,
    message: "arangox error"
  ]

  @type t :: %__MODULE__{
          status: pos_integer | nil,
          endpoint: binary | nil,
          message: binary
        }

  def message(%__MODULE__{message: message} = exception) when is_binary(message) do
    prepend(exception) <> message
  end

  def message(%__MODULE__{message: message} = exception) do
    prepend(exception) <> inspect(message)
  end

  defp prepend(%__MODULE__{endpoint: nil, status: nil}), do: ""

  defp prepend(%__MODULE__{endpoint: endpoint, status: nil}), do: "[#{endpoint}] "

  defp prepend(%__MODULE__{endpoint: nil, status: status}), do: "[#{status}] "

  defp prepend(%__MODULE__{endpoint: endpoint, status: status}), do: "[#{endpoint}] [#{status}] "
end
