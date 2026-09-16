defmodule ArangoxDocTest do
  # `Arangox`'s own `@moduledoc` is the README (`lib/arangox.ex` reads it at
  # compile time), and `ReadmeTest` already runs that text with `doctest_file`.
  # Excluding it here leaves the function docs, which nothing ran before: their
  # examples call `Arangox.start_link/1` and issue requests, so they are
  # integration tier for the same reason the README is.
  use ExUnit.Case, async: false

  @moduletag :integration

  doctest Arangox, except: [:moduledoc]
end
