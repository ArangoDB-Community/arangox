defmodule Arangox.Auth do
  @moduledoc """
  The shapes the `:auth` start option accepts.

  `validate/1` rejects anything else **without printing the value**: the
  value is the credential, and a `start_link/1` that raises is the most likely
  thing anyone pastes into an issue.
  """

  @type username :: String.t()
  @type password :: String.t()
  @type token :: String.t()

  @type t :: {:basic, username, password} | {:bearer, token}

  @doc """
  Returns `:ok` for a supported `:auth` value, raises `ArgumentError` otherwise.

  Every credential must be a string: these values are interpolated into an
  authorization header (or a VelocyStream auth message), and only a string has
  a rendering that is the credential itself rather than a term dump.

  The raised message describes the *shape* it received and never the value.
  """
  @spec validate(term) :: :ok
  def validate(auth) do
    case auth do
      {:basic, username, password} when is_binary(username) and is_binary(password) ->
        :ok

      {:bearer, token} when is_binary(token) ->
        :ok

      _ ->
        raise ArgumentError, """
        The :auth option expects one of the following, with every credential a string:

            {:basic, username, password}
            {:bearer, token}

        Instead, got: #{describe(auth)}
        """
    end
  end

  @doc false
  # Enough to see what is wrong; never enough to see the credential. A tuple is
  # described by its tag and size, because that is what is actually wrong with
  # a mistyped `:auth`, and everything else by its type alone. Public because
  # `Arangox.Connection` describes a rejected `:auth` the same way when a pool
  # was started around `validate/1`.
  @spec describe(term) :: binary
  def describe(auth) when is_tuple(auth) and tuple_size(auth) > 0 do
    case elem(auth, 0) do
      tag when is_atom(tag) ->
        "a #{tuple_size(auth)}-element tuple tagged #{inspect(tag)}"

      _other ->
        "a #{tuple_size(auth)}-element tuple"
    end
  end

  def describe(auth) when is_tuple(auth), do: "an empty tuple"
  def describe(nil), do: "nil"
  def describe(auth) when is_binary(auth), do: "a #{byte_size(auth)}-byte binary"
  def describe(auth) when is_atom(auth), do: "an atom"
  def describe(auth) when is_list(auth), do: "a #{length(auth)}-element list"
  def describe(auth) when is_map(auth), do: "a map with #{map_size(auth)} keys"
  def describe(auth) when is_function(auth), do: "a function"
  def describe(_auth), do: "an unsupported value"
end
