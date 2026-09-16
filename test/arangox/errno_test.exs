defmodule Arangox.ErrnoTest do
  @moduledoc """
  The vendored `errorNum` table.

  Unit tier. The interesting assertions are the ones that re-derive the table
  from `priv/arangodb/errors-3.12.10.dat` and compare it with the committed
  generated module: that is what keeps `lib/arangox/errno.ex` honest without
  anyone having to remember to re-run the generator.
  """

  use ExUnit.Case, async: true

  alias Arangox.{Client, Errno}

  doctest Arangox.Errno, only: [reason: 1, error_num: 1]

  @dat Path.expand("../../priv/arangodb/errors-3.12.10.dat", __DIR__)
  @pinned_sha256 "64397475bfe2c988ca42389bed44a57679d8bbdcef0cd6dad6ad899999c9d13f"

  # The same parse the generator does, repeated independently here so a drifted
  # generated module fails a test rather than shipping.
  defp vendored_table do
    @dat
    |> File.read!()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "ERROR_"))
    |> Enum.map(fn line ->
      ["ERROR_" <> name, number | _rest] = String.split(line, ",", parts: 3)
      {String.to_integer(number), String.to_atom(String.downcase(name))}
    end)
  end

  defp table_atoms, do: Enum.map(vendored_table(), &elem(&1, 1))

  describe "the vendored table:" do
    test "is byte-identical to what was pinned" do
      actual = :crypto.hash(:sha256, File.read!(@dat)) |> Base.encode16(case: :lower)

      assert actual == @pinned_sha256, """
      priv/arangodb/errors-3.12.10.dat was modified. It must stay byte-identical
      to ArangoDB's lib/Basics/errors.dat at tag 3.12.10. If you are re-pinning to
      a new server tag, update priv/arangodb/README.md, gen_errno.exs and this
      test together. Errno.tag/0 is the repo's single version pin: the API
      conformance gate (test/arangox/api/conformance_test.exs) holds it to the
      live server's /_api/version response, so a re-pin also moves that gate's
      expectations.
      """
    end
  end

  describe "the compose pin:" do
    # The compose default is the driver's pin: the conformance gate
    # (integration tier) asserts Errno.tag/0 against the live server the
    # compose file starts, so a default that drifts from the tag only
    # surfaces once a stack is up. This test catches the drift with no
    # Docker involved.
    test "every docker-compose.yml ARANGO_VERSION default equals Errno.tag/0" do
      compose = Path.expand("../../docker-compose.yml", __DIR__)

      defaults =
        ~r/\$\{ARANGO_VERSION:-([^}]+)\}/
        |> Regex.scan(File.read!(compose), capture: :all_but_first)
        |> List.flatten()

      assert defaults != [],
             "docker-compose.yml no longer parameterises any image over ARANGO_VERSION"

      assert Enum.uniq(defaults) == [Errno.tag()], """
      docker-compose.yml defaults ARANGO_VERSION to #{inspect(Enum.uniq(defaults))},
      but Errno.tag() is #{inspect(Errno.tag())}. The compose default is the
      driver's pin — every occurrence must equal the tag. Follow "Updating to
      a new server tag" in AGENTS.md to move them together.
      """
    end
  end

  describe "the generated module matches the table:" do
    test "every vendored code resolves to its atom" do
      for {number, reason} <- vendored_table() do
        assert Errno.reason(number) == reason,
               "errorNum #{number} should be #{inspect(reason)}, got #{inspect(Errno.reason(number))}"
      end
    end

    test "every atom maps back to its number" do
      for {number, reason} <- vendored_table() do
        assert Errno.error_num(reason) == number
      end
    end

    # Deliberately no hardcoded total. The digest assertion above is what pins
    # the table; restating its size here only means a re-pin fails on an
    # arithmetic detail rather than on anything that could be wrong.
    test "the counts agree" do
      table = vendored_table()

      assert length(table) == Errno.count()
      assert length(Errno.reasons()) == Errno.count()
      assert Errno.count() > 0
    end

    test "reasons/0 is exactly the table's atoms, sorted" do
      expected = table_atoms() |> Enum.sort()

      assert Errno.reasons() == expected
    end
  end

  describe "the naming scheme:" do
    test "strips ERROR_ and downcases" do
      assert Errno.reason(0) == :no_error
      assert Errno.reason(1200) == :arango_conflict
      assert Errno.reason(1202) == :arango_document_not_found
      assert Errno.reason(503) == :http_service_unavailable
      assert Errno.reason(11) == :forbidden
    end

    test "is injective, so no two codes share an atom" do
      atoms = table_atoms()

      assert length(Enum.uniq(atoms)) == length(atoms)
    end

    test "produces plain snake_case atoms only" do
      for reason <- Errno.reasons() do
        assert Regex.match?(~r/^[a-z][a-z0-9_]*$/, Atom.to_string(reason)),
               "#{inspect(reason)} is not a plain snake_case identifier"
      end
    end
  end

  describe "unknown codes (the documented catch-all):" do
    test "a code absent from the table yields :unknown" do
      assert Errno.unknown() == :unknown
      assert Errno.reason(9_999_999) == :unknown
      assert Errno.reason(-1) == :unknown
    end

    test "a non-integer yields :unknown rather than raising" do
      for value <- [nil, "1202", :arango_conflict, 1.5, %{}, [], {:a}] do
        assert Errno.reason(value) == :unknown
      end
    end

    test ":unknown maps back to no number" do
      assert Errno.error_num(:unknown) == nil
      assert Errno.error_num(:not_a_reason_at_all) == nil
    end

    test ":unknown does not collide with any code in the table" do
      refute Errno.unknown() in Errno.reasons()
    end

    # `Arangox.Error` carries both kinds of reason in one field, so an overlap
    # would make `connection_lost?/1` fire on a perfectly ordinary server error.
    test "no code in the table collides with a connection-lost reason" do
      overlap =
        MapSet.intersection(
          MapSet.new(Errno.reasons()),
          MapSet.new(Client.connection_lost_reasons())
        )

      assert MapSet.size(overlap) == 0,
             "these reasons mean two different things: #{inspect(MapSet.to_list(overlap))}"
    end

    test "the catch-all is not a connection-lost reason either" do
      refute Client.connection_lost?(Errno.unknown())
    end
  end
end
