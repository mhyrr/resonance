defmodule Resonance.WorkspaceContext do
  @moduledoc """
  Planner-facing context for follow-up workspace prompts.

  A workspace context is a compact description of the current workspace: the
  original prompt, the sections that exist, their stored query sources, and
  optionally the latest result summaries. It is pure data. LiveView, snapshots,
  and consuming apps decide when to persist or pass it back to the planner.
  """

  alias Resonance.{Result, WorkspaceCompiler, WorkspacePlan, WorkspaceSnapshot}
  alias Resonance.LLM.ToolCall
  alias Resonance.QueryIntent
  alias Resonance.Renderable
  alias Resonance.WorkspacePlan.Section

  @type section_context :: %{
          required(:id) => String.t() | nil,
          required(:title) => String.t() | nil,
          required(:role) => String.t() | nil,
          required(:pattern) => String.t() | nil,
          required(:source) => map() | nil,
          optional(:renderable) => map(),
          optional(:result) => map()
        }

  @type t :: %__MODULE__{
          original_prompt: String.t() | nil,
          fingerprint: String.t() | nil,
          goal: String.t() | nil,
          title: String.t() | nil,
          layout: String.t() | nil,
          identity: map(),
          sections: [section_context()]
        }

  defstruct original_prompt: nil,
            fingerprint: nil,
            goal: nil,
            title: nil,
            layout: nil,
            identity: %{},
            sections: []

  @doc """
  Extract workspace context from a Resonance context map.

  Accepted keys are `:workspace_context`, `"workspace_context"`,
  `:workspace_snapshot`, and `"workspace_snapshot"`.
  """
  @spec from_context(map() | nil) :: t() | nil
  def from_context(context) when is_map(context) do
    context
    |> fetch_context_value()
    |> normalize()
  end

  def from_context(_context), do: nil

  @doc "Build context from a workspace plan."
  @spec from_plan(WorkspacePlan.t(), keyword()) :: t()
  def from_plan(%WorkspacePlan{} = plan, opts \\ []) do
    %__MODULE__{
      original_prompt: Keyword.get(opts, :original_prompt),
      fingerprint: Keyword.get(opts, :fingerprint) || WorkspaceSnapshot.fingerprint(plan),
      goal: atom_to_string(plan.goal),
      title: plan.title,
      layout: atom_to_string(plan.layout),
      identity: json_safe(plan.identity),
      sections: Enum.map(plan.sections, &section_from_plan(&1, nil, nil))
    }
  end

  @doc "Build context from a compiled workspace."
  @spec from_compiled(WorkspaceCompiler.compiled_workspace(), keyword()) :: t()
  def from_compiled(%{plan: %WorkspacePlan{} = plan, sections: compiled_sections}, opts \\ []) do
    compiled_by_id =
      Map.new(compiled_sections, fn compiled_section ->
        {compiled_section.id, compiled_section}
      end)

    %__MODULE__{
      original_prompt: Keyword.get(opts, :original_prompt),
      fingerprint: Keyword.get(opts, :fingerprint) || WorkspaceSnapshot.fingerprint(plan),
      goal: atom_to_string(plan.goal),
      title: plan.title,
      layout: atom_to_string(plan.layout),
      identity: json_safe(plan.identity),
      sections:
        Enum.map(plan.sections, fn section ->
          section_from_plan(section, Map.get(compiled_by_id, section.id), nil)
        end)
    }
  end

  @doc "Build context from a workspace snapshot."
  @spec from_snapshot(WorkspaceSnapshot.t()) :: t()
  def from_snapshot(%WorkspaceSnapshot{} = snapshot) do
    metadata_by_id = Map.new(snapshot.sections, &{&1.id, &1})

    %__MODULE__{
      original_prompt: snapshot.original_prompt,
      fingerprint: snapshot.fingerprint || WorkspaceSnapshot.fingerprint(snapshot.plan),
      goal: atom_to_string(snapshot.plan.goal),
      title: snapshot.plan.title,
      layout: atom_to_string(snapshot.plan.layout),
      identity: json_safe(snapshot.plan.identity),
      sections:
        Enum.map(snapshot.plan.sections, fn section ->
          section_from_plan(section, nil, Map.get(metadata_by_id, section.id))
        end)
    }
  end

  @doc "Convert context to a JSON-safe map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    %{
      "original_prompt" => context.original_prompt,
      "fingerprint" => context.fingerprint,
      "goal" => context.goal,
      "title" => context.title,
      "layout" => context.layout,
      "identity" => json_safe(context.identity),
      "sections" => json_safe(context.sections)
    }
  end

  @doc """
  Render a compact prompt block for follow-up planning.
  """
  @spec format_for_prompt(t() | nil) :: String.t()
  def format_for_prompt(nil), do: ""

  def format_for_prompt(%__MODULE__{} = context) do
    """
    Current workspace context:
    original_prompt=#{inspect(context.original_prompt)}
    workspace=#{inspect(context.title)} goal=#{context.goal} layout=#{context.layout} fingerprint=#{context.fingerprint}
    sections:
    #{Enum.map_join(context.sections, "\n", &format_section/1)}

    Follow-up rules:
    - Treat short prompts as refinements of this workspace unless the user clearly asks for a new workspace.
    - Preserve relevant datasets, measures, dimensions, filters, and section intent from the referenced section.
    - If the user says "just", "only", "those", "them", or names a visible section, resolve that against the current sections.
    - Keep emitting a complete WorkspacePlan; do not emit deltas, UI code, or mutations.
    """
  end

  defp normalize(nil), do: nil
  defp normalize(%__MODULE__{} = context), do: context
  defp normalize(%WorkspaceSnapshot{} = snapshot), do: from_snapshot(snapshot)
  defp normalize(%WorkspacePlan{} = plan), do: from_plan(plan)
  defp normalize(%{plan: %WorkspacePlan{}} = compiled), do: from_compiled(compiled)
  defp normalize(_other), do: nil

  defp fetch_context_value(context) do
    Map.get(context, :workspace_context) ||
      Map.get(context, "workspace_context") ||
      Map.get(context, :workspace_snapshot) ||
      Map.get(context, "workspace_snapshot")
  end

  defp section_from_plan(%Section{} = section, compiled_section, snapshot_metadata) do
    %{
      id: section.id,
      title: section.title,
      role: atom_to_string(section.role),
      pattern: atom_to_string(section.pattern),
      source: source_context(section.source)
    }
    |> maybe_put_renderable(compiled_section, snapshot_metadata)
    |> maybe_put_result(compiled_section)
  end

  defp source_context({:tool_call, %ToolCall{name: name, arguments: arguments}}) do
    %{
      primitive: name,
      dataset: fetch(arguments, "dataset"),
      measures: fetch(arguments, "measures") || [],
      dimensions: fetch(arguments, "dimensions") || [],
      filters: fetch(arguments, "filters") || [],
      sort: fetch(arguments, "sort"),
      limit: fetch(arguments, "limit"),
      title: fetch(arguments, "title")
    }
    |> drop_nil_values()
    |> json_safe()
  end

  defp source_context(_source), do: nil

  defp maybe_put_renderable(section, %{renderable: %Renderable{} = renderable}, _metadata) do
    Map.put(section, :renderable, renderable_context(renderable))
  end

  defp maybe_put_renderable(section, _compiled_section, metadata) when is_map(metadata) do
    Map.put(section, :renderable, %{
      id: metadata.renderable_id,
      type: metadata.renderable_type,
      status: atom_to_string(metadata.status)
    })
  end

  defp maybe_put_renderable(section, _compiled_section, _metadata), do: section

  defp maybe_put_result(section, %{renderable: %Renderable{result: %Result{} = result}}) do
    Map.put(section, :result, result_context(result))
  end

  defp maybe_put_result(section, _compiled_section), do: section

  defp renderable_context(%Renderable{} = renderable) do
    %{
      id: renderable.id,
      type: renderable.type,
      status: atom_to_string(renderable.status)
    }
  end

  defp result_context(%Result{} = result) do
    %{
      kind: atom_to_string(result.kind),
      title: result.title,
      row_count: length(result.data),
      summary: json_safe(result.summary),
      intent: intent_context(result.intent),
      sample: result.data |> Enum.take(3) |> json_safe()
    }
    |> drop_nil_values()
  end

  defp intent_context(%QueryIntent{} = intent) do
    %{
      dataset: intent.dataset,
      measures: intent.measures || [],
      dimensions: intent.dimensions || [],
      filters: intent.filters || [],
      sort: intent.sort,
      limit: intent.limit
    }
    |> drop_nil_values()
    |> json_safe()
  end

  defp intent_context(_intent), do: nil

  defp format_section(section) do
    source = section[:source] || %{}
    result = section[:result] || %{}

    [
      "- id=#{section[:id]}",
      "title=#{inspect(section[:title])}",
      "role=#{section[:role]}",
      "pattern=#{section[:pattern]}",
      "source=#{source[:primitive] || source["primitive"]}",
      "dataset=#{source[:dataset] || source["dataset"]}",
      "measures=#{format_list(source[:measures] || source["measures"])}",
      "dimensions=#{format_list(source[:dimensions] || source["dimensions"])}",
      "filters=#{inspect(source[:filters] || source["filters"] || [])}",
      "result_kind=#{result[:kind] || result["kind"]}",
      "rows=#{result[:row_count] || result["row_count"]}"
    ]
    |> Enum.join(" ")
  end

  defp format_list(nil), do: "[]"
  defp format_list(values) when is_list(values), do: "[" <> Enum.join(values, ", ") <> "]"
  defp format_list(value), do: inspect(value)

  defp fetch(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, safe_atom(key))
  defp fetch(_map, _key), do: nil

  defp safe_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp json_safe(%{} = map) do
    Map.new(map, fn {key, value} -> {key, json_safe(value)} end)
  end

  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: atom_to_string(value)
  defp json_safe(value), do: value

  defp atom_to_string(nil), do: nil
  defp atom_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atom_to_string(value), do: value
end
