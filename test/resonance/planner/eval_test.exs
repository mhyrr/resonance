defmodule Resonance.Planner.EvalTest do
  use ExUnit.Case, async: false

  alias Resonance.LLM.ToolCall
  alias Resonance.Planner.Eval

  @crm_prompts [
    "Show me pipeline health by stage and owner.",
    "Which deals are stuck in negotiation?",
    "Compare this quarter's pipeline to last quarter.",
    "Give me an account review for top enterprise deals.",
    "What should Alice focus on this week?",
    "Show open pipeline by owner.",
    "Where are deals concentrated by stage?",
    "Rank the largest deals in the pipeline.",
    "Summarize proposal-stage pipeline.",
    "Show pipeline trend by quarter."
  ]

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
          },
          %{
            name: "companies",
            description: "CRM accounts",
            fields: ~w(name revenue size region industry),
            measures: ["count(*)", "sum(revenue)", "avg(revenue)"],
            dimensions: ~w(name size region industry),
            filters: [
              %{field: "size", ops: ["="]},
              %{field: "region", ops: ["="]},
              %{field: "industry", ops: ["="]}
            ],
            query_shapes: [
              %{dimensions: ["name"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
              %{dimensions: ["size"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
              %{dimensions: ["region"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
              %{dimensions: ["industry"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]}
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

  defmodule FailingResolver do
    @behaviour Resonance.Resolver

    @impl true
    def describe, do: CRMResolver.describe()

    @impl true
    def resolve(_intent, _context), do: {:error, :database_down}
  end

  defmodule EvalProvider do
    @behaviour Resonance.LLM.Provider

    @impl true
    def chat(prompt, _tools, _opts) do
      arguments = next_eval_output(prompt)

      {:ok,
       [
         %ToolCall{
           id: "plan-#{System.unique_integer([:positive])}",
           name: "create_workspace_plan",
           arguments: arguments
         }
       ]}
    end

    defp next_eval_output(prompt) do
      case Process.get(:planner_eval_outputs) do
        outputs when is_list(outputs) ->
          [next | rest] = outputs
          Process.put(:planner_eval_outputs, rest)
          next

        outputs when is_map(outputs) ->
          Map.fetch!(outputs, prompt)
      end
    end
  end

  setup do
    on_exit(fn -> Process.delete(:planner_eval_outputs) end)
  end

  test "evaluates ten CRM prompts through provider, planner validation, and compiler" do
    outputs =
      @crm_prompts
      |> Enum.with_index()
      |> Map.new(fn {prompt, index} -> {prompt, plan_for(prompt, index)} end)

    Process.put(:planner_eval_outputs, outputs)

    evaluation = Eval.evaluate(@crm_prompts, %{resolver: CRMResolver}, provider: EvalProvider)

    assert evaluation.summary.total == 10
    assert evaluation.summary.valid_plans == 10
    assert evaluation.summary.compiled == 10
    assert evaluation.summary.invalid_plans == 0
    assert evaluation.summary.retried == 0
    assert evaluation.summary.recovered == 0
    assert evaluation.summary.invented_capability_failures == 0
    assert evaluation.summary.invented_pattern_failures == 0
    assert evaluation.summary.invented_primitive_failures == 0
    assert evaluation.summary.compile_rate == 1.0
    assert Enum.all?(evaluation.results, &(&1.status == :compiled))
    assert Enum.all?(evaluation.results, &(length(&1.compiled.renderables) > 0))
    assert Enum.all?(evaluation.results, &(&1.attempts == 1))
    assert Enum.all?(evaluation.results, &(&1.diagnostics.section_count > 0))
  end

  test "records actionable validation errors for invalid planner output" do
    prompt = "Show me impossible CRM data."

    Process.put(:planner_eval_outputs, %{
      prompt =>
        plan_map("bad", [
          section_map("bad", "rank_entities", %{
            "dataset" => "deals",
            "measures" => ["sum(probability)"],
            "dimensions" => ["probability"],
            "title" => "Impossible"
          })
        ])
    })

    evaluation =
      Eval.evaluate([prompt], %{resolver: CRMResolver},
        provider: EvalProvider,
        max_validation_retries: 0
      )

    assert evaluation.summary.total == 1
    assert evaluation.summary.invalid_plans == 1
    assert evaluation.summary.retried == 0
    assert evaluation.summary.invented_capability_failures == 1
    [result] = evaluation.results
    assert result.status == :invalid_plan
    assert result.attempts == 1
    assert result.diagnostics.invented_capability?
    assert {:validation_failed, errors} = result.errors
    assert Enum.any?(errors, &match?(%{code: :unsupported_measure}, &1))
  end

  test "measures planner outputs recovered by validation-feedback retry" do
    prompt = "Show me deal probability, if available."

    Process.put(:planner_eval_outputs, [
      plan_map("bad", [
        section_map("bad", "rank_entities", %{
          "dataset" => "deals",
          "measures" => ["sum(probability)"],
          "dimensions" => ["probability"],
          "title" => "Impossible"
        })
      ]),
      plan_map("recovered", [
        section_map("stage_mix", "show_distribution", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["stage"],
          "title" => "Pipeline by stage"
        })
      ])
    ])

    evaluation = Eval.evaluate([prompt], %{resolver: CRMResolver}, provider: EvalProvider)

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 1
    assert evaluation.summary.retried == 1
    assert evaluation.summary.recovered == 1

    [result] = evaluation.results
    assert result.status == :compiled
    assert result.attempts == 2
    assert result.retried?
    assert result.recovered?
    assert result.diagnostics.retry_error_count > 0
    assert :unsupported_measure in result.diagnostics.retry_validation_error_codes
    assert Enum.any?(result.retry_errors, &match?(%{code: :unsupported_dimension}, &1))
  end

  test "compiles plans that use app-declared patterns" do
    prompt = "What should Alice focus on this week?"

    Process.put(:planner_eval_outputs, %{
      prompt =>
        plan_map("alice_focus", [
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
        ])
    })

    evaluation =
      Eval.evaluate([prompt], %{resolver: CRMResolver, patterns: crm_patterns()},
        provider: EvalProvider
      )

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 1
    assert evaluation.summary.invalid_plans == 0
    [result] = evaluation.results
    assert result.status == :compiled
    assert [%{pattern: :deal_focus_list}] = result.compiled.sections
  end

  test "does not count section-local error renderables as compiled eval success" do
    prompt = "Show open pipeline by owner."

    Process.put(:planner_eval_outputs, %{
      prompt =>
        plan_map("resolver_failure", [
          section_map("owner_pipeline", "segment_population", %{
            "dataset" => "deals",
            "measures" => ["sum(value)"],
            "dimensions" => ["owner"],
            "title" => "Pipeline by owner"
          })
        ])
    })

    evaluation = Eval.evaluate([prompt], %{resolver: FailingResolver}, provider: EvalProvider)

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 0
    assert evaluation.summary.compile_failed == 1

    [result] = evaluation.results
    assert result.status == :compile_failed

    assert {:renderable_errors, [%{section_id: "owner_pipeline", error: :database_down}]} =
             result.errors
  end

  defp plan_for(prompt, index) do
    sections =
      cond do
        prompt =~ "negotiation" ->
          [
            section_map(
              "negotiation_deals",
              "rank_entities",
              %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["name"],
                "filters" => [%{"field" => "stage", "op" => "=", "value" => "negotiation"}],
                "sort" => %{"field" => "sum(value)", "direction" => "desc"},
                "limit" => 10,
                "title" => "Deals in negotiation"
              },
              "focus_list",
              "entity_list"
            )
          ]

        prompt =~ "quarter" ->
          [
            section_map(
              "quarter_trend",
              "compare_over_time",
              %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["quarter"],
                "title" => "Pipeline by quarter"
              },
              "primary",
              "trend_panel"
            )
          ]

        prompt =~ "Alice" ->
          [
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
              "entity_list"
            )
          ]

        prompt =~ "owner" ->
          [
            section_map(
              "owner_scorecard",
              "segment_population",
              %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["owner"],
                "title" => "Pipeline by owner"
              },
              "primary",
              "metric_strip"
            )
          ]

        true ->
          [
            section_map(
              "summary",
              "summarize_findings",
              %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["stage"],
                "title" => "Pipeline summary",
                "focus" => "overview"
              },
              "summary",
              "prose_summary"
            ),
            section_map("stage_mix", "show_distribution", %{
              "dataset" => "deals",
              "measures" => ["sum(value)"],
              "dimensions" => ["stage"],
              "title" => "Pipeline by stage"
            })
          ]
      end

    plan_map("crm_eval_#{index}", sections)
  end

  defp plan_map(goal, sections) do
    %{
      "goal" => goal,
      "title" => String.replace(goal, "_", " "),
      "layout" => "overview_with_detail",
      "identity" => %{"id" => "crm:#{goal}", "kind" => "generated", "saveable" => true},
      "sections" => sections,
      "refinements" => []
    }
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
end
