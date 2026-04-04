defmodule Resonance.Primitives.ShowDistributionTest do
  use ExUnit.Case, async: true

  alias Resonance.Primitives.ShowDistribution
  alias Resonance.Renderable

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Won", value: 40},
         %{label: "Lost", value: 25},
         %{label: "Open", value: 35}
       ]}
    end
  end

  test "intent_schema is valid" do
    schema = ShowDistribution.intent_schema()
    assert schema.name == "show_distribution"
  end

  test "resolve returns data from resolver" do
    params = %{
      "dataset" => "deals",
      "measures" => ["count(*)"],
      "dimensions" => ["stage"],
      "title" => "Deals by Stage"
    }

    assert {:ok, data} = ShowDistribution.resolve(params, %{resolver: MockResolver})
    assert data.title == "Deals by Stage"
    assert length(data.data) == 3
  end

  test "present picks pie chart for few categories" do
    data = %{
      data: [%{label: "A", value: 50}, %{label: "B", value: 30}, %{label: "C", value: 20}],
      title: "Distribution"
    }

    result = ShowDistribution.present(data, %{})
    assert %Renderable{status: :ready} = result
    assert result.component == Resonance.Components.PieChart
    assert result.props.donut == true
  end

  test "present picks bar chart for many categories" do
    data = %{
      data: Enum.map(1..12, fn i -> %{label: "Cat #{i}", value: i * 10} end),
      title: "Many Categories"
    }

    result = ShowDistribution.present(data, %{})
    assert result.component == Resonance.Components.BarChart
  end
end
