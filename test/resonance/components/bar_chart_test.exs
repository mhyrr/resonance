defmodule Resonance.Components.BarChartTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.BarChart

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders a div with class resonance-bar-chart" do
      html = render_component(BarChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(class="resonance-component resonance-bar-chart")
    end

    test "includes phx-hook=ResonanceBarChart" do
      html = render_component(BarChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-hook="ResonanceBarChart")
    end

    test "has phx-update=ignore" do
      html = render_component(BarChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(phx-update="ignore")
    end

    test "renders title in h3 when provided" do
      html =
        render_component(BarChart, %{
          renderable_id: "test-1",
          props: %{data: [], title: "Revenue by Region"}
        })

      assert html =~ "<h3"
      assert html =~ "Revenue by Region"
    end

    test "omits h3 when no title" do
      html = render_component(BarChart, %{renderable_id: "test-1", props: %{data: []}})
      refute html =~ "<h3"
    end

    test "encodes data as JSON in data-chart-data attribute" do
      data = [%{label: "Q1", value: 100}, %{label: "Q2", value: 200}]

      html =
        render_component(BarChart, %{
          renderable_id: "test-1",
          props: %{data: data}
        })

      assert html =~ "data-chart-data="
      # The JSON should contain our values
      assert html =~ "Q1"
      assert html =~ "Q2"
    end

    test "renders correct id from renderable_id" do
      html = render_component(BarChart, %{renderable_id: "abc-123", props: %{data: []}})
      assert html =~ ~s(id="resonance-bar-abc-123")
    end

    test "passes orientation data attribute" do
      html =
        render_component(BarChart, %{
          renderable_id: "test-1",
          props: %{data: [], orientation: "horizontal"}
        })

      assert html =~ ~s(data-orientation="horizontal")
    end

    test "defaults orientation to vertical" do
      html = render_component(BarChart, %{renderable_id: "test-1", props: %{data: []}})
      assert html =~ ~s(data-orientation="vertical")
    end
  end

  describe "chart_dom_id/1" do
    test "returns prefixed id" do
      assert BarChart.chart_dom_id("abc") == "resonance-bar-abc"
    end
  end
end
