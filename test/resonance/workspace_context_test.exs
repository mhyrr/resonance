defmodule Resonance.WorkspaceContextTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspaceCompiler
  alias Resonance.WorkspaceContext
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section
  alias Resonance.WorkspaceSnapshot

  defmodule Resolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok, [%{label: "Acme", value: 100}, %{label: "Globex", value: 80}]}
    end
  end

  describe "from_plan/2" do
    test "extracts section query sources for follow-up prompts" do
      context = WorkspaceContext.from_plan(plan(), original_prompt: "Show open pipeline by stage")

      assert context.original_prompt == "Show open pipeline by stage"
      assert context.goal == "pipeline_review"
      assert context.title == "Pipeline review"

      assert [
               %{
                 id: "stage_mix",
                 role: "primary",
                 pattern: "summary_panel",
                 source: %{
                   dataset: "deals",
                   dimensions: ["stage"],
                   filters: [%{"field" => "stage", "op" => "=", "value" => "open"}],
                   measures: ["sum(value)"],
                   primitive: "show_distribution"
                 }
               }
             ] = context.sections
    end

    test "formats context without leaking rendering internals" do
      prompt_text =
        plan()
        |> WorkspaceContext.from_plan(original_prompt: "Show open pipeline by stage")
        |> WorkspaceContext.format_for_prompt()

      assert prompt_text =~ "Current workspace context"
      assert prompt_text =~ "original_prompt=\"Show open pipeline by stage\""
      assert prompt_text =~ "id=stage_mix"
      assert prompt_text =~ "dataset=deals"
      assert prompt_text =~ "measures=[sum(value)]"
      assert prompt_text =~ "Follow-up rules"
      refute prompt_text =~ "HEEx"
      refute prompt_text =~ "Phoenix"
      refute prompt_text =~ "Resonance.Components"
    end
  end

  describe "from_compiled/2" do
    test "includes result summaries from the latest compiled workspace" do
      {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})

      context = WorkspaceContext.from_compiled(compiled, original_prompt: "Show open pipeline")

      assert [
               %{
                 result: %{
                   kind: "distribution",
                   row_count: 2,
                   sample: [%{label: "Acme", value: 100}, %{label: "Globex", value: 80}]
                 }
               }
             ] = context.sections

      assert WorkspaceContext.format_for_prompt(context) =~ "result_kind=distribution rows=2"
    end
  end

  describe "from_snapshot/1" do
    test "derives context from saved plan and section metadata" do
      {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})

      snapshot =
        WorkspaceSnapshot.from_compiled(compiled,
          original_prompt: "Show open pipeline",
          created_at: ~U[2026-05-11 12:00:00Z]
        )

      context = WorkspaceContext.from_snapshot(snapshot)

      assert context.original_prompt == "Show open pipeline"
      assert context.fingerprint == snapshot.fingerprint
      assert [%{renderable: %{id: "workspace-stage_mix-show_distribution"}}] = context.sections
    end
  end

  test "extracts context from the public Resonance context map" do
    workspace_context = WorkspaceContext.from_plan(plan(), original_prompt: "Show open pipeline")

    assert ^workspace_context =
             WorkspaceContext.from_context(%{workspace_context: workspace_context})

    snapshot =
      plan()
      |> then(&WorkspaceCompiler.compile(&1, %{resolver: Resolver}))
      |> elem(1)
      |> WorkspaceSnapshot.from_compiled(original_prompt: "Show open pipeline")

    assert %WorkspaceContext{original_prompt: "Show open pipeline"} =
             WorkspaceContext.from_context(%{workspace_snapshot: snapshot})
  end

  defp plan do
    %WorkspacePlan{
      goal: :pipeline_review,
      title: "Pipeline review",
      layout: :overview_with_detail,
      sections: [
        %Section{
          id: "stage_mix",
          title: "Stage mix",
          role: :primary,
          pattern: :summary_panel,
          source:
            {:tool_call,
             tool_call("show_distribution", %{
               "dataset" => "deals",
               "measures" => ["sum(value)"],
               "dimensions" => ["stage"],
               "filters" => [%{"field" => "stage", "op" => "=", "value" => "open"}],
               "title" => "Open pipeline by stage"
             })}
        }
      ]
    }
  end

  defp tool_call(name, arguments) do
    %ToolCall{id: "call_#{name}", name: name, arguments: arguments}
  end
end
