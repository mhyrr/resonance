defmodule Resonance.Components.ErrorDisplayTest do
  use ExUnit.Case, async: true

  alias Resonance.Components.ErrorDisplay

  defp render_component(component_module, assigns) do
    assigns = Map.put(assigns, :__changed__, nil)

    component_module.render(assigns)
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  describe "render/1" do
    test "renders error message" do
      html = render_component(ErrorDisplay, %{error: "Something went wrong"})
      assert html =~ "Something went wrong"
    end

    test "has class resonance-error" do
      html = render_component(ErrorDisplay, %{error: "oops"})
      assert html =~ ~s(class="resonance-component resonance-error")
    end

    test "renders error message paragraph" do
      html = render_component(ErrorDisplay, %{error: "timeout"})
      assert html =~ ~s(class="resonance-error-message")
      assert html =~ "Failed to load component"
    end

    test "inspects non-string error values" do
      html = render_component(ErrorDisplay, %{error: {:error, :not_found}})
      assert html =~ "{:error, :not_found}"
    end
  end
end
