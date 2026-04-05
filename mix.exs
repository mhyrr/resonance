defmodule Resonance.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/mhyrr/resonance"

  def project do
    [
      app: :resonance,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "Resonance",
      description: "Generative analysis surfaces for Phoenix LiveView",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: ["test.all": :test]
    ]
  end

  def application do
    [
      mod: {Resonance.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp aliases do
    [
      "test.all": [
        "test",
        "cmd --cd example/resonance_demo mix test",
        "cmd --cd example/finance_demo mix test"
      ],
      "build.all": [
        "compile",
        "cmd --cd example/resonance_demo mix compile",
        "cmd --cd example/finance_demo mix compile"
      ],
      setup: [
        "deps.get",
        "cmd --cd example/resonance_demo mix setup",
        "cmd --cd example/finance_demo mix setup"
      ]
    ]
  end

  defp docs do
    [
      main: "Resonance",
      extras: ["README.md"],
      groups_for_modules: [
        Behaviours: [
          Resonance.Primitive,
          Resonance.Resolver,
          Resonance.Presenter,
          Resonance.LLM.Provider
        ],
        Primitives: ~r/Resonance\.Primitives\./,
        Components: ~r/Resonance\.Components\./,
        LLM: ~r/Resonance\.LLM\./
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
