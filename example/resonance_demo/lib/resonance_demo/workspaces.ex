defmodule ResonanceDemo.Workspaces do
  @moduledoc """
  Hand-written workspace plans owned by the CRM demo app.

  These are deliberately ordinary Elixir values. Resonance validates and
  compiles them, but the demo app decides what workspace exists and how it is
  revisited.
  """

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section

  @doc """
  A deterministic v3 workspace for a CRM pipeline review.
  """
  def pipeline_review do
    %WorkspacePlan{
      goal: :pipeline_review,
      title: "Pipeline review",
      layout: :overview_with_detail,
      identity: %{id: "crm:pipeline-review", kind: :hand_written, saveable: true},
      sections: [
        %Section{
          id: "pipeline_summary",
          title: "Pipeline summary",
          role: :summary,
          pattern: :prose_summary,
          source:
            {:tool_call,
             tool_call("summarize_findings", %{
               "dataset" => "deals",
               "measures" => ["sum(value)"],
               "dimensions" => ["stage"],
               "title" => "Pipeline health",
               "focus" => "overview"
             })}
        },
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
               "title" => "Pipeline value by stage"
             })}
        },
        %Section{
          id: "quarter_trend",
          title: "Quarter trend",
          role: :primary,
          pattern: :trend_panel,
          source:
            {:tool_call,
             tool_call("compare_over_time", %{
               "dataset" => "deals",
               "measures" => ["sum(value)"],
               "dimensions" => ["quarter"],
               "title" => "Pipeline value by quarter"
             })}
        },
        %Section{
          id: "top_deals",
          title: "Top deals",
          role: :focus_list,
          pattern: :entity_list,
          source:
            {:tool_call,
             tool_call("rank_entities", %{
               "dataset" => "deals",
               "measures" => ["sum(value)"],
               "dimensions" => ["name"],
               "sort" => %{"field" => "sum(value)", "direction" => "desc"},
               "limit" => 8,
               "title" => "Largest open deals"
             })},
          interactions: [:filter, :inspect]
        },
        %Section{
          id: "owner_scorecard",
          title: "Owner scorecard",
          role: :supporting_context,
          pattern: :metric_strip,
          source:
            {:tool_call,
             tool_call("segment_population", %{
               "dataset" => "deals",
               "measures" => ["sum(value)"],
               "dimensions" => ["owner"],
               "title" => "Pipeline value by owner"
             })},
          interactions: [:filter]
        }
      ]
    }
  end

  defp tool_call(name, arguments) do
    %ToolCall{
      id: "crm_workspace_#{name}",
      name: name,
      arguments: arguments
    }
  end
end
