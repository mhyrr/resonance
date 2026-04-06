defmodule Resonance.WidgetTest do
  use ExUnit.Case, async: true

  alias Resonance.Renderable
  alias Resonance.Widget

  defmodule MinimalWidget do
    use Resonance.Widget

    @impl Resonance.Widget
    def accepts_results, do: [:ranking]

    @impl Phoenix.LiveComponent
    def update(assigns, socket), do: {:ok, Phoenix.Component.assign(socket, assigns)}

    @impl Phoenix.LiveComponent
    def render(assigns) do
      ~H"<div>minimal</div>"
    end
  end

  defmodule FullWidget do
    use Resonance.Widget

    @impl Resonance.Widget
    def accepts_results, do: [:comparison, :ranking]

    @impl Resonance.Widget
    def capabilities, do: [:refine, :drilldown]

    @impl Resonance.Widget
    def example_renderable do
      %Renderable{
        id: "example",
        type: "comparison",
        component: __MODULE__,
        props: %{title: "Example"},
        status: :ready
      }
    end

    @impl Phoenix.LiveComponent
    def update(assigns, socket), do: {:ok, Phoenix.Component.assign(socket, assigns)}

    @impl Phoenix.LiveComponent
    def render(assigns) do
      ~H"<div>full</div>"
    end
  end

  defmodule NotAWidget do
    @moduledoc false
    def hello, do: :world
  end

  describe "use Resonance.Widget" do
    test "pulls in Phoenix.LiveComponent and the Widget behaviour" do
      behaviours =
        MinimalWidget.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Phoenix.LiveComponent in behaviours
      assert Resonance.Widget in behaviours
    end
  end

  describe "accepts_results/1" do
    test "returns the kinds declared by the widget" do
      assert Widget.accepts_results(MinimalWidget) == [:ranking]
      assert Widget.accepts_results(FullWidget) == [:comparison, :ranking]
    end
  end

  describe "capabilities/1" do
    test "returns [] when the optional callback is not implemented" do
      assert Widget.capabilities(MinimalWidget) == []
    end

    test "returns the declared capabilities when implemented" do
      assert Widget.capabilities(FullWidget) == [:refine, :drilldown]
    end
  end

  describe "example_renderable/1" do
    test "returns :error when the optional callback is not implemented" do
      assert Widget.example_renderable(MinimalWidget) == :error
    end

    test "returns {:ok, renderable} when implemented" do
      assert {:ok, %Renderable{id: "example", type: "comparison"}} =
               Widget.example_renderable(FullWidget)
    end
  end

  describe "widget?/1" do
    test "returns true for modules using Resonance.Widget" do
      assert Widget.widget?(MinimalWidget)
      assert Widget.widget?(FullWidget)
    end

    test "returns false for unrelated modules" do
      refute Widget.widget?(NotAWidget)
      refute Widget.widget?(Resonance.Renderable)
      refute Widget.widget?(String)
    end

    test "returns false for non-existent modules" do
      refute Widget.widget?(NonExistent.Module)
    end
  end
end
