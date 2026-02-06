defmodule WhoThere.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kittyfromouterspace/who_there"

  def project do
    [
      app: :who_there,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex package
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,

      # Docs
      name: "WhoThere",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Privacy-focused analytics for Phoenix applications using Ash Framework.
    Tracks page views, sessions, and events without cookies using fingerprinting.
    """
  end

  defp package do
    [
      name: "who_there",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "INTEGRATION_GUIDE.md",
        "CHANGELOG.md"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WhoThere, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_postgres, "~> 2.0"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:igniter, "~> 0.3"},
      {:plug, "~> 1.15"},
      {:telemetry, "~> 1.2"},
      {:jason, "~> 1.4"},
      {:picosat_elixir, "~> 0.2"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
