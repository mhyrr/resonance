defmodule Resonance.PlannerTest do
  use ExUnit.Case, async: false

  alias Resonance.LLM.ToolCall
  alias Resonance.Planner
  alias Resonance.WorkspaceContext
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section

  defmodule CRMResolver do
    @behaviour Resonance.Resolver

    @impl true
    def describe do
      %{
        datasets: [
          %{
            name: "deals",
            description: "CRM opportunities",
            fields: ~w(name value stage owner quarter),
            measures: ["count(*)", "sum(value)", "avg(value)"],
            dimensions: ~w(name stage owner quarter),
            filters: [
              %{field: "stage", ops: ["="]},
              %{field: "owner", ops: ["="]},
              %{field: "quarter", ops: ["="]}
            ],
            query_shapes: [
              %{dimensions: ["name"], measures: ["count(*)", "sum(value)", "avg(value)"]},
              %{dimensions: ["stage"], measures: ["count(*)", "sum(value)", "avg(value)"]},
              %{dimensions: ["owner"], measures: ["count(*)", "sum(value)", "avg(value)"]},
              %{dimensions: ["quarter"], measures: ["count(*)", "sum(value)", "avg(value)"]},
              %{
                dimensions: ["stage", "quarter"],
                measures: ["count(*)", "sum(value)", "avg(value)"]
              }
            ]
          }
        ]
      }
    end

    @impl true
    def resolve(_intent, _context) do
      {:ok, [%{label: "Acme expansion", value: 500_000}, %{label: "Globex", value: 300_000}]}
    end
  end

  defmodule PlannerProvider do
    @behaviour Resonance.LLM.Provider

    @impl true
    def chat(prompt, tools, opts) do
      send(
        Process.get(:planner_test_pid),
        {:planner_provider_called, prompt, tools, opts[:system]}
      )

      arguments = next_planner_output(prompt)

      {:ok, [%ToolCall{id: "plan-1", name: "create_workspace_plan", arguments: arguments}]}
    end

    defp next_planner_output(prompt) do
      case Process.get(:planner_outputs) do
        outputs when is_list(outputs) ->
          [next | rest] = outputs
          Process.put(:planner_outputs, rest)
          next

        outputs when is_map(outputs) ->
          Map.fetch!(outputs, prompt)
      end
    end
  end

  setup do
    old_provider = Application.get_env(:resonance, :provider)
    old_model = Application.get_env(:resonance, :model)

    Application.put_env(:resonance, :provider, PlannerProvider)
    Application.put_env(:resonance, :model, "planner-test")

    Process.put(:planner_test_pid, self())

    on_exit(fn ->
      restore_env(:provider, old_provider)
      restore_env(:model, old_model)
      Process.delete(:planner_test_pid)
      Process.delete(:planner_outputs)
    end)

    :ok
  end

  describe "plan/3" do
    test "requests a create_workspace_plan tool call and returns a typed WorkspacePlan" do
      prompt = "Show me pipeline health by stage and owner."
      Process.put(:planner_outputs, %{prompt => valid_plan_map()})

      assert {:ok, %WorkspacePlan{} = plan} = Planner.plan(prompt, %{resolver: CRMResolver})

      assert plan.goal == "pipeline_health"
      assert plan.layout == :overview_with_detail
      assert Enum.map(plan.sections, & &1.id) == ["summary", "stage_mix", "owner_focus"]
      assert [%{source: {:tool_call, %ToolCall{name: "summarize_findings"}}} | _] = plan.sections

      assert_receive {:planner_provider_called, ^prompt, [schema], system_prompt}
      assert schema.name == "create_workspace_plan"

      arguments_schema =
        schema.parameters.properties.sections.items.properties.source.properties.tool_call.properties.arguments

      assert arguments_schema.properties.filters.type == "array"
      assert arguments_schema.properties.filters.items.required == ["field", "op", "value"]
      assert arguments_schema.properties.sort.properties.field.type == "string"
      assert system_prompt =~ "workspace planner"
      assert system_prompt =~ ~s("deals")
      assert system_prompt =~ "sum(value)"
      assert system_prompt =~ "filters must be an array"
      assert system_prompt =~ "must match"
      assert system_prompt =~ "one declared query_shape exactly"
      assert system_prompt =~ "Multi-dimension sections are allowed only"
    end

    test "passes app-declared patterns through schema, prompt, and JSON decoding" do
      prompt = "What should Alice focus on this week?"

      Process.put(:planner_outputs, %{
        prompt =>
          valid_plan_map(%{
            "sections" => [
              section_map(
                "alice_focus",
                "rank_entities",
                %{
                  "dataset" => "deals",
                  "measures" => ["sum(value)"],
                  "dimensions" => ["name"],
                  "filters" => [%{"field" => "owner", "op" => "=", "value" => "Alice"}],
                  "sort" => %{"field" => "sum(value)", "direction" => "desc"},
                  "limit" => 5,
                  "title" => "Alice focus deals"
                },
                "focus_list",
                "deal_focus_list"
              )
            ]
          })
      })

      assert {:ok, %WorkspacePlan{} = plan} =
               Planner.plan(prompt, %{resolver: CRMResolver, patterns: crm_patterns()})

      assert [%{pattern: :deal_focus_list}] = plan.sections

      assert_receive {:planner_provider_called, ^prompt, [schema], system_prompt}
      pattern_enum = schema.parameters.properties.sections.items.properties.pattern.enum

      assert "deal_focus_list" in pattern_enum
      assert system_prompt =~ "- deal_focus_list:"
      assert system_prompt =~ "source_primitives=[rank_entities]"
      refute system_prompt =~ "Resonance.Components"
    end

    test "includes workspace-scoped context for follow-up prompts" do
      prompt = "Just closed won."

      Process.put(:planner_outputs, %{
        prompt =>
          valid_plan_map(%{
            "sections" => [
              section_map("closed_won_pipeline", "show_distribution", %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["stage"],
                "filters" => [%{"field" => "stage", "op" => "=", "value" => "closed_won"}],
                "title" => "Closed won pipeline"
              })
            ]
          })
      })

      workspace_context =
        existing_workspace_plan()
        |> WorkspaceContext.from_plan(original_prompt: "Show pipeline by stage.")

      assert {:ok, %WorkspacePlan{} = plan} =
               Planner.plan(prompt, %{resolver: CRMResolver, workspace_context: workspace_context})

      assert [%{id: "closed_won_pipeline"}] = plan.sections

      assert_receive {:planner_provider_called, ^prompt, [_schema], system_prompt}
      assert system_prompt =~ "Current workspace context"
      assert system_prompt =~ "original_prompt=\"Show pipeline by stage.\""
      assert system_prompt =~ "id=stage_mix"
      assert system_prompt =~ "dataset=deals"
      assert system_prompt =~ "dimensions=[stage]"
      assert system_prompt =~ "Follow-up rules"
    end

    test "rejects plans that invent fields outside resolver capabilities" do
      prompt = "Show deal probability."

      invalid_plan =
        valid_plan_map(%{
          "sections" => [
            section_map("bad_probability", "rank_entities", %{
              "dataset" => "deals",
              "measures" => ["sum(probability)"],
              "dimensions" => ["probability"],
              "title" => "Deal probability"
            })
          ]
        })

      Process.put(:planner_outputs, %{prompt => invalid_plan})

      assert {:error, {:validation_failed, errors}} =
               Planner.plan(prompt, %{resolver: CRMResolver}, max_validation_retries: 0)

      assert Enum.any?(errors, &match?(%{code: :unsupported_measure}, &1))
      assert Enum.any?(errors, &match?(%{code: :unsupported_dimension}, &1))
    end

    test "rejects planner output that names unsupported workspace patterns" do
      prompt = "Make me a fancy pipeline card."

      invalid_plan =
        valid_plan_map(%{
          "sections" => [
            %{
              "id" => "raw_ui",
              "role" => "primary",
              "pattern" => "raw_card",
              "source" => %{
                "type" => "tool_call",
                "tool_call" => %{
                  "name" => "rank_entities",
                  "arguments" => %{
                    "dataset" => "deals",
                    "measures" => ["sum(value)"],
                    "dimensions" => ["name"],
                    "title" => "Deals"
                  }
                }
              }
            }
          ]
        })

      Process.put(:planner_outputs, %{prompt => invalid_plan})

      assert {:error, {:validation_failed, [error]}} =
               Planner.plan(prompt, %{resolver: CRMResolver}, max_validation_retries: 0)

      assert error.code == :unsupported_pattern
      assert error.path == [:sections, "raw_ui", :pattern]
    end

    test "rejects plans whose pattern is incompatible with the source primitive" do
      prompt = "Show my biggest deals as a metric strip."

      invalid_plan =
        valid_plan_map(%{
          "sections" => [
            section_map(
              "bad_metric_strip",
              "rank_entities",
              %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["name"],
                "title" => "Biggest deals"
              },
              "primary",
              "metric_strip"
            )
          ]
        })

      Process.put(:planner_outputs, %{prompt => invalid_plan})

      assert {:error, {:validation_failed, [error]}} =
               Planner.plan(prompt, %{resolver: CRMResolver}, max_validation_retries: 0)

      assert error.code == :incompatible_pattern_source
      assert error.path == [:sections, "bad_metric_strip", :source, :tool_call, :name]
      assert error.details.pattern == :metric_strip
      assert error.details.allowed_primitives == ["segment_population"]
    end

    test "retries once with structured validation feedback and returns the corrected plan" do
      prompt = "Show deal probability."

      invalid_plan =
        valid_plan_map(%{
          "sections" => [
            section_map("bad_probability", "rank_entities", %{
              "dataset" => "deals",
              "measures" => ["sum(probability)"],
              "dimensions" => ["probability"],
              "title" => "Deal probability"
            })
          ]
        })

      Process.put(:planner_outputs, [invalid_plan, valid_plan_map()])

      assert {:ok, result} = Planner.plan_result(prompt, %{resolver: CRMResolver})
      assert result.attempts == 2
      assert result.retried?
      assert result.recovered?
      assert Enum.any?(result.retry_errors, &match?(%{code: :unsupported_measure}, &1))
      assert Enum.any?(result.retry_errors, &match?(%{code: :unsupported_dimension}, &1))
      assert Enum.map(result.plan.sections, & &1.id) == ["summary", "stage_mix", "owner_focus"]

      assert_receive {:planner_provider_called, ^prompt, [_schema], _system_prompt}
      assert_receive {:planner_provider_called, retry_prompt, [_schema], _system_prompt}

      assert retry_prompt =~ "previous workspace plan was invalid"
      assert retry_prompt =~ "unsupported_measure"
      assert retry_prompt =~ "unsupported_dimension"
      assert retry_prompt =~ ~s([{"field": "stage", "op": "=", "value": "negotiation"}])
      assert retry_prompt =~ "one exact declared query_shape"

      assert retry_prompt =~ "combine dimensions unless that exact dimension list is declared"

      assert retry_prompt =~ prompt
    end

    test "keeps retry-triggering validation errors when the retry also fails" do
      prompt = "Show deal probability."

      invalid_plan =
        valid_plan_map(%{
          "sections" => [
            section_map("bad_probability", "rank_entities", %{
              "dataset" => "deals",
              "measures" => ["sum(probability)"],
              "dimensions" => ["probability"],
              "title" => "Deal probability"
            })
          ]
        })

      Process.put(:planner_outputs, [invalid_plan, invalid_plan])

      assert {:error, result} = Planner.plan_result(prompt, %{resolver: CRMResolver})
      assert result.attempts == 2
      assert result.retried?
      refute result.recovered?
      assert {:validation_failed, _errors} = result.reason
      assert Enum.any?(result.retry_errors, &match?(%{code: :unsupported_measure}, &1))
    end
  end

  defp valid_plan_map(overrides \\ %{}) do
    Map.merge(
      %{
        "goal" => "pipeline_health",
        "title" => "Pipeline health",
        "layout" => "overview_with_detail",
        "identity" => %{"id" => "crm:pipeline-health", "kind" => "generated", "saveable" => true},
        "sections" => [
          section_map(
            "summary",
            "summarize_findings",
            %{
              "dataset" => "deals",
              "measures" => ["sum(value)"],
              "dimensions" => ["stage"],
              "title" => "Pipeline health",
              "focus" => "overview"
            },
            "summary",
            "prose_summary"
          ),
          section_map("stage_mix", "show_distribution", %{
            "dataset" => "deals",
            "measures" => ["sum(value)"],
            "dimensions" => ["stage"],
            "title" => "Pipeline value by stage"
          }),
          section_map(
            "owner_focus",
            "segment_population",
            %{
              "dataset" => "deals",
              "measures" => ["sum(value)"],
              "dimensions" => ["owner"],
              "title" => "Pipeline value by owner"
            },
            "supporting_context",
            "metric_strip"
          )
        ],
        "refinements" => []
      },
      overrides
    )
  end

  defp section_map(id, primitive, arguments, role \\ "primary", pattern \\ "summary_panel") do
    %{
      "id" => id,
      "title" => arguments["title"],
      "role" => role,
      "pattern" => pattern,
      "source" => %{
        "type" => "tool_call",
        "tool_call" => %{
          "id" => "call_#{id}",
          "name" => primitive,
          "arguments" => arguments
        }
      },
      "interactions" => ["filter"]
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:resonance, key)
  defp restore_env(key, value), do: Application.put_env(:resonance, key, value)

  defp crm_patterns do
    [
      %{
        name: :deal_focus_list,
        description: "CRM deal list for owner/account follow-up work.",
        roles: [:focus_list, :detail],
        result_kinds: [:ranking],
        source_primitives: ["rank_entities"]
      }
    ]
  end

  defp existing_workspace_plan do
    %WorkspacePlan{
      goal: :pipeline_review,
      title: "Pipeline by stage",
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
  end
end
