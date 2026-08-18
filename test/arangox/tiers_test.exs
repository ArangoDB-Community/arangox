defmodule Arangox.TiersTest do
  @moduledoc """
  Guards the three-tier split of the suite.

  Tier 1 (unit) and tier 2 (protocol, via `Arangox.ProtocolServer`) run on a
  fresh clone with nothing else installed. Tier 3 (integration) needs the
  ArangoDB containers from `docker-compose.yml` and is therefore excluded by
  default, so that `mix test` is green without Docker. `mix test.integration`
  (`mix test --only integration`) opts back in.
  """

  use ExUnit.Case, async: true

  test ":integration is excluded by default so `mix test` needs no Docker" do
    assert :integration in List.wrap(ExUnit.configuration()[:exclude])
  end
end
