defmodule Arangox.API.SurfaceTest do
  @moduledoc """
  A source-code linter for Arangox's public API wrappers.

  Arangox has 230 small, hand-maintained functions under `lib/arangox/api/`.
  Each function turns ordinary Elixir arguments into a request description
  and hands that description to `Arangox.API.Client`. A typo in one of these
  wrappers can compile successfully while sending the wrong method, path, or
  option to ArangoDB, so this module reads the wrapper source as Elixir syntax
  and checks the conventions that keep them uniform.

  These tests need no running ArangoDB server, Docker container, or downloaded
  API description. Plain `mix test` can therefore catch structural mistakes:

    * No operation file reaches the network except through the adapter.
    * Every path is built from literal segments and bare arguments, so no
      operation can assemble an address by string building.
    * Every operation has a bang twin, and that twin calls the matching
      non-bang function with the same arguments.
    * The operation count is pinned, so an accidental deletion or duplication
      turns the unit tier red.
    * A parameter the operation forces is never also offered as an option —
      the guard that keeps a caller from setting a flag the driver fixes.
    * Every local `fun/arity` reference in the docs resolves, so a bang
      twin's "See `twin/n`." line cannot go stale when a signature changes.

  `Arangox.API.ConformanceTest` answers a separate question. In the integration
  tier it asks a live ArangoDB server for its API description and compares
  Arangox's methods, addresses, query parameters, and request media against
  that description. This module checks how the wrappers are written; the
  conformance test checks whether the resulting surface matches the server.
  """

  use ExUnit.Case, async: true

  alias Arangox.TestSupport.ApiSurface

  @operation_count 230

  ## The adapter seam

  test "no operation file reaches the network except through the adapter" do
    for file <- ApiSurface.surface_files() do
      source = File.read!(file)

      assert source =~ "alias Arangox.API.Client",
             "#{file} does not alias the adapter"

      for forbidden <- [
            "Arangox.Client",
            "MintClient",
            "VelocyClient",
            "DBConnection",
            "Mint.",
            ":gen_tcp",
            ":ssl.",
            "Arangox.Connection",
            "Arangox.request"
          ] do
        refute source =~ forbidden,
               "#{file} references #{forbidden} — operation modules must only call the adapter"
      end
    end
  end

  ## Addresses

  # `ApiSurface.operations/1` raises on a segment that is neither a literal
  # string nor a bare argument, so reaching the assertion at all is most of
  # the proof. This states the invariant the raise defends.
  test "every path segment is a literal or a bare argument" do
    for op <- all_operations(), op.spec != nil, {kind, value} <- op.segments do
      assert kind in [:literal, :arg],
             "#{op.fun}/#{op.arity} has a path segment of an unreadable shape: #{inspect(value)}"

      if kind == :literal do
        refute value =~ ~r/[{}#?]/,
               "#{op.fun}/#{op.arity} has the literal segment #{inspect(value)}, which " <>
                 "carries a character that would alter the address"
      end
    end
  end

  ## Bang twins

  test "every operation has a bang twin of the same arity" do
    for {file, ops} <- operations_by_file() do
      plain = for o <- ops, not o.bang?, do: {o.fun, o.arity}

      bangs =
        for o <- ops,
            o.bang?,
            do:
              {o.fun |> Atom.to_string() |> String.trim_trailing("!") |> String.to_atom(),
               o.arity}

      assert Enum.sort(plain) == Enum.sort(bangs),
             "#{file}: every operation needs a bang twin taking the same arguments; " <>
               "missing #{inspect(Enum.sort(plain) -- Enum.sort(bangs))}"
    end
  end

  test "a bang form delegates instead of issuing its own request" do
    for op <- all_operations(), op.bang? do
      assert op.spec == nil,
             "#{op.fun}/#{op.arity} calls the adapter directly; it must delegate to its " <>
               "non-bang twin so the two cannot describe different requests"
    end
  end

  test "a bang form delegates to its matching twin with the same arguments" do
    file =
      Path.join(
        System.tmp_dir!(),
        "arangox-api-surface-#{System.unique_integer([:positive])}.ex"
      )

    on_exit(fn -> File.rm(file) end)

    for delegate <- ["remove(conn, id, opts)", "fetch(conn, opts, id)"] do
      File.write!(file, """
      defmodule BrokenBang do
        def fetch(conn, id, opts) do
          Client.request(conn,
            method: :get,
            segments: ["_api", "document", id],
            opts: opts
          )
        end

        def fetch!(conn, id, opts) do
          case #{delegate} do
            {:ok, body} -> body
            {:error, exception} -> raise exception
          end
        end
      end
      """)

      assert_raise RuntimeError,
                   ~r/fetch!\/3 must delegate to fetch\/3 with the same arguments/,
                   fn -> ApiSurface.operations(file) end
    end
  end

  ## Forced parameters

  # A forced parameter carries a value ArangoDB requires but a caller must not
  # choose. Offering the same name as an option would hand that choice back —
  # for `onlyget` that turns a read into a collection-wide replace.
  test "a forced query parameter is never also offered as an option" do
    for op <- all_operations(), op.spec != nil do
      forced = for {wire, _value} <- op.forced, do: wire
      overlap = forced -- (forced -- op.query)

      assert overlap == [],
             "#{op.fun}/#{op.arity} forces #{inspect(overlap)} and also offers it as an option"
    end
  end

  ## Documentation references

  # ExDoc renders an unresolvable local reference as dead text instead of a
  # link, and warns only when docs are built — which plain `mix test` never
  # does. The references live in prose, so nothing else re-derives them when
  # an operation's signature changes.
  test "every local function reference in the docs resolves to a defined arity" do
    for {file, ops} <- operations_by_file() do
      # `opts` carries a default, so an operation is also callable one below its
      # head arity — the arity its docs conventionally cite.
      callable =
        for op <- ops,
            arity <- [op.arity, op.arity - 1],
            into: MapSet.new(),
            do: {Atom.to_string(op.fun), arity}

      source = File.read!(file)

      for [whole, name, arity] <- Regex.scan(~r|`([a-z_][a-z0-9_]*!?)/(\d+)`|, source) do
        assert MapSet.member?(callable, {name, String.to_integer(arity)}),
               "#{file}: the docs reference #{whole}, which no operation there matches"
      end
    end
  end

  ## The operation count

  test "the surface holds exactly #{@operation_count} operations" do
    count = Enum.count(all_operations(), &(&1.spec != nil))

    assert count == @operation_count,
           "#{count} operations under #{ApiSurface.surface_dir()} — one was deleted, " <>
             "duplicated, or added. The conformance gate (integration tier) names which; " <>
             "move this count and its pin together, deliberately."
  end

  defp operations_by_file do
    for file <- ApiSurface.surface_files(), do: {file, ApiSurface.operations(file)}
  end

  defp all_operations do
    for {_file, ops} <- operations_by_file(), op <- ops, do: op
  end
end
