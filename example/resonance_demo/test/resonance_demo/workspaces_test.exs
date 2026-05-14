defmodule ResonanceDemo.WorkspacesTest do
  use ExUnit.Case, async: true

  alias Resonance.WorkspacePlan
  alias ResonanceDemo.Workspaces

  test "pipeline review workspace is a valid hand-written plan" do
    assert {:ok, plan} = WorkspacePlan.validate(Workspaces.pipeline_review())

    assert plan.goal == :pipeline_review
    assert plan.layout == :overview_with_detail

    assert Enum.map(plan.sections, & &1.id) == [
             "pipeline_summary",
             "stage_mix",
             "quarter_trend",
             "top_deals",
             "owner_scorecard"
           ]
  end
end
