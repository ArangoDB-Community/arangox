defmodule Arangox.ErrorTest do
  use ExUnit.Case, async: true
  alias Arangox.Error

  @endpoint %Error{
    message: "message",
    endpoint: "endpoint"
  }

  @status %Error{
    message: "message",
    status: "status"
  }

  @endpoint_and_status %Error{
    message: "message",
    endpoint: "endpoint",
    status: "status"
  }

  test "stringify non-binary messages" do
    assert Exception.message(%Error{message: :a}) == ":a"
    assert Exception.message(%Error{message: {}}) == "{}"
    assert Exception.message(%Error{message: %{}}) == "%{}"
  end

  test "prepend messages with keys when present" do
    assert Exception.message(%Error{message: "message"}) == "message"
    assert Exception.message(@endpoint) == "[endpoint] message"
    assert Exception.message(@status) == "[status] message"
    assert Exception.message(@endpoint_and_status) == "[endpoint] [status] message"
  end
end
