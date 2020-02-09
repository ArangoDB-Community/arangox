defmodule Arangox.EndpointTest do
  use ExUnit.Case, async: true
  alias Arangox.Endpoint
  import Arangox.Endpoint

  test "parsing an endpoint" do
    assert %Endpoint{addr: {:tcp, "host", 123}, ssl?: false} = new("tcp://host:123")
    assert %Endpoint{addr: {:tcp, "host", 123}, ssl?: true} = new("ssl://host:123")
    assert %Endpoint{addr: {:tcp, "host", 123}, ssl?: true} = new("tls://host:123")
    assert %Endpoint{addr: {:tcp, "host", 123}, ssl?: false} = new("http://host:123")
    assert %Endpoint{addr: {:tcp, "host", 123}, ssl?: true} = new("https://host:123")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: false} = new("unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: false} = new("tcp+unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("ssl+unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("tls+unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: false} = new("http+unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("https+unix:///path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: false} = new("tcp://unix:/path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("ssl://unix:/path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("tls://unix:/path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: false} = new("http://unix:/path.sock")
    assert %Endpoint{addr: {:unix, "/path.sock"}, ssl?: true} = new("https://unix:/path.sock")

    assert_raise ArgumentError, fn -> new("") end
    assert_raise ArgumentError, fn -> new("host") end
    assert_raise ArgumentError, fn -> new("host:123") end

    assert_raise ArgumentError,
                 "Missing host or port in endpoint configuration: \"http://\"",
                 fn -> new("http://") end

    assert_raise ArgumentError,
                 "Missing host or port in endpoint configuration: \"http://host\"",
                 fn -> new("http://host") end

    assert_raise ArgumentError,
                 "Missing host or port in endpoint configuration: \"http://:123\"",
                 fn -> new("http://:123") end

    assert_raise ArgumentError,
                 "Invalid protocol in endpoint configuration: \"unexpected://host:123\"",
                 fn -> new("unexpected://host:123") end

    assert_raise ArgumentError,
                 "Invalid protocol in endpoint configuration: \"unexpected+ssl://host:123\"",
                 fn -> new("unexpected+ssl://host:123") end

    assert_raise ArgumentError,
                 "Invalid protocol in endpoint configuration: \"http+unexpected://host:123\"",
                 fn -> new("http+unexpected://host:123") end
  end
end
