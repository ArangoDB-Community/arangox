defmodule Arangox.TestSupport.ApiSurface do
  @moduledoc """
  Reads the owned `Arangox.API.*` operation sources as data.

  Both gates over the surface — the pure-source `Arangox.API.SurfaceTest` and
  the live `Arangox.API.ConformanceTest` — need the same facts out of the same
  files: which operations exist, and what each one puts on the wire. Parsing
  happens here once, from the AST rather than from the source text, so an
  operation written in a shape these checks cannot read raises instead of
  being silently skipped.
  """

  @surface_dir "lib/arangox/api"

  @doc "The directory holding the operation sources, for failure messages."
  def surface_dir, do: @surface_dir

  @doc """
  Every operation source. The adapter is not one: it is the seam the
  operations call, not an operation.
  """
  def surface_files do
    @surface_dir
    |> Path.join("*.ex")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "client.ex"))
    |> Enum.sort()
  end

  @doc """
  Every operation in a file, as
  `%{fun:, arity:, bang?:, method:, segments:, forced:, query:, body?:}`.

  `segments` renders each entry as `{:literal, binary}` for a static path
  segment and `{:arg, atom}` for one interpolated from an argument — the
  distinction the surface gate needs to prove no path is assembled by string
  building.
  """
  def operations(file) do
    file
    |> File.read!()
    |> Code.string_to_quoted!()
    |> defs()
    |> Enum.map(&operation(&1, file))
    |> Enum.reject(&is_nil/1)
  end

  defp defs({:defmodule, _, [_, [do: {:__block__, _, body}]]}), do: body
  defp defs({:defmodule, _, [_, [do: single]]}), do: [single]
  defp defs(_other), do: []

  defp operation({:def, _, [head, [do: body]]}, file) do
    {name, args} = head_parts(head, file)

    case call_spec(body) do
      nil ->
        # A bang form delegates to its own non-bang twin rather than calling
        # the adapter again; it carries no wire facts of its own. The target
        # and forwarded arguments are still checked before recording it.
        if bang?(name) do
          validate_bang_delegate!(body, name, args, file)
        else
          raise "#{file}: #{name}/#{length(args)} does not call the adapter directly; " <>
                  "every operation reaches the network through Arangox.API.Client.request/2"
        end

        %{fun: name, arity: length(args), bang?: true, spec: nil}

      spec ->
        %{
          fun: name,
          arity: length(args),
          args: arg_names(args),
          bang?: bang?(name),
          method: Keyword.fetch!(spec, :method) |> literal!(file, name, :method),
          segments: segments(Keyword.fetch!(spec, :segments), file, name),
          forced: Keyword.get(spec, :forced, []) |> forced(),
          query: Keyword.get(spec, :query, []) |> query_names(),
          body?: Keyword.has_key?(spec, :body),
          spec: spec
        }
    end
  end

  defp operation(_other, _file), do: nil

  defp head_parts({:when, _, [inner, _guard]}, file), do: head_parts(inner, file)
  defp head_parts({name, _, args}, _file) when is_atom(name) and is_list(args), do: {name, args}
  defp head_parts({name, _, nil}, _file) when is_atom(name), do: {name, []}

  defp head_parts(other, file),
    do: raise("#{file}: cannot read a function head from #{inspect(other)}")

  defp bang?(name), do: name |> Atom.to_string() |> String.ends_with?("!")

  defp validate_bang_delegate!(
         {:case, _, [{delegate, _, delegate_args}, [do: _clauses]]},
         name,
         args,
         file
       )
       when is_atom(delegate) and is_list(delegate_args) do
    expected_delegate =
      name
      |> Atom.to_string()
      |> String.trim_trailing("!")

    expected_args = Enum.map(args, &argument_name!(&1, file, name))
    forwarded_args = Enum.map(delegate_args, &argument_name!(&1, file, name))

    if Atom.to_string(delegate) != expected_delegate or forwarded_args != expected_args do
      invalid_bang_delegate!(file, name, length(args), expected_delegate)
    end
  end

  defp validate_bang_delegate!(_body, name, args, file) do
    expected_delegate =
      name
      |> Atom.to_string()
      |> String.trim_trailing("!")

    invalid_bang_delegate!(file, name, length(args), expected_delegate)
  end

  defp argument_name!({:\\, _, [argument, _default]}, file, name),
    do: argument_name!(argument, file, name)

  defp argument_name!({argument, _, context}, _file, _name)
       when is_atom(argument) and is_atom(context),
       do: argument

  defp argument_name!(argument, file, name) do
    raise "#{file}: #{name} must use bare arguments, got: #{inspect(argument)}"
  end

  defp invalid_bang_delegate!(file, name, arity, expected_delegate) do
    raise "#{file}: #{name}/#{arity} must delegate to #{expected_delegate}/#{arity} " <>
            "with the same arguments"
  end

  # The positional arguments an operation takes, in order, without `conn` and
  # without the trailing `opts \\ []`.
  defp arg_names(args) do
    args
    |> Enum.reject(&match?({:\\, _, _}, &1))
    |> Enum.map(fn {name, _meta, _ctx} -> name end)
    |> Enum.reject(&(&1 == :conn))
  end

  # The adapter call, if this body is one. Anything else — a bang form's
  # `case`, a helper — has no spec.
  defp call_spec({{:., _, [{:__aliases__, _, [:Client]}, :request]}, _, [_conn, spec]})
       when is_list(spec),
       do: spec

  defp call_spec(_other), do: nil

  defp literal!(value, _file, _name, _key) when is_atom(value) or is_binary(value), do: value

  defp literal!(other, file, name, key),
    do: raise("#{file}: #{name}'s #{key} is not a literal: #{inspect(other)}")

  defp segments(list, file, name) when is_list(list) do
    Enum.map(list, fn
      literal when is_binary(literal) ->
        {:literal, literal}

      # A parameter that is itself a path keeps its separators; it still
      # occupies one slot in the address.
      {:path, {arg, _meta, ctx}} when is_atom(arg) and is_atom(ctx) ->
        {:arg, arg}

      {arg, _meta, context} when is_atom(arg) and is_atom(context) ->
        {:arg, arg}

      other ->
        raise(
          "#{file}: #{name} has a path segment that is neither a literal string " <>
            "nor a bare argument: #{inspect(other)}"
        )
    end)
  end

  defp segments(other, file, name),
    do: raise("#{file}: #{name}'s segments is not a list: #{inspect(other)}")

  # `[{"wireName", value}]` — the value is a literal for a fixed flag and an
  # argument for a required parameter lifted to a positional.
  defp forced(list) do
    Enum.map(list, fn
      {:{}, _, [wire, value]} -> {wire, forced_value(value)}
      {wire, value} -> {wire, forced_value(value)}
    end)
  end

  defp forced_value(v) when is_binary(v), do: {:literal, v}
  defp forced_value({arg, _meta, ctx}) when is_atom(arg) and is_atom(ctx), do: {:arg, arg}

  defp query_names(list), do: Enum.map(list, fn {_snake, wire} -> wire end)

  @doc """
  The wire path an operation addresses, with arguments rendered as the
  document writes them: `/_api/document/{collection}/{key}`.
  """
  def address(%{segments: segments}) do
    "/" <>
      Enum.map_join(segments, "/", fn
        {:literal, s} -> s
        {:arg, a} -> "{#{a}}"
      end)
  end
end
