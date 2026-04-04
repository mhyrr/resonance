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

  test "resolve returns Result with kind :segmentation" do
    params = %{
      "dataset" => "contacts",
      "measures" => ["count(*)"],
      "dimensions" => ["stage"],
      "title" => "Contacts by Stage"
    }

    assert {:ok, result} = SegmentPopulation.resolve(params, %{resolver: SmallResolver})
    assert result.kind == :segmentation
  end

  test "default presenter picks metric grid for few segments" do
    result = %Resonance.Result{
      kind: :segmentation,
      title: "Small",
      data: [%{label: "A", value: 10}, %{label: "B", value: 20}]
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert %Renderable{status: :ready} = renderable
    assert renderable.component == Resonance.Components.MetricGrid
  end

  test "default presenter picks data table for many segments" do
    result = %Resonance.Result{
      kind: :segmentation,
      title: "Large",
      data: Enum.map(1..10, fn i -> %{label: "S#{i}", value: i} end)
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert renderable.component == Resonance.Components.DataTable
  end
end
