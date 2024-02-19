defmodule Arangox.Auth do
  @type bearer :: String.t()
  @type username :: String.t()
  @type password :: String.t()
  @type t ::
          :off
          | {:basic, username, password}
          | {:jwt, bearer}

  def validate(auth) do
    case auth do
      :off ->
        :ok

      {:basic, _username, _password} ->
        :ok

      {:jwt, _bearer} ->
        :ok

      _ ->
        raise ArgumentError, """
        The :auth expects one of the following options: \
        `{:basic, username, password}`, `{:jwt, bearer}`,\
        got: #{inspect(auth)}
        """
    end
  end
end
