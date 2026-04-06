defmodule Resonance.Components.LineChartTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.LineChart

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders with class resonance-line-chart" do
      html = render_component(LineChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(class="resonance-component resonance-line-chart")
    end

    test "includes phx-hook=ResonanceLineChart" do
      html = render_component(LineChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-hook="ResonanceLineChart")
    end

    test "has phx-update=ignore" do
      html = render_component(LineChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-update="ignore")
    end

    test "renders title in h3 when provided" do
      html =
        render_component(LineChart, %{
          renderable_id: "test-1",
          props: %{data: [], title: "Trend Over Time"}
        })

      assert html =~ "<h3"
      assert html =~ "Trend Over Time"
    end

    test "handles multi_series flag in data attribute" do
      html =
        render_component(LineChart, %{
          renderable_id: "test-1",
          props: %{data: [], multi_series: true}
        })

      assert html =~ ~s(data-multi-series="true")
    end

    test "defaults multi_series to false" do
      html = render_component(LineChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(data-multi-series="false")
    end

    test "encodes data as JSON in data-chart-data attribute" do
      data = [%{x: "Jan", y: 10}, %{x: "Feb", y: 20}]

      html =
        render_component(LineChart, %{
          renderable_id: "test-1",
          props: %{data: data}
        })

      assert html =~ "data-chart-data="
      assert html =~ "Jan"
    end

    test "renders correct id from renderable_id" do
      html = render_component(LineChart, %{renderable_id: "xyz", props: %{data: []}})
      assert html =~ ~s(id="resonance-line-xyz")
    end
  end

  describe "chart_dom_id/1" do
    test "returns prefixed id" do
      assert LineChart.chart_dom_id("abc") == "resonance-line-abc"
    end
  end
end
