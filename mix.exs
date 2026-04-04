defmodule Resonance.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/mhyrr/resonance"

  def project do
    [
      app: :resonance,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "Resonance",
      description: "Generative analysis surfaces for Phoenix LiveView",
      source_url: @source_url,
      package: package()
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.all": ["test", "cmd --cd example/resonance_demo mix test"],
      "build.all": ["compile", "cmd --cd example/resonance_demo mix compile"],
      setup: ["deps.get", "cmd --cd example/resonance_demo mix setup"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
