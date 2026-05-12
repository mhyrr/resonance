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
          required(:diagnostics) => map(),
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

    invented_capability_failures =
      Enum.count(results, &get_in(&1, [:diagnostics, :invented_capability?]))

    invented_pattern_failures =
      Enum.count(results, &get_in(&1, [:diagnostics, :invented_pattern?]))

    invented_primitive_failures =
      Enum.count(results, &get_in(&1, [:diagnostics, :invented_primitive?]))

    %{
      total: total,
      valid_plans: compiled + compile_failed,
      compiled: compiled,
      invalid_plans: invalid,
      compile_failed: compile_failed,
      retried: retried,
      recovered: recovered,
      invented_capability_failures: invented_capability_failures,
      invented_pattern_failures: invented_pattern_failures,
      invented_primitive_failures: invented_primitive_failures,
      valid_plan_rate: rate(compiled + compile_failed, total),
      compile_rate: rate(compiled, total)
    }
  end

  defp evaluate_one(prompt, context, opts) do
    case Planner.plan_result(prompt, context, opts) do
      {:ok, %{plan: plan} = planner_result} ->
        case WorkspaceCompiler.compile(plan, context) do
          {:ok, compiled} ->
            case renderable_errors(compiled) do
              [] ->
                %{
                  prompt: prompt,
                  status: :compiled,
                  plan: plan,
                  compiled: compiled,
                  attempts: planner_result.attempts,
                  retried?: planner_result.retried?,
                  recovered?: planner_result.recovered?,
                  diagnostics: plan_diagnostics(plan, nil)
                }

              errors ->
                reason = {:renderable_errors, errors}

                %{
                  prompt: prompt,
                  status: :compile_failed,
                  plan: plan,
                  compiled: compiled,
                  errors: reason,
                  attempts: planner_result.attempts,
                  retried?: planner_result.retried?,
                  recovered?: false,
                  diagnostics: plan_diagnostics(plan, reason)
                }
            end

          {:error, reason} ->
            %{
              prompt: prompt,
              status: :compile_failed,
              plan: plan,
              errors: reason,
              attempts: planner_result.attempts,
              retried?: planner_result.retried?,
              recovered?: false,
              diagnostics: plan_diagnostics(plan, reason)
            }
        end

      {:error, planner_result} ->
        %{
          prompt: prompt,
          status: :invalid_plan,
          errors: planner_result.reason,
          attempts: planner_result.attempts,
          retried?: planner_result.retried?,
          recovered?: false,
          diagnostics: plan_diagnostics(nil, planner_result.reason)
        }
    end
  end

  defp plan_diagnostics(nil, errors) do
    validation_errors = validation_errors(errors)

    %{
      section_count: 0,
      primitives: [],
      patterns: [],
      invented_capability?: error_code?(validation_errors, capability_error_codes()),
      invented_pattern?: error_code?(validation_errors, pattern_error_codes()),
      invented_primitive?: error_code?(validation_errors, [:unknown_primitive]),
      validation_error_codes: Enum.map(validation_errors, & &1.code)
    }
  end

  defp plan_diagnostics(plan, errors) do
    validation_errors = validation_errors(errors)
    sections = plan.sections || []

    %{
      section_count: length(sections),
      primitives:
        sections |> Enum.map(&section_primitive/1) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      patterns: sections |> Enum.map(& &1.pattern) |> Enum.reject(&is_nil/1) |> Enum.uniq(),
      invented_capability?: error_code?(validation_errors, capability_error_codes()),
      invented_pattern?: error_code?(validation_errors, pattern_error_codes()),
      invented_primitive?: error_code?(validation_errors, [:unknown_primitive]),
      validation_error_codes: Enum.map(validation_errors, & &1.code)
    }
  end

  defp validation_errors({:validation_failed, errors}) when is_list(errors), do: errors

  defp validation_errors({:renderable_errors, errors}) when is_list(errors) do
    Enum.flat_map(errors, fn
      %{error: {:validation_failed, validation_errors}} when is_list(validation_errors) ->
        validation_errors

      _error ->
        []
    end)
  end

  defp validation_errors(_errors), do: []

  defp renderable_errors(%{sections: sections}) when is_list(sections) do
    Enum.flat_map(sections, fn
      %{id: id, renderable: %{status: :error, error: error}} ->
        [%{section_id: id, error: error}]

      _section ->
        []
    end)
  end

  defp renderable_errors(_compiled), do: []

  defp error_code?(errors, codes), do: Enum.any?(errors, &(&1.code in codes))

  defp capability_error_codes do
    [
      :unknown_dataset,
      :unsupported_measure,
      :unsupported_dimension,
      :unsupported_filter,
      :unsupported_filter_op,
      :unsupported_sort_field,
      :unsupported_query_shape
    ]
  end

  defp pattern_error_codes do
    [
      :unsupported_pattern,
      :incompatible_pattern_role,
      :incompatible_pattern_source
    ]
  end

  defp section_primitive(%{source: {:tool_call, %{name: name}}}), do: name
  defp section_primitive(_section), do: nil

  defp rate(_numerator, 0), do: 0.0
  defp rate(numerator, denominator), do: Float.round(numerator / denominator, 3)
end
