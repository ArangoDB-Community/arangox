defmodule Arangox.TestSupport.ApiSurface do
  @moduledoc """
  Source extraction over the hand-maintained operation modules under
  `lib/arangox/api/`: the operation-file listing, the `client.request/1`
  call-site reader, and the URL-template reconstruction. Everything is read
  from the AST, never regex over source.

  Both source gates read through this module — `Arangox.Api.SurfaceTest`
  (unit tier) and `Arangox.Api.ConformanceTest` (integration tier) — so the
  tiers cannot disagree about what counts as an operation file or a call
  site; a private copy in either test can drift and quietly narrow what the
  other tier's invariants are checked against. Analysis of the extracted
  sites (URL checks, the call-site count, comparison against the server's
  document) belongs to the tests, not here.
  """

  import ExUnit.Assertions

  @surface_dir "lib/arangox/api"
  @adapter Path.join(@surface_dir, "client.ex")

  @doc "The directory holding the operation sources, for failure messages."
  def surface_dir, do: @surface_dir

  @doc """
  Every operation file: `#{@surface_dir}/*.ex` minus the adapter, which is
  the transport seam rather than an operation module.
  """
  def surface_files do
    files =
      @surface_dir
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.reject(&(&1 == @adapter))

    assert files != [], "no operation files found under #{@surface_dir}"
    files
  end

  @doc """
  Every `client.request/1` call site in one operation file, as
  `%{module:, fun:, body:, pairs:}`: the enclosing module and function, the
  function body (query extraction reads `query =` bindings from it), and the
  key-value pairs of the request map.
  """
  def call_sites(file) do
    {:ok, ast} = file |> File.read!() |> Code.string_to_quoted()

    {:defmodule, _, [{:__aliases__, _, module_parts}, _]} = ast
    module = Module.concat(module_parts)

    sites =
      for {name, body} <- function_defs(ast, file), pairs <- request_pairs(body) do
        %{module: module, fun: name, body: body, pairs: pairs}
      end

    assert sites != [], "#{file} contains no client.request/1 call site"
    sites
  end

  @doc """
  Every public function in a quoted expression, as `{name, body}` pairs.
  Recognizes plain and guarded heads — a guarded `def` wraps its head in a
  `:when` tuple, so a head-only match would record the function as `:when`.
  A bodyless head (a default-argument declaration) carries no call sites and
  is skipped. Any other `def` shape raises, naming `context`: a def this walk
  cannot read must never be skipped, because a skipped operation silently
  narrows every invariant checked over the extracted sites.
  """
  def function_defs(ast, context) do
    {_ast, defs} =
      Macro.prewalk(ast, [], fn
        {:def, _, [{:when, _, [{name, _, _} | _]}, [do: body]]} = node, acc
        when is_atom(name) ->
          {node, [{name, body} | acc]}

        {:def, _, [{name, _, _}, [do: body]]} = node, acc
        when is_atom(name) and name != :when ->
          {node, [{name, body} | acc]}

        {:def, _, [{:when, _, [{name, _, _} | _]}]} = node, acc when is_atom(name) ->
          {node, acc}

        {:def, _, [{name, _, _}]} = node, acc when is_atom(name) and name != :when ->
          {node, acc}

        {:def, _, _} = node, _acc ->
          raise "#{context}: cannot extract a function name from #{Macro.to_string(node)} — " <>
                  "extend Arangox.TestSupport.ApiSurface.function_defs/2 deliberately"

        node, acc ->
          {node, acc}
      end)

    defs
  end

  @doc """
  The argument pairs of every `client.request(%{...})` call in an AST. Takes
  any quoted expression, not only a whole file's AST, so a test can run the
  extraction over a synthetic function body.
  """
  def request_pairs(ast) do
    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:client, _, _}, :request]}, _, [{:%{}, _, pairs}]} = node, acc ->
          {node, [pairs | acc]}

        node, acc ->
          {node, acc}
      end)

    calls
  end

  @doc """
  The URL template of a call site's `url:` value, reconstructed from the AST:
  a binary literal passes through, and each interpolated segment must be a
  bare variable, rendered through `render` — `"{var}"` by default, the
  spelling the conformance gate compares against the document's path keys.
  Any other shape (a variable, a helper call, an interpolated expression)
  returns `:error`, so a caller must fail loudly rather than skip the site.
  """
  def template(url_ast, render \\ fn name -> "{#{name}}" end)

  def template(url, _render) when is_binary(url), do: {:ok, url}

  def template({:<<>>, _, parts}, render) do
    Enum.reduce_while(parts, {:ok, ""}, fn part, {:ok, acc} ->
      case template_part(part, render) do
        {:ok, segment} -> {:cont, {:ok, acc <> segment}}
        :error -> {:halt, :error}
      end
    end)
  end

  def template(_other, _render), do: :error

  defp template_part(literal, _render) when is_binary(literal), do: {:ok, literal}

  defp template_part(
         {:"::", _, [{{:., _, [Kernel, :to_string]}, _, [{var, _, context}]}, _type]},
         render
       )
       when is_atom(var) and is_atom(context),
       do: {:ok, render.(var)}

  defp template_part(_other, _render), do: :error
end
