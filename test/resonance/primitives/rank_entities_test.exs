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

    assert {:ok, data} = RankEntities.resolve(params, %{resolver: MockResolver})
    assert data.limit == 10
  end

  test "present picks bar chart for small datasets" do
    data = %{
      data: [%{label: "A", value: 10}, %{label: "B", value: 5}],
      title: "Ranked",
      limit: 10
    }

    result = RankEntities.present(data, %{})
    assert %Renderable{status: :ready} = result
    assert result.component == Resonance.Components.BarChart
    assert result.props.orientation == "horizontal"
  end

  test "present picks data table for large datasets" do
    data = %{
      data: Enum.map(1..15, fn i -> %{label: "Item #{i}", value: i} end),
      title: "Many Items",
      limit: 25
    }

    result = RankEntities.present(data, %{})
    assert result.component == Resonance.Components.DataTable
  end
end
