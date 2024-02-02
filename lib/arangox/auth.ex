defmodule Arangox.Auth do
  @type t :: :authentication_off | :authentication_basic | :authentication_jwt

  def off, do: :authentication_off
  def basic, do: :authentication_basic
  def jwt, do: :authentication_jwt
  def allTypes, do: [:authentication_off, :authentication_basic, :authentication_jwt]
end