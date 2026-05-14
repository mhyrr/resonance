defmodule ResonanceDemo.PlannerEvalTest do
  use ResonanceDemo.DataCase, async: false

  alias Resonance.Planner.Eval
  alias ResonanceDemo.PlannerEval

  test "evaluates the golden CRM prompts through planner validation and compiler" do
    evaluation = PlannerEval.evaluate()

    assert evaluation.summary.total == 12
    assert evaluation.summary.valid_plans == 12
    assert evaluation.summary.compiled == 12
    assert evaluation.summary.invalid_plans == 0
    assert evaluation.summary.compile_failed == 0
    assert evaluation.summary.invented_capability_failures == 0
    assert evaluation.summary.invented_pattern_failures == 0
    assert evaluation.summary.invented_primitive_failures == 0
    assert evaluation.summary.compile_rate == 1.0

    assert Enum.map(evaluation.results, & &1.id) == Enum.map(PlannerEval.prompts(), & &1.id)
    assert Enum.all?(evaluation.results, &(&1.status == :compiled))
    assert Enum.all?(evaluation.results, &(&1.diagnostics.section_count > 0))

    assert Enum.find(evaluation.results, &(&1.id == "forecast_vampires")).diagnostics.section_count ==
             3

    assert Enum.find(evaluation.results, &(&1.id == "board_packet_dashboard")).diagnostics.section_count ==
             6
  end

  test "exposes actionable validation diagnostics for invented CRM fields" do
    evaluation =
      Eval.evaluate(["Show deal probability by owner."], PlannerEval.context(),
        provider: PlannerEval.InvalidProvider,
        max_validation_retries: 0
      )

    assert evaluation.summary.invalid_plans == 1
    assert evaluation.summary.invented_capability_failures == 1

    [result] = evaluation.results
    assert result.status == :invalid_plan
    assert result.diagnostics.invented_capability?
    assert :unsupported_measure in result.diagnostics.validation_error_codes
    assert {:validation_failed, errors} = result.errors
    assert Enum.any?(errors, &(&1.message =~ "measure is not declared"))
  end

  test "real-provider entrypoint can run with an explicit provider override" do
    evaluation =
      PlannerEval.evaluate_real(
        provider: PlannerEval.Provider,
        prompts: [hd(PlannerEval.prompts())]
      )

    assert evaluation.summary.total == 1
    assert evaluation.summary.compiled == 1
    [result] = evaluation.results
    assert result.id == "pipeline_health"
    assert result.status == :compiled
  end
end
