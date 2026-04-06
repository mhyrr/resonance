defmodule Resonance.Components.PieChartTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.PieChart

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders with class resonance-pie-chart" do
      html = render_component(PieChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(class="resonance-component resonance-pie-chart")
    end

    test "includes phx-hook=ResonancePieChart" do
      html = render_component(PieChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-hook="ResonancePieChart")
    end

    test "has phx-update=ignore" do
      html = render_component(PieChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-update="ignore")
    end

    test "renders title in h3 when provided" do
      html =
        render_component(PieChart, %{
          renderable_id: "test-1",
          props: %{data: [], title: "Market Share"}
        })

      assert html =~ "<h3"
      assert html =~ "Market Share"
    end

    test "passes donut option as data attribute" do
      html =
        render_component(PieChart, %{
          renderable_id: "test-1",
          props: %{data: [], donut: true}
        })

      assert html =~ ~s(data-donut="true")
    end

    test "defaults donut to false" do
      html = render_component(PieChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(data-donut="false")
    end

    test "encodes data as JSON in data-chart-data attribute" do
      data = [%{label: "A", value: 40}, %{label: "B", value: 60}]

      html =
        render_component(PieChart, %{
          renderable_id: "test-1",
          props: %{data: data}
        })

      assert html =~ "data-chart-data="
    end

    test "renders correct id from renderable_id" do
      html = render_component(PieChart, %{renderable_id: "pie-1", props: %{data: []}})
      assert html =~ ~s(id="resonance-pie-pie-1")
    end
  end

  describe "chart_dom_id/1" do
    test "returns prefixed id" do
      assert PieChart.chart_dom_id("abc") == "resonance-pie-abc"
    end
  end
end
