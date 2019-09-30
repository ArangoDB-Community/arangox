defmodule Arangox.Error do
  @type t :: %__MODULE__{
          endpoint: Arangox.endpoint() | nil,
          status: pos_integer | nil,
          error_num: non_neg_integer,
          message: binary
        }

  @keys [
    :endpoint,
    :status,
    :error_num
  ]

  defexception [{:message, "arangox error"} | @keys]

  def message(%__MODULE__{message: message} = exception) when is_binary(message) do
    prepend(exception) <> message
  end

  def message(%__MODULE__{message: message} = exception) do
    prepend(exception) <> inspect(message)
  end

  defp prepend(%__MODULE__{} = exception) do
    for key <- @keys, into: "" do
      exception
      |> Map.get(key)
      |> prepend()
    end
  end

  defp prepend(nil), do: ""
  defp prepend(key), do: "[#{key}] "
end
