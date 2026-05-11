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
    old_provider = Application.get_env(:resonance, :provider)
    old_model = Application.get_env(:resonance, :model)

    Application.put_env(:resonance, :provider, EvalProvider)
    Application.put_env(:resonance, :model, "planner-eval-test")

    on_exit(fn ->
      restore_env(:provider, old_provider)
      restore_env(:model, old_model)
      Process.delete(:planner_eval_outputs)
    end)

    :ok
  end

  test "evaluates ten CRM prompts through provider, planner validation, and compiler" do
    outputs =
      @crm_prompts
      |> Enum.with_index()
      |> Map.new(fn {prompt, index} -> {prompt, plan_for(prompt, index)} end)

    Process.put(:planner_eval_outputs, outputs)

    evaluation = Eval.evaluate(@crm_prompts, %{resolver: CRMResolver})

    assert evaluation.summary.total == 10
    assert evaluation.summary.valid_plans == 10
    assert evaluation.summary.compiled == 10
    assert evaluation.summary.invalid_plans == 0
    assert evaluation.summary.retried == 0
    assert evaluation.summary.recovered == 0
    assert evaluation.summary.compile_rate == 1.0
    assert Enum.all?(evaluation.results, &(&1.status == :compiled))
    assert Enum.all?(evaluation.results, &(length(&1.compiled.renderables) > 0))
    assert Enum.all?(evaluation.results, &(&1.attempts == 1))
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

    evaluation = Eval.evaluate([prompt], %{resolver: CRMResolver}, max_validation_retries: 0)

    assert evaluation.summary.total == 1
    assert evaluation.summary.invalid_plans == 1
    assert evaluation.summary.retried == 0
    [result] = evaluation.results
    assert result.status == :invalid_plan
    assert result.attempts == 1
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

    evaluation = Eval.evaluate([prompt], %{resolver: CRMResolver})

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 1
    assert evaluation.summary.retried == 1
    assert evaluation.summary.recovered == 1

    [result] = evaluation.results
    assert result.status == :compiled
    assert result.attempts == 2
    assert result.retried?
    assert result.recovered?
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

    evaluation = Eval.evaluate([prompt], %{resolver: CRMResolver, patterns: crm_patterns()})

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 1
    assert evaluation.summary.invalid_plans == 0
    [result] = evaluation.results
    assert result.status == :compiled
    assert [%{pattern: :deal_focus_list}] = result.compiled.sections
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
end
