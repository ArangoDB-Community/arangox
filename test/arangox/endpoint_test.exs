defmodule Arangox.EndpointTest do
  use ExUnit.Case, async: true
  import Arangox.Endpoint

  describe "parsing an endpoint:" do
    test "host defaults to 'localhost'" do
      assert %URI{host: "localhost"} = parse("scheme://")
    end

    test "port defaults to 8529" do
      assert %URI{port: 8529} = parse("scheme://")
    end
  end

  test "determining an ssl endpoint" do
    assert ssl?(URI.parse("ssl://endpoint:port"))
    assert ssl?(URI.parse("https://endpoint:port"))
    refute ssl?(URI.parse("tcp://endpoint:port"))
    refute ssl?(URI.parse("http://endpoint:port"))

    assert ssl?(URI.parse("ssl+unix:///tmp/arangodb.sock"))
    assert ssl?(URI.parse("https+unix:///tmp/arangodb.sock"))
    refute ssl?(URI.parse("unix:///tmp/arangodb.sock"))
    refute ssl?(URI.parse("tcp+unix:///tmp/arangodb.sock"))
    refute ssl?(URI.parse("http+unix:///tmp/arangodb.sock"))

    assert ssl?(URI.parse("ssl://unix:/tmp/arangodb.sock"))
    assert ssl?(URI.parse("https://unix:/tmp/arangodb.sock"))
    refute ssl?(URI.parse("tcp://unix:/tmp/arangodb.sock"))
    refute ssl?(URI.parse("http://unix:/tmp/arangodb.sock"))
  end

  test "determining a unix endpoint" do
    assert unix?(URI.parse("unix:///tmp/arangodb.sock"))
    assert unix?(URI.parse("ssl+unix:///tmp/arangodb.sock"))
    assert unix?(URI.parse("https+unix:///tmp/arangodb.sock"))
    assert unix?(URI.parse("tcp+unix:///tmp/arangodb.sock"))
    assert unix?(URI.parse("http+unix:///tmp/arangodb.sock"))
    assert unix?(URI.parse("ssl://unix:/tmp/arangodb.sock"))
    assert unix?(URI.parse("https://unix:/tmp/arangodb.sock"))
    assert unix?(URI.parse("tcp://unix:/tmp/arangodb.sock"))
    assert unix?(URI.parse("http://unix:/tmp/arangodb.sock"))
    refute unix?(URI.parse("ssl://endpoint:port"))
    refute unix?(URI.parse("https://endpoint:port"))
    refute unix?(URI.parse("tcp://endpoint:port"))
    refute unix?(URI.parse("http://endpoint:port"))
  end
end
