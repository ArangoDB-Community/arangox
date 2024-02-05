defmodule Arangox.Auth do
  @type jwt_token :: String.t()
  @type username :: String.t()
  @type password :: String.t()
  @type t ::
          :authentication_off
          | {:authentication_basic, username, password}
          | {:authentication_jwt, jwt_token}

  def off, do: :authentication_off
  def basic, do: :authentication_basic
  def jwt, do: :authentication_jwt

  def validate(auth_mode) do
    case auth_mode do
      :authentication_off ->
        :ok

      {:authentication_basic, _username, _password} ->
        :ok

      {:authentication_jwt, _jwt_token} ->
        :ok

      _ ->
        raise ArgumentError, """
        The :auth_mode expects one of the following options: `Arangox.Auth.off()`,\
        `{Arangox.Auth.basic(), username, password}`, `{Arangox.Auth.jwt(), jwt_token}`,\
        got: #{inspect(auth_mode)}
        """
    end
  end
end