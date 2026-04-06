defmodule Resonance.Components.MetricCardTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.MetricCard

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders with class resonance-metric-card" do
      html = render_component(MetricCard, %{renderable_id: "m-1", props: %{value: 42}})
      assert html =~ ~s(class="resonance-component resonance-metric-card")
    end

    test "shows label" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{label: "Total Revenue", value: 100}
        })

      assert html =~ "Total Revenue"
      assert html =~ ~s(class="resonance-metric-label")
    end

    test "shows formatted integer value" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 5000}
        })

      assert html =~ "5.0K"
    end

    test "shows formatted float value" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 3.14159}
        })

      assert html =~ "3.14"
    end

    test "shows dash for nil value" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: nil}
        })

      assert html =~ ~s(class="resonance-metric-value">-)
    end

    test "formats currency when format is currency" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 1500, format: "currency"}
        })

      assert html =~ "$1,500"
    end

    test "formats percent when format is percent" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 0.856, format: "percent"}
        })

      assert html =~ "85.6%"
    end

    test "computes upward trend when comparison_value provided and current is higher" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 120, comparison_value: 100}
        })

      assert html =~ "resonance-trend-up"
      assert html =~ "20.0%"
    end

    test "computes downward trend when current is lower" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 80, comparison_value: 100}
        })

      assert html =~ "resonance-trend-down"
      assert html =~ "20.0%"
    end

    test "shows flat trend when values are equal" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 100, comparison_value: 100}
        })

      assert html =~ "resonance-trend-flat"
      assert html =~ "0.0%"
    end

    test "omits trend when no comparison_value" do
      html =
        render_component(MetricCard, %{
          renderable_id: "m-1",
          props: %{value: 100}
        })

      refute html =~ "resonance-metric-trend"
    end
  end
end
