defmodule Resonance.Planner.Eval do
  @moduledoc """
  Small evaluation harness for planner-mode prompts.

  This is intentionally ordinary Elixir: pass prompts, a context with a
  resolver, and a provider configured at the normal provider boundary. The
  harness measures whether the planner returned a valid plan and whether each
  valid plan compiles through the deterministic workspace compiler.
  """

  alias Resonance.{Planner, WorkspaceCompiler}

  @type result :: %{
          required(:prompt) => String.t(),
          required(:status) => :compiled | :invalid_plan | :compile_failed,
          required(:attempts) => non_neg_integer(),
          required(:retried?) => boolean(),
          required(:recovered?) => boolean(),
          optional(:plan) => Resonance.WorkspacePlan.t(),
          optional(:compiled) => WorkspaceCompiler.compiled_workspace(),
          optional(:errors) => term()
        }

  @doc """
  Evaluate a list of prompts.
  """
  @spec evaluate([String.t()], map(), keyword()) :: %{results: [result()], summary: map()}
  def evaluate(prompts, context, opts \\ []) when is_list(prompts) and is_map(context) do
    results = Enum.map(prompts, &evaluate_one(&1, context, opts))

    %{
      results: results,
      summary: summary(results)
    }
  end

  @doc """
  Summarize validity and compile rate for evaluation output.
  """
  @spec summary([result()]) :: map()
  def summary(results) do
    total = length(results)
    compiled = Enum.count(results, &(&1.status == :compiled))
    invalid = Enum.count(results, &(&1.status == :invalid_plan))
    compile_failed = Enum.count(results, &(&1.status == :compile_failed))
    retried = Enum.count(results, & &1.retried?)
    recovered = Enum.count(results, & &1.recovered?)

    %{
      total: total,
      valid_plans: compiled + compile_failed,
      compiled: compiled,
      invalid_plans: invalid,
      compile_failed: compile_failed,
      retried: retried,
      recovered: recovered,
      valid_plan_rate: rate(compiled + compile_failed, total),
      compile_rate: rate(compiled, total)
    }
  end

  defp evaluate_one(prompt, context, opts) do
    case Planner.plan_result(prompt, context, opts) do
      {:ok, %{plan: plan} = planner_result} ->
        case WorkspaceCompiler.compile(plan, context) do
          {:ok, compiled} ->
            %{
              prompt: prompt,
              status: :compiled,
              plan: plan,
              compiled: compiled,
              attempts: planner_result.attempts,
              retried?: planner_result.retried?,
              recovered?: planner_result.recovered?
            }

          {:error, reason} ->
            %{
              prompt: prompt,
              status: :compile_failed,
              plan: plan,
              errors: reason,
              attempts: planner_result.attempts,
              retried?: planner_result.retried?,
              recovered?: false
            }
        end

      {:error, planner_result} ->
        %{
          prompt: prompt,
          status: :invalid_plan,
          errors: planner_result.reason,
          attempts: planner_result.attempts,
          retried?: planner_result.retried?,
          recovered?: false
        }
    end
  end

  defp rate(_numerator, 0), do: 0.0
  defp rate(numerator, denominator), do: Float.round(numerator / denominator, 3)
end
