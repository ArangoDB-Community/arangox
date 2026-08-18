defmodule ReadmeTest do
  # The README's examples call `Arangox.start_link/1` and issue requests
  # against a live server, so the whole file is integration tier.
  use ExUnit.Case, async: false

  # The README documents both server lines — the active-failover example talks
  # to the 3.11 trio — so this file needs the full stack. The tag *value* is
  # what keeps it out of the profile-isolated CI legs, which select
  # `integration:true` and `integration:arango_3_11`; the bare `--only
  # integration` filter of `mix test.integration` matches any value, so the
  # local full-stack workflow still runs it.
  @moduletag integration: :readme

  doctest_file("README.md")
end
