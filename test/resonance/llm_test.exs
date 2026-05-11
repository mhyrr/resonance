defmodule Resonance.LLMTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspaceContext
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section

  defmodule DescribingResolver do
    @behaviour Resonance.Resolver

    @impl true
    def describe do
      """
      Datasets:
      - "widgets" — measures: count(*), sum(cost)
      """
    end

    @impl true
    def resolve(_intent, _context), do: {:ok, []}
  end

  defmodule MinimalResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context), do: {:ok, []}
  end

  describe "build_system_prompt/1" do
    test "includes base instructions" do
      prompt = Resonance.LLM.build_system_prompt(%{})

      assert prompt =~ "data analysis assistant"
      assert prompt =~ "semantic primitives"
      assert prompt =~ "CRITICAL"
      assert prompt =~ "exact dataset names"
    end

    test "appends resolver.describe/0 when available" do
      prompt = Resonance.LLM.build_system_prompt(%{resolver: DescribingResolver})

      assert prompt =~ "data analysis assistant"
      assert prompt =~ "widgets"
      assert prompt =~ "sum(cost)"
    end

    test "returns base prompt when resolver has no describe/0" do
      prompt = Resonance.LLM.build_system_prompt(%{resolver: MinimalResolver})

      assert prompt =~ "data analysis assistant"
      refute prompt =~ "widgets"
    end

    test "returns base prompt when no resolver provided" do
      prompt = Resonance.LLM.build_system_prompt(%{})

      assert prompt =~ "data analysis assistant"
      refute prompt =~ "Datasets:"
    end

    test "appends workspace context when provided" do
      workspace_context =
        %WorkspacePlan{
          goal: :pipeline_review,
          title: "Pipeline review",
          layout: :stack,
          sections: [
            %Section{
              id: "stage_mix",
              title: "Pipeline by stage",
              role: :primary,
              pattern: :summary_panel,
              source:
                {:tool_call,
                 %ToolCall{
                   id: "call_stage_mix",
                   name: "show_distribution",
                   arguments: %{
                     "dataset" => "deals",
                     "measures" => ["sum(value)"],
                     "dimensions" => ["stage"],
                     "title" => "Pipeline by stage"
                   }
                 }}
            }
          ]
        }
        |> WorkspaceContext.from_plan(original_prompt: "Show pipeline by stage.")

      prompt = Resonance.LLM.build_system_prompt(%{workspace_context: workspace_context})

      assert prompt =~ "Current workspace context"
      assert prompt =~ "original_prompt=\"Show pipeline by stage.\""
      assert prompt =~ "id=stage_mix"
      assert prompt =~ "Follow-up rules"
    end
  end
end
