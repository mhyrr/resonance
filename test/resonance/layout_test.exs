defmodule Resonance.LayoutTest do
  use ExUnit.Case, async: true

  alias Resonance.{Layout, Renderable}

  test "orders metrics before charts before tables before prose" do
    renderables = [
      Renderable.ready("summarize_findings", Resonance.Components.ProseSection, %{}),
      Renderable.ready("compare_over_time", Resonance.Components.LineChart, %{}),
      Renderable.ready("segment_population", Resonance.Components.MetricGrid, %{}),
      Renderable.ready("rank_entities", Resonance.Components.DataTable, %{})
    ]

    ordered = Layout.order(renderables)
    components = Enum.map(ordered, & &1.component)

    assert components == [
             Resonance.Components.MetricGrid,
             Resonance.Components.LineChart,
             Resonance.Components.DataTable,
             Resonance.Components.ProseSection
           ]
  end

  test "handles empty list" do
    assert Layout.order([]) == []
  end

  test "errors sort last" do
    renderables = [
      Renderable.error("bad", :failed),
      Renderable.ready("compare_over_time", Resonance.Components.BarChart, %{})
    ]

    ordered = Layout.order(renderables)
    assert List.last(ordered).status == :error
  end
end
