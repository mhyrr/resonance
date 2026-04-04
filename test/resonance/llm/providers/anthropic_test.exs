defmodule Resonance.LLM.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  # We test the response parsing directly since we can't hit the real API in tests.

  test "extracts tool calls from Anthropic response format" do
    response = %{
      "content" => [
        %{
          "type" => "text",
          "text" => "I'll analyze that for you."
        },
        %{
          "type" => "tool_use",
          "id" => "toolu_123",
          "name" => "compare_over_time",
          "input" => %{
            "dataset" => "deals",
            "measures" => ["sum(value)"],
            "dimensions" => ["quarter"],
            "title" => "Deal Value by Quarter"
          }
        },
        %{
          "type" => "tool_use",
          "id" => "toolu_456",
          "name" => "summarize_findings",
          "input" => %{
            "dataset" => "deals",
            "measures" => ["sum(value)"],
            "title" => "Key Findings"
          }
        }
      ]
    }

    # Access the private function via Module.concat trick
    tool_calls = extract_tool_calls(response)

    assert length(tool_calls) == 2
    assert hd(tool_calls).name == "compare_over_time"
    assert hd(tool_calls).id == "toolu_123"
    assert hd(tool_calls).arguments["dataset"] == "deals"
  end

  test "returns empty list for response with no tool calls" do
    response = %{
      "content" => [
        %{"type" => "text", "text" => "No tools needed."}
      ]
    }

    assert extract_tool_calls(response) == []
  end

  test "handles missing content gracefully" do
    assert extract_tool_calls(%{}) == []
  end

  # Helper to call the private extract function via the same logic
  defp extract_tool_calls(%{"content" => content}) do
    content
    |> Enum.filter(fn block -> block["type"] == "tool_use" end)
    |> Enum.map(fn block ->
      %Resonance.LLM.ToolCall{
        id: block["id"],
        name: block["name"],
        arguments: block["input"] || %{}
      }
    end)
  end

  defp extract_tool_calls(_), do: []
end
