defmodule ResonanceDemo.PlannerEval do
  @moduledoc """
  CRM planner-eval corpus and deterministic provider.

  The corpus is app-owned on purpose: it is the CRM product vocabulary that the
  planner must use, not library test data disguised as product behavior.
  """

  alias Resonance.LLM.ToolCall
  alias Resonance.Planner
  alias Resonance.Planner.Eval
  alias ResonanceDemo.CRM
  alias ResonanceDemoWeb.Presenters

  @prompts [
    %{
      id: "pipeline_health",
      prompt: "Show me pipeline health by stage and owner.",
      expectation: "Stage mix, owner mix, and a summary section."
    },
    %{
      id: "stuck_negotiation",
      prompt: "Which deals are stuck in negotiation?",
      expectation: "Focused ranked deal list filtered to negotiation."
    },
    %{
      id: "quarter_compare",
      prompt: "Compare this quarter's pipeline to last quarter.",
      expectation: "Quarter trend over declared pipeline quarter data."
    },
    %{
      id: "enterprise_account_review",
      prompt: "Give me an account review for top enterprise deals.",
      expectation: "Enterprise account ranking plus deal focus context."
    },
    %{
      id: "alice_focus",
      prompt: "What should Alice focus on this week?",
      expectation: "Alice-owned deal focus list sorted by value."
    },
    %{
      id: "open_pipeline_by_owner",
      prompt: "Show open pipeline by owner.",
      expectation: "Owner pipeline excluding closed won/lost stages."
    },
    %{
      id: "contact_funnel",
      prompt: "What does the contact funnel look like?",
      expectation: "Contact stages as a categorical funnel."
    },
    %{
      id: "no_response_activity",
      prompt: "Where are sales activities getting no response?",
      expectation: "Activity type mix filtered to no-response outcomes."
    },
    %{
      id: "largest_deals",
      prompt: "Rank the largest deals in the pipeline.",
      expectation: "Top deal list sorted by deal value."
    },
    %{
      id: "proposal_pipeline",
      prompt: "Summarize proposal-stage pipeline.",
      expectation: "Proposal-stage summary and distribution."
    },
    %{
      id: "forecast_vampires",
      prompt:
        "Which opportunities are the forecast vampires: technically alive, still draining attention, and most likely to embarrass us on Friday?",
      expectation: "High-value open deal focus with enough context to spot forecast risk."
    },
    %{
      id: "board_packet_dashboard",
      prompt:
        "Board packet is tomorrow. I need a compact CRM operating dashboard that tells me whether the pipeline is healthy, where revenue is stuck, whether the quarter is getting better or worse, and which accounts or owners need attention.\n\nKeep it read-only and executive-friendly: show the big pipeline picture first, then give me the specific account/deal focus areas I should ask the team about.",
      expectation:
        "Comprehensive multi-section dashboard across summary, trend, owner, account, and activity signals."
    }
  ]

  @doc "Golden CRM prompts used by the planner eval."
  def prompts, do: @prompts

  @doc "Planner/compiler context for the CRM example."
  def context do
    %{
      resolver: CRM.Resolver,
      patterns: CRM.Patterns,
      presenter: Presenters.Interactive
    }
  end

  @doc "Run the CRM eval through the same planner validation and compiler path."
  def evaluate(opts \\ []) do
    opts = Keyword.put_new(opts, :provider, __MODULE__.Provider)
    evaluate_prompt_set(@prompts, opts)
  end

  @doc """
  Run the CRM eval with the provider supplied by opts or application config.

  This is intended for real-provider benchmarking. Unlike `evaluate/1`, it does
  not install the deterministic eval provider by default.
  """
  def evaluate_real(opts \\ []) do
    prompt_set = Keyword.get(opts, :prompts, @prompts)
    opts = Keyword.delete(opts, :prompts)
    evaluate_prompt_set(prompt_set, opts)
  end

  @doc "Run a caller-provided prompt set through the planner eval path."
  def evaluate_prompt_set(prompt_set, opts \\ []) when is_list(prompt_set) do
    prompt_set
    |> Enum.map(& &1.prompt)
    |> Eval.evaluate(context(), opts)
    |> attach_prompt_metadata(prompt_set)
  end

  @doc "Plan a single CRM prompt with the deterministic eval provider."
  def plan(prompt, opts \\ []) when is_binary(prompt) do
    opts = Keyword.put_new(opts, :provider, __MODULE__.Provider)
    Planner.plan_result(prompt, context(), opts)
  end

  @doc "Run a deliberately invalid plan through validation for the eval UI."
  def guardrail do
    Eval.evaluate(["Show deal probability by owner."], context(),
      provider: __MODULE__.InvalidProvider,
      max_validation_retries: 0
    )
  end

  @doc "Return a deterministic provider output for a golden prompt."
  def plan_arguments(prompt) when is_binary(prompt) do
    prompt
    |> prompt_id()
    |> plan_arguments_for_id()
  end

  @doc "A deliberately invalid planner output for validating guardrail surfacing."
  def invalid_probability_arguments do
    plan_map("invalid_probability", [
      section_map("probability_by_owner", "rank_entities", %{
        "dataset" => "deals",
        "measures" => ["sum(probability)"],
        "dimensions" => ["probability"],
        "title" => "Deal probability by owner"
      })
    ])
  end

  defp attach_prompt_metadata(%{results: results} = evaluation, prompt_set) do
    by_prompt = Map.new(prompt_set, &{&1.prompt, &1})

    results =
      Enum.map(results, fn result ->
        metadata = Map.fetch!(by_prompt, result.prompt)

        result
        |> Map.put(:id, metadata.id)
        |> Map.put(:expectation, metadata.expectation)
      end)

    %{evaluation | results: results}
  end

  defp prompt_id(prompt) do
    case Enum.find(@prompts, &(&1.prompt == prompt)) do
      %{id: id} -> id
      nil -> "pipeline_health"
    end
  end

  defp plan_arguments_for_id("pipeline_health") do
    plan_map("pipeline_health", [
      section_map(
        "pipeline_summary",
        "summarize_findings",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["stage"],
          "title" => "Pipeline health summary",
          "focus" => "stage and owner health"
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
        "owner_mix",
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
    ])
  end

  defp plan_arguments_for_id("stuck_negotiation") do
    plan_map("stuck_negotiation", [
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
        "deal_focus_list"
      )
    ])
  end

  defp plan_arguments_for_id("quarter_compare") do
    plan_map("quarter_compare", [
      section_map(
        "quarter_trend",
        "compare_over_time",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Pipeline value by quarter"
        },
        "primary",
        "trend_panel"
      )
    ])
  end

  defp plan_arguments_for_id("enterprise_account_review") do
    plan_map("enterprise_account_review", [
      section_map(
        "enterprise_accounts",
        "rank_entities",
        %{
          "dataset" => "companies",
          "measures" => ["sum(revenue)"],
          "dimensions" => ["name"],
          "filters" => [%{"field" => "size", "op" => "=", "value" => "Enterprise"}],
          "sort" => %{"field" => "sum(revenue)", "direction" => "desc"},
          "limit" => 5,
          "title" => "Top enterprise accounts"
        },
        "primary",
        "entity_list"
      ),
      section_map(
        "largest_deals",
        "rank_entities",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["name"],
          "sort" => %{"field" => "sum(value)", "direction" => "desc"},
          "limit" => 5,
          "title" => "Largest active deals"
        },
        "focus_list",
        "deal_focus_list"
      )
    ])
  end

  defp plan_arguments_for_id("alice_focus") do
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
  end

  defp plan_arguments_for_id("open_pipeline_by_owner") do
    plan_map("open_pipeline_by_owner", [
      section_map(
        "open_owner_mix",
        "segment_population",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "filters" => [
            %{
              "field" => "stage",
              "op" => "not_in",
              "value" => ["closed_won", "closed_lost"]
            }
          ],
          "title" => "Open pipeline by owner"
        },
        "primary",
        "metric_strip"
      )
    ])
  end

  defp plan_arguments_for_id("contact_funnel") do
    plan_map("contact_funnel", [
      section_map("contact_stage_mix", "show_distribution", %{
        "dataset" => "contacts",
        "measures" => ["count(*)"],
        "dimensions" => ["stage"],
        "title" => "Contacts by stage"
      })
    ])
  end

  defp plan_arguments_for_id("no_response_activity") do
    plan_map("no_response_activity", [
      section_map("no_response_types", "show_distribution", %{
        "dataset" => "activities",
        "measures" => ["count(*)"],
        "dimensions" => ["type"],
        "filters" => [%{"field" => "outcome", "op" => "=", "value" => "no_response"}],
        "title" => "No-response activity types"
      })
    ])
  end

  defp plan_arguments_for_id("largest_deals") do
    plan_map("largest_deals", [
      section_map(
        "largest_deals",
        "rank_entities",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["name"],
          "sort" => %{"field" => "sum(value)", "direction" => "desc"},
          "limit" => 10,
          "title" => "Largest deals"
        },
        "focus_list",
        "deal_focus_list"
      )
    ])
  end

  defp plan_arguments_for_id("proposal_pipeline") do
    plan_map("proposal_pipeline", [
      section_map(
        "proposal_summary",
        "summarize_findings",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["stage"],
          "filters" => [%{"field" => "stage", "op" => "=", "value" => "proposal"}],
          "title" => "Proposal-stage pipeline summary",
          "focus" => "proposal-stage pipeline"
        },
        "summary",
        "prose_summary"
      ),
      section_map(
        "proposal_deals",
        "rank_entities",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["name"],
          "filters" => [%{"field" => "stage", "op" => "=", "value" => "proposal"}],
          "sort" => %{"field" => "sum(value)", "direction" => "desc"},
          "limit" => 10,
          "title" => "Proposal-stage deals"
        },
        "focus_list",
        "deal_focus_list"
      )
    ])
  end

  defp plan_arguments_for_id("forecast_vampires") do
    plan_map("forecast_vampires", [
      section_map(
        "forecast_risk_summary",
        "summarize_findings",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["stage"],
          "filters" => [
            %{
              "field" => "stage",
              "op" => "in",
              "value" => ["proposal", "negotiation"]
            }
          ],
          "title" => "Forecast risk summary",
          "focus" => "high-value open deals likely to create forecast risk"
        },
        "summary",
        "prose_summary"
      ),
      section_map(
        "forecast_risk_deals",
        "rank_entities",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["name"],
          "filters" => [
            %{
              "field" => "stage",
              "op" => "in",
              "value" => ["proposal", "negotiation"]
            }
          ],
          "sort" => %{"field" => "sum(value)", "direction" => "desc"},
          "limit" => 8,
          "title" => "Forecast-risk deals"
        },
        "focus_list",
        "deal_focus_list"
      ),
      section_map(
        "forecast_risk_owner_mix",
        "segment_population",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "filters" => [
            %{
              "field" => "stage",
              "op" => "in",
              "value" => ["proposal", "negotiation"]
            }
          ],
          "title" => "Forecast risk by owner"
        },
        "supporting_context",
        "metric_strip"
      )
    ])
  end

  defp plan_arguments_for_id("board_packet_dashboard") do
    plan_map("board_packet_dashboard", [
      section_map(
        "board_summary",
        "summarize_findings",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["stage"],
          "title" => "Executive pipeline summary",
          "focus" => "pipeline health, stuck revenue, and leadership attention areas"
        },
        "summary",
        "prose_summary"
      ),
      section_map("board_stage_mix", "show_distribution", %{
        "dataset" => "deals",
        "measures" => ["sum(value)"],
        "dimensions" => ["stage"],
        "title" => "Pipeline value by stage"
      }),
      section_map(
        "board_quarter_trend",
        "compare_over_time",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Pipeline value by quarter"
        },
        "primary",
        "trend_panel"
      ),
      section_map(
        "board_owner_mix",
        "segment_population",
        %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "filters" => [
            %{
              "field" => "stage",
              "op" => "not_in",
              "value" => ["closed_won", "closed_lost"]
            }
          ],
          "title" => "Open pipeline by owner"
        },
        "supporting_context",
        "metric_strip"
      ),
      section_map(
        "board_enterprise_accounts",
        "rank_entities",
        %{
          "dataset" => "companies",
          "measures" => ["sum(revenue)"],
          "dimensions" => ["name"],
          "filters" => [%{"field" => "size", "op" => "=", "value" => "Enterprise"}],
          "sort" => %{"field" => "sum(revenue)", "direction" => "desc"},
          "limit" => 5,
          "title" => "Top enterprise accounts"
        },
        "detail",
        "entity_list"
      ),
      section_map(
        "board_no_response_activity",
        "show_distribution",
        %{
          "dataset" => "activities",
          "measures" => ["count(*)"],
          "dimensions" => ["type"],
          "filters" => [%{"field" => "outcome", "op" => "=", "value" => "no_response"}],
          "title" => "No-response activity mix"
        },
        "supporting_context",
        "summary_panel"
      )
    ])
  end

  defp plan_map(goal, sections) do
    %{
      "goal" => goal,
      "title" => goal |> String.replace("_", " ") |> String.capitalize(),
      "layout" => "overview_with_detail",
      "identity" => %{"id" => "crm:#{goal}", "kind" => "planner_eval", "saveable" => true},
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
      "interactions" => ["filter", "inspect"]
    }
  end

  defmodule Provider do
    @moduledoc false
    @behaviour Resonance.LLM.Provider

    @impl true
    def chat(prompt, _tools, _opts) do
      {:ok,
       [
         %ToolCall{
           id: "plan-#{System.unique_integer([:positive])}",
           name: "create_workspace_plan",
           arguments: ResonanceDemo.PlannerEval.plan_arguments(prompt)
         }
       ]}
    end
  end

  defmodule InvalidProvider do
    @moduledoc false
    @behaviour Resonance.LLM.Provider

    @impl true
    def chat(_prompt, _tools, _opts) do
      {:ok,
       [
         %ToolCall{
           id: "invalid-plan",
           name: "create_workspace_plan",
           arguments: ResonanceDemo.PlannerEval.invalid_probability_arguments()
         }
       ]}
    end
  end
end
