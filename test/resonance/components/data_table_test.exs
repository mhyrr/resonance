defmodule Resonance.Components.DataTableTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.DataTable

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders a table with resonance-data-table class" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [%{"name" => "Alice", "age" => 30}]}
        })

      assert html =~ ~s(class="resonance-component resonance-data-table")
      assert html =~ "<table"
    end

    test "infers columns from first row keys" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [%{"name" => "Alice", "score" => 95}]}
        })

      assert html =~ "<th>name</th>"
      assert html =~ "<th>score</th>"
    end

    test "renders row data in td elements" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [%{"name" => "Alice", "score" => 95}]}
        })

      assert html =~ "<td>Alice</td>"
      assert html =~ "<td>95</td>"
    end

    test "formats float values to 2 decimal places" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [%{"value" => 3.14159}]}
        })

      assert html =~ "<td>3.14</td>"
    end

    test "renders title when provided" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [], title: "Top Accounts"}
        })

      assert html =~ "<h3"
      assert html =~ "Top Accounts"
    end

    test "omits title h3 when not provided" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: []}
        })

      refute html =~ "<h3"
    end

    test "handles empty data gracefully" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: []}
        })

      assert html =~ "<table"
      assert html =~ "<thead>"
      assert html =~ "<tbody>"
    end

    test "handles nil values in cells" do
      html =
        render_component(DataTable, %{
          renderable_id: "t-1",
          props: %{data: [%{"name" => nil}]}
        })

      assert html =~ "<td></td>"
    end
  end
end
