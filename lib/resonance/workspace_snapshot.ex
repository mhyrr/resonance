defmodule Resonance.WorkspaceSnapshot do
  @moduledoc """
  Serializable value object for revisitable workspaces.

  A snapshot contains a validated workspace plan, enough resolved section
  metadata to preserve identity across reruns, the original prompt, and a
  deterministic plan fingerprint. Persistence remains app-owned: Resonance
  only converts snapshots to/from maps and reruns stored tool-call sources.
  """

  alias Resonance.{Pipeline, Renderable, WorkspaceCompiler, WorkspacePlan}
  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan.Section

  @version 1

  @type section_metadata :: %{
          required(:id) => String.t(),
          required(:role) => atom(),
          required(:pattern) => atom(),
          required(:renderable_id) => String.t(),
          required(:renderable_type) => String.t(),
          required(:status) => atom()
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          fingerprint: String.t(),
          original_prompt: String.t() | nil,
          created_at: DateTime.t(),
          plan: WorkspacePlan.t(),
          sections: [section_metadata()]
        }

  defstruct version: @version,
            fingerprint: nil,
            original_prompt: nil,
            created_at: nil,
            plan: nil,
            sections: []

  @doc """
  Build a snapshot from a compiled workspace.
  """
  @spec from_compiled(WorkspaceCompiler.compiled_workspace(), keyword()) :: t()
  def from_compiled(%{plan: %WorkspacePlan{} = plan, sections: sections}, opts \\ []) do
    %__MODULE__{
      version: @version,
      fingerprint: fingerprint(plan),
      original_prompt: Keyword.get(opts, :original_prompt),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      plan: plan,
      sections: Enum.map(sections, &section_metadata/1)
    }
  end

  @doc """
  Deterministically fingerprint a plan's serializable representation.
  """
  @spec fingerprint(WorkspacePlan.t()) :: String.t()
  def fingerprint(%WorkspacePlan{} = plan) do
    plan
    |> plan_to_map()
    |> Map.delete("identity")
    |> canonical_json()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Convert a snapshot to a JSON-safe map.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = snapshot) do
    %{
      "version" => snapshot.version,
      "fingerprint" => snapshot.fingerprint,
      "original_prompt" => snapshot.original_prompt,
      "created_at" => DateTime.to_iso8601(snapshot.created_at),
      "plan" => plan_to_map(snapshot.plan),
      "sections" => Enum.map(snapshot.sections, &json_safe/1)
    }
  end

  @doc """
  Rebuild a snapshot from `to_map/1` output.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    with {:ok, plan} <- plan_from_map(fetch(map, "plan")),
         {:ok, created_at} <- parse_created_at(fetch(map, "created_at")),
         {:ok, sections} <- sections_metadata_from_map(fetch(map, "sections")) do
      snapshot = %__MODULE__{
        version: fetch(map, "version") || @version,
        fingerprint: fetch(map, "fingerprint") || fingerprint(plan),
        original_prompt: fetch(map, "original_prompt"),
        created_at: created_at,
        plan: plan,
        sections: sections
      }

      {:ok, snapshot}
    end
  end

  @doc """
  Encode a snapshot as JSON.
  """
  @spec to_json(t()) :: {:ok, String.t()} | {:error, term()}
  def to_json(%__MODULE__{} = snapshot), do: Jason.encode(to_map(snapshot))

  @doc """
  Decode a snapshot from JSON.
  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json) when is_binary(json) do
    with {:ok, map} <- Jason.decode(json),
         {:ok, snapshot} <- from_map(map) do
      {:ok, snapshot}
    end
  end

  @doc """
  Rerun the snapshot through stored section tool calls.

  Events are delivered asynchronously, matching `Resonance.Pipeline.resolve/3`.
  Component-ready events are rewritten with stable workspace renderable IDs.
  """
  @spec rerun(t(), map(), Pipeline.sink()) :: :ok
  def rerun(%__MODULE__{plan: %WorkspacePlan{} = plan} = snapshot, context, sink)
      when is_map(context) and is_function(sink, 1) do
    tool_calls = section_tool_calls(plan.sections)
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Pipeline.resolve(tool_calls, context, fn
      {:component_ready, %Renderable{} = renderable} ->
        index = Agent.get_and_update(counter, fn current -> {current, current + 1} end)
        section = Enum.at(plan.sections, index)

        rewritten = %{
          renderable
          | id: WorkspaceCompiler.stable_renderable_id(plan, section, renderable)
        }

        sink.({:component_ready, rewritten})

      :done ->
        Agent.stop(counter)
        sink.(:done)

      {:error, reason} ->
        Agent.stop(counter)
        sink.({:error, reason})

      event ->
        sink.(event)
    end)

    _ = snapshot
    :ok
  end

  @doc false
  @spec plan_to_map(WorkspacePlan.t()) :: map()
  def plan_to_map(%WorkspacePlan{} = plan) do
    %{
      "goal" => atom_to_string(plan.goal),
      "title" => plan.title,
      "layout" => atom_to_string(plan.layout),
      "sections" => Enum.map(plan.sections, &section_to_map/1),
      "refinements" => json_safe(plan.refinements),
      "identity" => json_safe(plan.identity)
    }
  end

  defp section_to_map(%Section{} = section) do
    %{
      "id" => section.id,
      "title" => section.title,
      "role" => atom_to_string(section.role),
      "pattern" => atom_to_string(section.pattern),
      "source" => source_to_map(section.source),
      "interactions" => Enum.map(section.interactions, &atom_to_string/1),
      "depends_on" => section.depends_on,
      "metadata" => json_safe(section.metadata)
    }
  end

  defp source_to_map({:tool_call, %ToolCall{} = tool_call}) do
    %{
      "type" => "tool_call",
      "tool_call" => %{
        "id" => tool_call.id,
        "name" => tool_call.name,
        "arguments" => json_safe(tool_call.arguments)
      }
    }
  end

  defp plan_from_map(map) when is_map(map) do
    with {:ok, goal} <- existing_atom(fetch(map, "goal")),
         {:ok, layout} <- allowed_atom(fetch(map, "layout"), layout_atoms()),
         {:ok, sections} <- sections_from_map(fetch(map, "sections")) do
      plan = %WorkspacePlan{
        goal: goal,
        title: fetch(map, "title"),
        layout: layout,
        sections: sections,
        refinements: fetch(map, "refinements") || [],
        identity: fetch(map, "identity") || %{}
      }

      WorkspacePlan.validate(plan)
    end
  end

  defp plan_from_map(other), do: {:error, {:invalid_snapshot_plan, other}}

  defp sections_from_map(sections) when is_list(sections) do
    sections
    |> Enum.reduce_while({:ok, []}, fn section_map, {:ok, acc} ->
      case section_from_map(section_map) do
        {:ok, section} -> {:cont, {:ok, [section | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sections} -> {:ok, Enum.reverse(sections)}
      error -> error
    end
  end

  defp sections_from_map(other), do: {:error, {:invalid_snapshot_sections, other}}

  defp section_from_map(map) when is_map(map) do
    with {:ok, role} <- allowed_atom(fetch(map, "role"), section_role_atoms()),
         {:ok, pattern} <- allowed_atom(fetch(map, "pattern"), section_pattern_atoms()),
         {:ok, source} <- source_from_map(fetch(map, "source")) do
      {:ok,
       %Section{
         id: fetch(map, "id"),
         title: fetch(map, "title"),
         role: role,
         pattern: pattern,
         source: source,
         interactions: interaction_atoms(fetch(map, "interactions") || []),
         depends_on: fetch(map, "depends_on") || [],
         metadata: fetch(map, "metadata") || %{}
       }}
    end
  end

  defp section_from_map(other), do: {:error, {:invalid_snapshot_section, other}}

  defp source_from_map(%{"type" => "tool_call", "tool_call" => tool_call})
       when is_map(tool_call) do
    {:ok,
     {:tool_call,
      %ToolCall{
        id: fetch(tool_call, "id"),
        name: fetch(tool_call, "name"),
        arguments: fetch(tool_call, "arguments") || %{}
      }}}
  end

  defp source_from_map(other), do: {:error, {:invalid_snapshot_source, other}}

  defp section_tool_calls(sections) do
    Enum.map(sections, fn %Section{source: {:tool_call, %ToolCall{} = tool_call}} -> tool_call end)
  end

  defp section_metadata(%{id: id, role: role, pattern: pattern, renderable: renderable}) do
    %{
      id: id,
      role: role,
      pattern: pattern,
      renderable_id: renderable.id,
      renderable_type: renderable.type,
      status: renderable.status
    }
  end

  defp sections_metadata_from_map(sections) when is_list(sections) do
    {:ok,
     Enum.map(sections, fn section ->
       %{
         id: fetch(section, "id"),
         role: safe_existing_atom(fetch(section, "role")),
         pattern: safe_existing_atom(fetch(section, "pattern")),
         renderable_id: fetch(section, "renderable_id"),
         renderable_type: fetch(section, "renderable_type"),
         status: safe_existing_atom(fetch(section, "status"))
       }
     end)}
  end

  defp sections_metadata_from_map(_), do: {:ok, []}

  defp parse_created_at(nil), do: {:ok, DateTime.utc_now()}
  defp parse_created_at(%DateTime{} = datetime), do: {:ok, datetime}

  defp parse_created_at(value) when is_binary(value),
    do: DateTime.from_iso8601(value) |> strip_offset()

  defp parse_created_at(other), do: {:error, {:invalid_created_at, other}}

  defp strip_offset({:ok, datetime, _offset}), do: {:ok, datetime}
  defp strip_offset(error), do: error

  defp layout_atoms, do: [:stack, :dashboard_grid, :overview_with_detail]
  defp section_role_atoms, do: [:summary, :primary, :focus_list, :supporting_context, :detail]

  defp section_pattern_atoms do
    [
      :prose_summary,
      :metric_strip,
      :entity_list,
      :trend_panel,
      :summary_panel,
      :comparison_panel,
      :data_table
    ]
  end

  defp interaction_atoms(values) when is_list(values), do: Enum.map(values, &safe_existing_atom/1)

  defp allowed_atom(value, allowed) when is_binary(value) do
    atom = safe_existing_atom(value)
    if atom in allowed, do: {:ok, atom}, else: {:error, {:unsupported_atom, value}}
  end

  defp allowed_atom(value, allowed) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: {:error, {:unsupported_atom, value}}
  end

  defp allowed_atom(value, _allowed), do: {:error, {:invalid_atom, value}}

  defp existing_atom(value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:ok, value}
  end

  defp existing_atom(value) when is_atom(value) and not is_nil(value), do: {:ok, value}
  defp existing_atom(value), do: {:error, {:invalid_atom, value}}

  defp safe_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> :unknown
  end

  defp safe_existing_atom(value) when is_atom(value), do: value

  defp atom_to_string(nil), do: nil
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_to_string(value), do: to_string(value)

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp fetch(_map, _key), do: nil

  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(value) when is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: atom_to_string(value)
  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)

  defp json_safe(value) when is_map(value) do
    value
    |> Enum.map(fn {key, val} -> {to_string(key), json_safe(val)} end)
    |> Map.new()
  end

  defp json_safe(value), do: value

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.map(fn {key, val} -> {to_string(key), canonical_json(val)} end)
      |> Enum.sort_by(fn {key, _val} -> key end)

    "{" <>
      Enum.map_join(entries, ",", fn {key, val} -> Jason.encode!(key) <> ":" <> val end) <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)
end
