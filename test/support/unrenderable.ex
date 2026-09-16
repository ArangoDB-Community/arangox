defmodule Arangox.TestSupport.Unrenderable do
  @moduledoc """
  A header value whose `String.Chars` implementation throws rather than
  raises, for the connect-time guard that must catch all three failure kinds.

  Lives in `test/support` rather than in the test file that uses it because
  `String.Chars` is consolidated: an implementation compiled at test *runtime*
  is invisible to `to_string/1`, which then raises `Protocol.UndefinedError`
  instead — a different failure kind than the one under test.
  """

  defstruct []
end

defimpl String.Chars, for: Arangox.TestSupport.Unrenderable do
  def to_string(_value), do: throw(:not_a_string)
end
