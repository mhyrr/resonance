defmodule Resonance.WorkspacePlanTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section
  alias Resonance.WorkspacePlan.Validation

  describe "validate/1" do
    test "validates a hand-written CRM workspace plan" do
      plan = %WorkspacePlan{
        goal: :pipeline_review,
        title: "Pipeline review for this week",
        layout: :overview_with_detail,
        sections: [
          %Section{
            id: "summary",
            role: :summary,
            pattern: :prose_summary,
            source: {:tool_call, tool_call("summarize_findings")},
            interactions: []
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

      assert {:ok, ^plan} = WorkspacePlan.validate(plan)
    end

    test "rejects unsupported layout" do
      plan = valid_plan(%{layout: :masonry})

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :unsupported_layout
      assert error.path == [:layout]
      assert error.details.allowed == [:stack, :dashboard_grid, :overview_with_detail]
    end

    test "rejects duplicate section ids" do
      section = valid_section(%{id: "summary"})
      plan = valid_plan(%{sections: [section, %{section | role: :primary}]})

      assert {:error, {:validation_failed, errors}} = Validation.validate(plan)
      assert Enum.any?(errors, &match?(%{code: :duplicate_section_id}, &1))
      assert Enum.any?(errors, &(&1.path == [:sections, "summary", :id]))
    end

    test "rejects unsupported section role" do
      plan = valid_plan(%{sections: [valid_section(%{role: :sidebar})]})

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :unsupported_role
      assert error.path == [:sections, "summary", :role]
    end

    test "rejects unsupported section pattern" do
      plan = valid_plan(%{sections: [valid_section(%{pattern: :raw_card})]})

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :unsupported_pattern
      assert error.path == [:sections, "summary", :pattern]
    end

    test "rejects incompatible section pattern and source primitive" do
      plan =
        valid_plan(%{
          sections: [
            valid_section(%{
              role: :primary,
              pattern: :metric_strip,
              source: {:tool_call, tool_call("rank_entities")}
            })
          ]
        })

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :incompatible_pattern_source
      assert error.path == [:sections, "summary", :source, :tool_call, :name]
      assert error.details.allowed_primitives == ["segment_population"]
    end

    test "accepts app-declared section patterns" do
      plan =
        valid_plan(%{
          sections: [
            valid_section(%{
              role: :focus_list,
              pattern: :deal_focus_list,
              source: {:tool_call, tool_call("rank_entities")}
            })
          ]
        })

      assert {:ok, ^plan} = WorkspacePlan.validate(plan, patterns: custom_patterns())
    end

    test "rejects invalid section source" do
      plan = valid_plan(%{sections: [valid_section(%{source: {:query, %{dataset: "deals"}}})]})

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :invalid_source
      assert error.path == [:sections, "summary", :source]
    end

    test "rejects invalid tool call fields" do
      plan =
        valid_plan(%{
          sections: [
            valid_section(%{
              source: {:tool_call, %ToolCall{name: "", arguments: nil}}
            })
          ]
        })

      assert {:error, {:validation_failed, errors}} = Validation.validate(plan)

      assert Enum.map(errors, & &1.code) == [
               :invalid_tool_call_name,
               :invalid_tool_call_arguments
             ]
    end

    test "accumulates plan and section validation errors" do
      plan = %WorkspacePlan{
        goal: nil,
        title: "",
        layout: :masonry,
        sections: [
          %Section{id: "", role: :sidebar, pattern: :raw_card, source: :missing}
        ],
        refinements: :none,
        identity: nil
      }

      assert {:error, {:validation_failed, errors}} = Validation.validate(plan)

      assert [
               :invalid_goal,
               :invalid_title,
               :unsupported_layout,
               :invalid_section_id,
               :unsupported_role,
               :unsupported_pattern,
               :invalid_source,
               :invalid_refinements,
               :invalid_identity
             ] = Enum.map(errors, & &1.code)
    end

    test "rejects empty section list" do
      plan = valid_plan(%{sections: []})

      assert {:error, {:validation_failed, [error]}} = Validation.validate(plan)
      assert error.code == :missing_sections
      assert error.path == [:sections]
    end

    test "exposes allowed schema values" do
      assert Validation.allowed_layouts() == [:stack, :dashboard_grid, :overview_with_detail]
      assert :focus_list in Validation.allowed_roles()
      assert :entity_list in Validation.allowed_patterns()
      assert :deal_focus_list in Validation.allowed_patterns(patterns: custom_patterns())
    end
  end

  describe "from_map/2" do
    test "decodes app-declared pattern names without creating arbitrary atoms" do
      map = %{
        "goal" => "deal_focus",
        "title" => "Deal focus",
        "layout" => "stack",
        "sections" => [
          %{
            "id" => "top_deals",
            "role" => "focus_list",
            "pattern" => "deal_focus_list",
            "source" => %{
              "type" => "tool_call",
              "tool_call" => %{
                "id" => "call_top_deals",
                "name" => "rank_entities",
                "arguments" => %{
                  "dataset" => "deals",
                  "measures" => ["sum(value)"],
                  "dimensions" => ["name"],
                  "title" => "Top deals"
                }
              }
            }
          }
        ]
      }

      assert {:ok, plan} = WorkspacePlan.from_map(map, patterns: custom_patterns())
      assert [%Section{pattern: :deal_focus_list}] = plan.sections
    end
  end

  defp valid_plan(attrs) do
    struct!(
      %WorkspacePlan{
        goal: :pipeline_review,
        title: "Pipeline review",
        layout: :stack,
        sections: [valid_section(%{})]
      },
      attrs
    )
  end

  defp valid_section(attrs) do
    struct!(
      %Section{
        id: "summary",
        role: :summary,
        pattern: :prose_summary,
        source: {:tool_call, tool_call("summarize_findings")}
      },
      attrs
    )
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

  defp custom_patterns do
    [
      %{
        name: :deal_focus_list,
        description: "CRM deal list for follow-up work.",
        roles: [:focus_list, :detail],
        result_kinds: [:ranking],
        source_primitives: ["rank_entities"]
      }
    ]
  end
end
