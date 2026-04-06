defmodule Resonance.Components.MetricGridTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.MetricGrid

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders grid with resonance-metric-grid class" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{
            metrics: [
              %{label: "Revenue", value: 1000},
              %{label: "Users", value: 50}
            ]
          }
        })

      assert html =~ ~s(class="resonance-component resonance-metric-grid")
    end

    test "renders multiple metrics" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{
            metrics: [
              %{label: "Revenue", value: 1000},
              %{label: "Users", value: 50}
            ]
          }
        })

      assert html =~ "Revenue"
      assert html =~ "Users"
      assert html =~ "1,000"
      assert html =~ "50"
    end

    test "renders title when provided" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{title: "Key Metrics", metrics: []}
        })

      assert html =~ "<h3"
      assert html =~ "Key Metrics"
    end

    test "omits title when not provided" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{metrics: []}
        })

      refute html =~ "<h3"
    end

    test "handles columns prop in grid style" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{metrics: [], columns: 4}
        })

      assert html =~ "repeat(4, 1fr)"
    end

    test "defaults to 3 columns" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{metrics: []}
        })

      assert html =~ "repeat(3, 1fr)"
    end

    test "formats currency values" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{
            metrics: [%{label: "Revenue", value: 2500, format: "currency"}]
          }
        })

      assert html =~ "$2,500"
    end

    test "handles empty metrics list" do
      html =
        render_component(MetricGrid, %{
          renderable_id: "g-1",
          props: %{metrics: []}
        })

      assert html =~ "resonance-grid"
    end
  end
end
