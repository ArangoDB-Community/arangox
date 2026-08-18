# Measures what the `:content_type` pool option changes: codec encode and
# decode cost, and encoded size, on representative payloads. The
# README's codec table is generated from this output. Run with:
#
#     mix run bench/content_type.exs
#
# Requires :velocy, which is a dev/test dependency of this repo.
#
# This is a codec benchmark, not a wire benchmark: request latency against a
# live server is dominated by the server and the network, which is exactly why
# a measured codec result is reported instead of an asserted end-to-end
# benefit.

defmodule Bench.ContentType do
  @rounds 5

  def run do
    ensure_velocy!()

    payloads = [
      {"1 document", document(1), 10_000},
      {"100-document batch", batch(100), 1_000},
      {"1000-document batch", batch(1_000), 100}
    ]

    IO.puts("Rounds: #{@rounds}, median reported. #{system_line()}\n")

    IO.puts("| Payload | Codec | Encode | Decode | Encoded size |")
    IO.puts("| --- | --- | --- | --- | --- |")

    for {label, payload, iterations} <- payloads do
      json = Jason.encode!(payload)
      vpack = VelocyPack.encode!(payload)

      row(label, "JSON", iterations,
        encode: fn -> Jason.encode!(payload) end,
        decode: fn -> Jason.decode!(json) end,
        size: byte_size(json)
      )

      row(label, "VelocyPack", iterations,
        encode: fn -> VelocyPack.encode!(payload) end,
        decode: fn -> VelocyPack.decode!(vpack) end,
        size: byte_size(vpack)
      )
    end
  end

  defp row(label, codec, iterations, encode: encode, decode: decode, size: size) do
    IO.puts(
      "| #{label} | #{codec} | #{measure(encode, iterations)} | " <>
        "#{measure(decode, iterations)} | #{format_bytes(size)} |"
    )
  end

  # Median over rounds of (wall time / iterations). Each round times the whole
  # loop once rather than each call, so the timer's own cost stays out of the
  # per-call figure.
  defp measure(fun, iterations) do
    # Warmup round, discarded.
    loop(fun, iterations)

    1..@rounds
    |> Enum.map(fn _ ->
      {micros, :ok} = :timer.tc(fn -> loop(fun, iterations) end)
      micros / iterations
    end)
    |> median()
    |> format_micros()
  end

  defp loop(_fun, 0), do: :ok

  defp loop(fun, n) do
    fun.()
    loop(fun, n - 1)
  end

  defp median(values) do
    sorted = Enum.sort(values)
    Enum.at(sorted, div(length(sorted), 2))
  end

  defp format_micros(us) when us < 1_000, do: "#{Float.round(us / 1, 2)} µs"
  defp format_micros(us), do: "#{Float.round(us / 1_000, 2)} ms"

  defp format_bytes(b) when b < 1_024, do: "#{b} B"
  defp format_bytes(b), do: "#{Float.round(b / 1_024, 1)} KiB"

  # A cursor-row-shaped document: system attributes plus a mix of the scalar
  # and container types real documents carry.
  defp document(i) do
    %{
      "_key" => "user#{i}",
      "_id" => "users/user#{i}",
      "_rev" => "_hV2oH#{i}",
      "name" => "User Number #{i}",
      "email" => "user#{i}@example.com",
      "active" => rem(i, 2) == 0,
      "score" => i * 1.5,
      "visits" => i * 17,
      "tags" => ["alpha", "beta", "gamma"],
      "address" => %{
        "street" => "#{i} Example Street",
        "city" => "Exampleton",
        "zip" => "10#{rem(i, 1000)}"
      }
    }
  end

  defp batch(n), do: Enum.map(1..n, &document/1)

  defp ensure_velocy! do
    unless Code.ensure_loaded?(VelocyPack) do
      IO.puts(:stderr, "the :velocy dependency is required; run in this repo via mix run")
      System.halt(1)
    end
  end

  defp system_line do
    otp = :erlang.system_info(:otp_release) |> List.to_string()

    "Elixir #{System.version()} / OTP #{otp}, " <>
      "#{:erlang.system_info(:schedulers_online)} schedulers."
  end
end

Bench.ContentType.run()
