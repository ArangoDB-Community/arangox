defmodule Arangox.Auth do
  @type username :: String.t()
  @type password :: String.t()
  @type token :: String.t()

  @type t :: {:basic, username, password} | {:bearer, token}

  def validate(auth) do
    case auth do
      {:basic, _username, _password} ->
        :ok

      {:bearer, _token} ->
        :ok

      _ ->
        raise ArgumentError, """
        The :auth option expects one of the following:

            {:basic, username, password}
            {:bearer, token},

        Instead, got: #{inspect(auth)}
        """
    end
  end
end
