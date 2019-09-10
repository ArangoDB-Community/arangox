defmodule Arangox.RequestTest do
  use ExUnit.Case, async: true
  alias Arangox.{Request, Response}
  alias DBConnection.Query

  @request %Request{method: :method, path: "/path"}
  @response %Response{status: 000, headers: []}

  test "body must default to \"\" and headers to []" do
    assert @request == %{@request | body: "", headers: []}
  end

  describe "DBConnection.Query protocol:" do
    test "parse" do
      assert Query.parse(@request, []) == @request
    end

    test "describe" do
      assert Query.describe(@request, []) == @request
    end

    test "encode" do
      assert Query.encode(%{@request | body: nil}, [], []) == %{@request | body: "null"}
      assert Query.encode(%{@request | path: "path"}, [], []) == %{@request | path: "/path"}
    end

    test "decode" do
      assert Query.decode(@request, %{@response | body: nil}, []) == %{@response | body: nil}
      assert Query.decode(@request, %{@response | body: "null"}, []) == %{@response | body: nil}
    end
  end
end
