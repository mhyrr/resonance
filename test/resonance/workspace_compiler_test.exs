defmodule Resonance.WorkspaceCompilerTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.Renderable
  alias Resonance.WorkspaceCompiler
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section

  defmodule CRMResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Acme expansion", value: 500_000},
         %{label: "Globex renewal", value: 300_000}
       ]}
    end
  end

  defmodule ChangedCRMResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Acme expansion", value: 900_000},
         %{label: "Globex renewal", value: 100_000}
       ]}
    end
  end

  defmodule FailingResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context), do: {:error, :database_down}
  end

  defmodule RecordingResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, context) do
      send(context.test_pid, :resolver_called)
      {:ok, []}
    end
  end

  defmodule RaisingPresenter do
    @behaviour Resonance.Presenter

    @impl true
    def present(_result, _context), do: raise("presenter boom")
  end

  describe "compile/2" do
    test "compiles a hand-written CRM workspace plan into renderables" do
      plan = workspace_plan()

      assert {:ok, compiled} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})

      assert compiled.plan == plan
      assert Enum.map(compiled.sections, & &1.id) == ["summary", "stuck_deals"]
      assert Enum.map(compiled.sections, & &1.role) == [:summary, :focus_list]
      assert [%Renderable{status: :ready}, %Renderable{status: :ready}] = compiled.renderables
    end

    test "preserves section metadata alongside renderables" do
      plan = workspace_plan()

      assert {:ok, compiled} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})

      [summary | _] = compiled.sections
      assert summary.pattern == :prose_summary
      assert summary.section.id == "summary"
      assert summary.renderable.type == "summarize_findings"
    end

    test "uses stable renderable ids when recompiling the same plan" do
      plan = workspace_plan()

      assert {:ok, first} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})
      assert {:ok, second} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})

      assert Enum.map(first.renderables, & &1.id) == Enum.map(second.renderables, & &1.id)

      assert Enum.map(first.renderables, & &1.id) == [
               "workspace-summary-summarize_findings",
               "workspace-stuck_deals-rank_entities"
             ]
    end

    test "keeps renderable ids stable when source data changes" do
      plan = workspace_plan()

      assert {:ok, first} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})
      assert {:ok, rerun} = WorkspaceCompiler.compile(plan, %{resolver: ChangedCRMResolver})

      assert Enum.map(first.renderables, & &1.id) == Enum.map(rerun.renderables, & &1.id)
      refute Enum.at(first.renderables, 1).props.data == Enum.at(rerun.renderables, 1).props.data
    end

    test "includes workspace identity when present" do
      plan = %{workspace_plan() | identity: %{id: "pipeline:weekly"}}

      assert {:ok, compiled} = WorkspaceCompiler.compile(plan, %{resolver: CRMResolver})

      assert Enum.map(compiled.renderables, & &1.id) == [
               "workspace-pipeline-weekly-summary-summarize_findings",
               "workspace-pipeline-weekly-stuck_deals-rank_entities"
             ]
    end

    test "returns validation errors before resolving invalid plans" do
      plan = %WorkspacePlan{
        goal: :pipeline_review,
        title: "Bad",
        layout: :stack,
        sections: []
      }

      assert {:error, {:validation_failed, [error]}} =
               WorkspaceCompiler.compile(plan, %{resolver: RecordingResolver, test_pid: self()})

      assert error.code == :missing_sections
      refute_received :resolver_called
    end

    test "keeps resolver failures section-local as error renderables" do
      plan = workspace_plan()

      assert {:ok, compiled} = WorkspaceCompiler.compile(plan, %{resolver: FailingResolver})

      assert Enum.all?(compiled.renderables, &(&1.status == :error))
      assert Enum.all?(compiled.renderables, &(&1.error == :database_down))
    end

    test "wraps presenter failures as section-local compile errors" do
      plan = workspace_plan()

      assert {:ok, compiled} =
               WorkspaceCompiler.compile(plan, %{
                 resolver: CRMResolver,
                 presenter: RaisingPresenter
               })

      assert Enum.all?(compiled.renderables, &(&1.status == :error))

      assert Enum.all?(
               compiled.renderables,
               &match?({:compile_failed, "presenter boom"}, &1.error)
             )
    end
  end

  defp workspace_plan do
    %WorkspacePlan{
      goal: :pipeline_review,
      title: "Pipeline review",
      layout: :overview_with_detail,
      sections: [
        %Section{
          id: "summary",
          role: :summary,
          pattern: :prose_summary,
          source: {:tool_call, tool_call("summarize_findings")}
        },
        %Section{
          id: "stuck_deals",
          role: :focus_list,
          pattern: :entity_list,
          source: {:tool_call, tool_call("rank_entities")},
          interactions: [:filter, :inspect]
        }
      ]
    }
  end

  defp tool_call(name) do
    %ToolCall{
      id: "call_#{name}",
      name: name,
      arguments: %{
        "dataset" => "deals",
        "measures" => ["sum(value)"],
        "dimensions" => ["stage"],
        "title" => "Pipeline"
      }
    }
  end
end
