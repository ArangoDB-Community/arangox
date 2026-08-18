defmodule Arangox.Api.SurfaceTest do
  @moduledoc """
  Pure-source checks over the owned `Arangox.Api.*` surface.

  The operation modules under `lib/arangox/api/` are hand-maintained source:
  no generator stands behind them, so nothing re-derives them when an edit
  goes wrong. These checks read only the sources — no Docker, no document —
  so a broken edit fails plain `mix test` instead of surfacing in the
  integration leg. Conformance against the OpenAPI document the server
  itself serves lives in `Arangox.Api.ConformanceTest` (integration tier).

  Three invariants:

    * No operation file reaches the network except through the adapter —
      `@default_client Arangox.Api.Client` declared, transport modules absent.
    * Every operation URL is a usable address: no URL fragment, no literal
      `{param}` left un-interpolated.
    * The `client.request/1` call-site count is pinned, so an accidental
      deletion or duplication of an operation turns the unit tier red.
  """

  use ExUnit.Case, async: true

  alias Arangox.TestSupport.ApiSurface

  ## The adapter seam

  test "no operation file reaches the network except through the adapter" do
    for file <- ApiSurface.surface_files() do
      source = File.read!(file)

      assert source =~ "@default_client Arangox.Api.Client",
             "#{file} does not name the adapter as its client"

      for forbidden <- [
            "Arangox.Client",
            "MintClient",
            "VelocyClient",
            "DBConnection",
            "Mint.",
            ":gen_tcp",
            ":ssl.",
            "Arangox.Connection"
          ] do
        refute source =~ forbidden,
               "#{file} references #{forbidden} — operation modules must only call the adapter"
      end
    end
  end

  ## Usable addresses

  # The call-site count below and the conformance gate both compare operation
  # identities, so neither can see a URL that is wrong in itself — a leftover
  # fragment or a parameter never interpolated. These assert the emitted URL
  # is a usable address.
  test "no operation URL carries an un-interpolated path parameter" do
    for {file, url} <- surface_urls() do
      refute url =~ ~r/\{[a-zA-Z_][a-zA-Z0-9_]*\}/,
             "#{file} emits #{url}, which still holds a literal {param}"
    end
  end

  test "no operation URL carries a URL fragment" do
    for {file, url} <- surface_urls() do
      refute url =~ "#",
             "#{file} emits #{url}, whose fragment addresses nothing on the server"
    end
  end

  ## The call-site count

  # One call site per operation. The conformance gate pins the same number
  # against the live document (its @expected_operation_count) — the two move
  # together when an operation is added or removed.
  @call_site_count 243

  test "the surface holds exactly #{@call_site_count} client.request/1 call sites" do
    count =
      ApiSurface.surface_files()
      |> Enum.map(&length(ApiSurface.call_sites(&1)))
      |> Enum.sum()

    assert count == @call_site_count,
           "#{count} call sites under #{ApiSurface.surface_dir()} — an operation was deleted, " <>
             "duplicated, or added. The conformance gate (integration tier) names " <>
             "which; move this count and its pin together, deliberately."
  end

  ## Extraction

  # Every call site's `url:` value, reconstructed from the AST rather than
  # scanned out of the source text, so a url not written as one literal
  # string cannot slip past these checks unread. Interpolated segments render
  # as `<interpolated>`: the default `{name}` rendering would read as an
  # un-interpolated parameter, and the source spelling carries both of the
  # characters the assertions look for.
  defp surface_urls do
    for file <- ApiSurface.surface_files(),
        %{fun: fun, pairs: pairs} <- ApiSurface.call_sites(file) do
      url_ast = Keyword.get(pairs, :url)

      case ApiSurface.template(url_ast, fn _name -> "<interpolated>" end) do
        {:ok, url} ->
          {Path.basename(file), url}

        :error ->
          flunk(
            "#{file} #{fun}: url: #{Macro.to_string(url_ast)} is not a shape the " <>
              "template reconstruction reads — fix the site, or extend " <>
              "ApiSurface.template/2 deliberately"
          )
      end
    end
  end

  ## Extraction self-checks

  # No guarded def exists on the surface today, so the walker's handling of
  # one is only provable on synthetic input. A head-only match records a
  # guarded function as `:when` — the call site still counts, but every
  # check keyed on the function name misattributes it.
  describe "def extraction" do
    test "a guarded def yields its own name and its call sites" do
      ast =
        quote do
          defmodule Synthetic do
            def get_thing(name) when is_binary(name) do
              client.request(%{method: :get, url: "/_api/thing/#{name}"})
            end
          end
        end

      assert [{:get_thing, body}] = ApiSurface.function_defs(ast, "synthetic")
      assert [pairs] = ApiSurface.request_pairs(body)
      assert Keyword.fetch!(pairs, :method) == :get
      assert {:ok, "/_api/thing/{name}"} = ApiSurface.template(Keyword.fetch!(pairs, :url))
    end

    test "a bodyless head carries no call sites and does not raise" do
      ast =
        quote do
          defmodule Synthetic do
            def get_thing(name, opts \\ [])

            def get_thing(name, opts) do
              client.request(%{method: :get, url: "/_api/thing"})
            end
          end
        end

      assert [{:get_thing, _body}] = ApiSurface.function_defs(ast, "synthetic")
    end

    test "a def the walker cannot name raises, naming the source" do
      ast = {:def, [], [:unnameable, [do: :ok]]}

      assert_raise RuntimeError, ~r/synthetic\.ex: cannot extract a function name/, fn ->
        ApiSurface.function_defs(ast, "synthetic.ex")
      end
    end
  end
end
