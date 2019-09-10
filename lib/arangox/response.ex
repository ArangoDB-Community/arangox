defmodule Arangox.Response do
  @moduledoc nil

  @type t :: %__MODULE__{
          status: pos_integer,
          headers: [Arangox.header()],
          body: Arangox.body()
        }

  @enforce_keys [:status, :headers]
  defstruct [
    :status,
    :headers,
    :body
  ]
end
