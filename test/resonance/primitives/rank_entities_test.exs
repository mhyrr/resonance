defmodule Resonance.Primitives.RankEntitiesTest do
  use ExUnit.Case, async: true

  alias Resonance.Primitives.RankEntities
  alias Resonance.Renderable

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Acme Corp", value: 500_000},
         %{label: "GlobalTech", value: 300_000},
         %{label: "Summit", value: 100_000}
       ]}
    end
  end

  test "intent_schema is valid" do
    schema = RankEntities.intent_schema()
    assert schema.name == "rank_entities"
    assert schema.parameters.required == ["dataset", "measures", "dimensions", "title"]
  end

  test "resolve defaults to limit 10 and desc sort" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "dimensions" => ["company"],
      "title" => "Top Deals"
    }

    assert {:ok, result} = RankEntities.resolve(params, %{resolver: MockResolver})
    assert result.intent.limit == 10
    assert result.kind == :ranking
  end

  test "default presenter picks bar chart for small datasets" do
    result = %Resonance.Result{
      kind: :ranking,
      title: "Ranked",
      data: [%{label: "A", value: 10}, %{label: "B", value: 5}]
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert %Renderable{status: :ready} = renderable
    assert renderable.component == Resonance.Components.BarChart
    assert renderable.props.orientation == "horizontal"
  end

  test "default presenter picks data table for large datasets" do
    result = %Resonance.Result{
      kind: :ranking,
      title: "Many Items",
      data: Enum.map(1..15, fn i -> %{label: "Item #{i}", value: i} end)
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert renderable.component == Resonance.Components.DataTable
  end
end
