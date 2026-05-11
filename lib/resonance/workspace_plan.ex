defmodule Resonance.WorkspacePlan do
  @moduledoc """
  Typed plan for a generated workspace.

  `WorkspacePlan` is the v3 middle layer above LLM tool calls and below
  rendered Phoenix surfaces. Phase 1 keeps the contract intentionally small:
  hand-written plans, known layouts/roles/pattern names, and section sources
  that are stored `Resonance.LLM.ToolCall` structs.

  The plan does not resolve data or render UI. It only describes what should
  appear. `Resonance.WorkspacePlan.Validation` checks that description before
  any resolver or presenter runs.
  """

  alias Resonance.Patterns
  alias Resonance.WorkspacePlan.{Section, Validation}

  @type goal :: atom() | String.t()
  @type layout :: :stack | :dashboard_grid | :overview_with_detail
  @type identity :: %{optional(atom()) => term()}

  @type t :: %__MODULE__{
          goal: goal() | nil,
          title: String.t() | nil,
          layout: layout() | atom() | nil,
          sections: [Section.t()],
          refinements: [map()],
          identity: identity()
        }

  defstruct goal: nil,
            title: nil,
            layout: :stack,
            sections: [],
            refinements: [],
            identity: %{kind: :ephemeral, saveable: true}

  @doc """
  Validate a workspace plan.

  Returns `{:ok, plan}` or `{:error, {:validation_failed, errors}}`, where each
  error has `:path`, `:code`, `:message`, and optional `:details`.
  """
  @spec validate(t(), keyword()) ::
          {:ok, t()} | {:error, {:validation_failed, [Validation.error()]}}
  def validate(%__MODULE__{} = plan, opts \\ []), do: Validation.validate(plan, opts)

  @doc """
  Build a workspace plan from a JSON-safe map.

  Provider output is untrusted JSON. Known enum strings are converted to known
  atoms. Unknown strings remain strings so validation can reject them without
  creating atoms dynamically.
  """
  @spec from_map(map(), keyword()) ::
          {:ok, t()} | {:error, {:validation_failed, [Validation.error()]}}
  def from_map(map, opts \\ [])

  def from_map(map, opts) when is_map(map) do
    pattern_manifest = Patterns.from_opts(opts)

    plan = %__MODULE__{
      goal: fetch(map, "goal"),
      title: fetch(map, "title"),
      layout: known_atom(fetch(map, "layout"), Validation.allowed_layouts()),
      sections: sections_from_map(fetch(map, "sections"), pattern_manifest),
      refinements: fetch(map, "refinements") || [],
      identity: fetch(map, "identity") || %{}
    }

    validate(plan, patterns: pattern_manifest)
  end

  def from_map(other, _opts) do
    {:error,
     {:validation_failed,
      [
        %{
          path: [],
          code: :invalid_plan,
          message: "workspace plan must be a map",
          details: %{received: other}
        }
      ]}}
  end

  defp sections_from_map(sections, pattern_manifest) when is_list(sections) do
    Enum.map(sections, &section_from_map(&1, pattern_manifest))
  end

  defp sections_from_map(other, _pattern_manifest), do: other

  defp section_from_map(map, pattern_manifest) when is_map(map) do
    %Section{
      id: fetch(map, "id"),
      title: fetch(map, "title"),
      role: known_atom(fetch(map, "role"), Validation.allowed_roles()),
      pattern: known_atom(fetch(map, "pattern"), Patterns.names(pattern_manifest)),
      source: source_from_map(fetch(map, "source")),
      interactions: known_atoms(fetch(map, "interactions") || [], known_interactions()),
      depends_on: fetch(map, "depends_on") || [],
      metadata: fetch(map, "metadata") || %{}
    }
  end

  defp section_from_map(other, _pattern_manifest), do: other

  defp source_from_map(%{"type" => "tool_call", "tool_call" => tool_call})
       when is_map(tool_call) do
    {:tool_call, tool_call_from_map(tool_call)}
  end

  defp source_from_map(%{type: "tool_call", tool_call: tool_call}) when is_map(tool_call) do
    {:tool_call, tool_call_from_map(tool_call)}
  end

  defp source_from_map(%{"tool_call" => tool_call}) when is_map(tool_call) do
    {:tool_call, tool_call_from_map(tool_call)}
  end

  defp source_from_map(%{tool_call: tool_call}) when is_map(tool_call) do
    {:tool_call, tool_call_from_map(tool_call)}
  end

  defp source_from_map(source), do: source

  defp tool_call_from_map(map) do
    %Resonance.LLM.ToolCall{
      id: fetch(map, "id"),
      name: fetch(map, "name"),
      arguments: fetch(map, "arguments") || %{}
    }
  end

  defp known_atoms(values, allowed) when is_list(values) do
    Enum.map(values, &known_atom(&1, allowed))
  end

  defp known_atoms(values, _allowed), do: values

  defp known_atom(value, allowed) when is_binary(value) do
    Enum.find(allowed, value, &(Atom.to_string(&1) == value))
  end

  defp known_atom(value, allowed) when is_atom(value) do
    if value in allowed, do: value, else: value
  end

  defp known_atom(value, _allowed), do: value

  defp known_interactions, do: [:filter, :inspect, :refine]

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, safe_existing_atom(key))
  end

  defp fetch(_map, _key), do: nil

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
