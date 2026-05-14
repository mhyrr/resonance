defmodule ResonanceDemo.CRM.PatternsTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan.Section
  alias ResonanceDemo.CRM.Patterns, as: CRMPatterns

  test "declares a CRM-specific planner-facing pattern" do
    manifest = Resonance.Patterns.manifest(CRMPatterns)

    assert :deal_focus_list in Resonance.Patterns.names(manifest)

    section = %Section{
      id: "top_deals",
      role: :focus_list,
      pattern: :deal_focus_list,
      source:
        {:tool_call,
         %ToolCall{
           id: "call_top_deals",
           name: "rank_entities",
           arguments: %{
             "dataset" => "deals",
             "measures" => ["sum(value)"],
             "dimensions" => ["name"]
           }
         }}
    }

    assert :ok = Resonance.Patterns.validate_section(section, manifest)
  end
end
