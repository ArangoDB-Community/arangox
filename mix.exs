defmodule Arangox.MixProject do
  use Mix.Project

  # OTP 26 is where `:ssl` began verifying peers by default. This driver holds
  # no TLS opinion of its own — options reach the transport as written, and the
  # transport's defaults are what apply — so on an older release a TLS pool
  # would silently accept any certificate presented to it. Refusing to build is
  # the only way that fact does not become a quiet one. OTP 24 and 25 are both
  # past end of life.
  @minimum_otp 26

  if String.to_integer(System.otp_release()) < @minimum_otp do
    Mix.raise("""
    arangox requires OTP #{@minimum_otp} or later, and this is OTP #{System.otp_release()}.

    Before OTP #{@minimum_otp}, `:ssl` defaulted to `verify: :verify_none`. Since this driver
    passes transport options through rather than supplying its own, a TLS
    connection on this release would accept any certificate without saying so.
    """)
  end

  @version "0.8.0"
  @description """
  An implementation of DBConnection for ArangoDB. Velocy and JSON over HTTP/2,
  the new AQL plan cache, resource APIs covering ArangoDB's HTTP surface,
  and pools, transactions and cursors via DBConnection. VelocyStream and Active Failover
  remain for 3.11.
  """
  @source_url "https://github.com/ArangoDB-Community/arangox"
  @homepage_url "https://www.arangodb.com"

  def project do
    [
      app: :arangox,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Arangox",
      description: @description,
      source_url: @source_url,
      homepage_url: @homepage_url,
      package: package(),
      docs: docs(),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer()
    ]
  end

  # Dialyzer runs in CI. The ignore file carries one entry, with the reason
  # written out; see `.dialyzer_ignore.exs`.
  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: ["test.integration": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    ["test.integration": "test --only integration"]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # Without this list the tarball ships priv/ — the vendored error table
      # and its generator script, which only regeneration of
      # `lib/arangox/errno.ex` needs. Nothing under priv/ is read at runtime.
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      # The README links to both, so both must be in the docs output or the
      # links resolve to nothing on HexDocs. They already ship in the
      # tarball through `package/0`.
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.10"},
      {:velocy, "~> 0.2", optional: true},
      {:gun, "~> 2.0", optional: true},
      {:mint, "~> 1.9", optional: true},
      {:jason, "~> 1.4", optional: true},
      {:plug, "~> 1.16", only: [:test]},
      {:plug_cowboy, "~> 2.7", only: [:test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
