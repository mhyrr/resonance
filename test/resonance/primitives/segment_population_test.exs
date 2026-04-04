defmodule Resonance.Primitives.SegmentPopulationTest do
  use ExUnit.Case, async: true

  alias Resonance.Primitives.SegmentPopulation
  alias Resonance.Renderable

  defmodule SmallResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Lead", value: 45},
         %{label: "Qualified", value: 30},
         %{label: "Customer", value: 25}
       ]}
    end
  end

  defmodule LargeResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok, Enum.map(1..10, fn i -> %{label: "Segment #{i}", value: i * 10} end)}
    end
  end

  test "intent_schema is valid" do
    schema = SegmentPopulation.intent_schema()
    assert schema.name == "segment_population"
  end

  test "resolve returns segmented data" do
    params = %{
      "dataset" => "contacts",
      "measures" => ["count(*)"],
      "dimensions" => ["stage"],
      "title" => "Contacts by Stage"
    }

    assert {:ok, data} = SegmentPopulation.resolve(params, %{resolver: SmallResolver})
    assert length(data.data) == 3
  end

  test "present picks metric grid for few segments" do
    data = %{
      data: [%{label: "A", value: 10}, %{label: "B", value: 20}],
      title: "Small",
      intent: %Resonance.QueryIntent{dataset: "x", measures: ["count(*)"]}
    }

    result = SegmentPopulation.present(data, %{})
    assert %Renderable{status: :ready} = result
    assert result.component == Resonance.Components.MetricGrid
  end

  test "present picks data table for many segments" do
    data = %{
      data: Enum.map(1..10, fn i -> %{label: "S#{i}", value: i} end),
      title: "Large",
      intent: %Resonance.QueryIntent{dataset: "x", measures: ["count(*)"]}
    }

    result = SegmentPopulation.present(data, %{})
    assert result.component == Resonance.Components.DataTable
  end
end
