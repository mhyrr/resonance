defmodule Resonance.Registry do
  @moduledoc """
  Maps semantic primitive names to their implementing modules.

  Started as part of the Resonance supervision tree. Default primitives
  are registered at startup; apps can register custom primitives at runtime.
  """

  use Agent

  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, name: opts[:name] || __MODULE__)
  end

  @doc """
  Register a primitive module under a name.
  """
  def register(name, module, server \\ __MODULE__) do
    Agent.update(server, &Map.put(&1, name, module))
  end

  @doc """
  Look up a primitive module by name.
  """
  def get(name, server \\ __MODULE__) do
    Agent.get(server, &Map.get(&1, name))
  end

  @doc """
  Return all registered tool schemas for passing to the LLM.
  """
  def all_schemas(server \\ __MODULE__) do
    Agent.get(server, fn registry ->
      Enum.map(registry, fn {_name, module} -> module.intent_schema() end)
    end)
  end

  @doc """
  List all registered primitive names.
  """
  def list(server \\ __MODULE__) do
    Agent.get(server, &Map.keys/1)
  end

  @doc """
  Register the default Resonance primitives.
  """
  def register_defaults(server \\ __MODULE__) do
    defaults = %{
      "compare_over_time" => Resonance.Primitives.CompareOverTime,
      "rank_entities" => Resonance.Primitives.RankEntities,
      "show_distribution" => Resonance.Primitives.ShowDistribution,
      "summarize_findings" => Resonance.Primitives.SummarizeFindings,
      "segment_population" => Resonance.Primitives.SegmentPopulation
    }

    Enum.each(defaults, fn {name, module} ->
      register(name, module, server)
    end)
  end
end
