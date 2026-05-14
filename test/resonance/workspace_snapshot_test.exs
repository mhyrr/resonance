defmodule Resonance.WorkspaceSnapshotTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.Renderable
  alias Resonance.WorkspaceCompiler
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

  defmodule ChangedResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok, [%{label: "Acme", value: 500}, %{label: "Globex", value: 10}]}
    end
  end

  describe "snapshots" do
    test "serializes and deserializes a compiled workspace snapshot" do
      snapshot = snapshot()

      assert {:ok, decoded} =
               snapshot
               |> WorkspaceSnapshot.to_map()
               |> WorkspaceSnapshot.from_map()

      assert decoded.fingerprint == snapshot.fingerprint
      assert decoded.original_prompt == "Show my pipeline"
      assert decoded.plan.title == snapshot.plan.title
      assert Enum.map(decoded.plan.sections, & &1.id) == ["summary", "stuck_deals"]

      assert Enum.map(decoded.sections, & &1.renderable_id) ==
               Enum.map(snapshot.sections, & &1.renderable_id)
    end

    test "round trips through JSON" do
      snapshot = snapshot()

      assert {:ok, json} = WorkspaceSnapshot.to_json(snapshot)
      assert {:ok, decoded} = WorkspaceSnapshot.from_json(json)

      assert decoded.fingerprint == snapshot.fingerprint
      assert decoded.plan.identity["kind"] == "ephemeral"
      assert decoded.plan.identity["saveable"] == true
    end

    test "fingerprint is deterministic for equivalent plans" do
      assert WorkspaceSnapshot.fingerprint(plan()) == WorkspaceSnapshot.fingerprint(plan())
    end

    test "reruns stored section sources without an LLM call and preserves ids" do
      original = snapshot()
      parent = self()

      WorkspaceSnapshot.rerun(original, %{resolver: ChangedResolver}, fn event ->
        send(parent, {:rerun, event})
      end)

      assert_receive {:rerun,
                      {:component_ready, %Renderable{id: "workspace-summary-summarize_findings"}}},
                     5000

      assert_receive {:rerun,
                      {:component_ready,
                       %Renderable{
                         id: "workspace-stuck_deals-rank_entities",
                         props: %{data: data}
                       }}},
                     5000

      assert [%{value: 500}, %{value: 10}] = data
      assert_receive {:rerun, :done}, 5000
    end
  end

  defp snapshot do
    {:ok, compiled} = WorkspaceCompiler.compile(plan(), %{resolver: Resolver})

    WorkspaceSnapshot.from_compiled(compiled,
      original_prompt: "Show my pipeline",
      created_at: ~U[2026-05-10 12:00:00Z]
    )
  end

  defp plan do
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
