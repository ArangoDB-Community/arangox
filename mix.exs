defmodule Arangox.MixProject do
  use Mix.Project

  @version "0.7.0"
  @description """
  ArangoDB 3.11 driver for Elixir with connection pooling, support for \
  VelocyStream, active failover, transactions and streamed cursors.
  """
  @source_url "https://github.com/ArangoDB-Community/arangox"
  @homepage_url "https://www.arangodb.com"

  def project do
    [
      app: :arangox,
      version: @version,
      elixir: ">= 1.7.0",
      start_permanent: Mix.env() == :prod,
      name: "Arangox",
      description: @description,
      source_url: @source_url,
      homepage_url: @homepage_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [extra_applications: [:logger] ++ extras(Mix.env())]
  end

  defp extras(:prod), do: []
  defp extras(_), do: [:gun]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:db_connection, "~> 2.6"},
      {:velocy, "~> 0.1", optional: true},
      {:gun, "~> 2.0", optional: true},
      {:mint, "~> 1.5", optional: true},
      {:jason, "> 0.0.0", optional: true},
      {:ex_doc, "> 0.0.0", only: :dev, runtime: false},
    ]
  end
end
