defmodule Resonance.ComposerTest do
  use ExUnit.Case, async: true

  alias Resonance.{Composer, Renderable}

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Q1", value: 100},
         %{label: "Q2", value: 150},
         %{label: "Q3", value: 200}
       ]}
    end
  end

  setup do
    # Ensure the default registry has primitives registered
    # (Application.start handles this, but be explicit for test isolation)
    :ok
  end

  test "compose resolves tool calls into renderables" do
    tool_calls = [
      %Resonance.LLM.ToolCall{
        id: "call_1",
        name: "compare_over_time",
        arguments: %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Deal Value by Quarter"
        }
      }
    ]

    context = %{resolver: MockResolver}

    assert {:ok, [%Renderable{status: :ready} = renderable]} =
             Composer.compose(tool_calls, context)

    assert renderable.type == "compare_over_time"
    assert renderable.props.title == "Deal Value by Quarter"
  end

  test "compose handles unknown primitives gracefully" do
    tool_calls = [
      %Resonance.LLM.ToolCall{
        id: "call_1",
        name: "nonexistent_primitive",
        arguments: %{}
      }
    ]

    assert {:ok, [%Renderable{status: :error}]} = Composer.compose(tool_calls, %{})
  end

  test "compose handles resolver errors" do
    defmodule FailingResolver do
      @behaviour Resonance.Resolver

      @impl true
      def resolve(_intent, _context), do: {:error, :database_down}
    end

    tool_calls = [
      %Resonance.LLM.ToolCall{
        id: "call_1",
        name: "compare_over_time",
        arguments: %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Test"
        }
      }
    ]

    assert {:ok, [%Renderable{status: :error, error: :database_down}]} =
             Composer.compose(tool_calls, %{resolver: FailingResolver})
  end

  test "compose_stream sends components and done message" do
    tool_calls = [
      %Resonance.LLM.ToolCall{
        id: "call_1",
        name: "compare_over_time",
        arguments: %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Streamed"
        }
      }
    ]

    context = %{resolver: MockResolver}
    assert :ok = Composer.compose_stream(tool_calls, context, self())

    assert_receive {:resonance, {:component_ready, %Renderable{status: :ready}}}, 5000
    assert_receive {:resonance, :done}, 5000
  end
end
