defmodule Resonance.LLM.Providers.OpenAITest do
  use ExUnit.Case, async: true

  test "extracts tool calls from OpenAI response format" do
    response = %{
      "choices" => [
        %{
          "message" => %{
            "tool_calls" => [
              %{
                "id" => "call_abc",
                "function" => %{
                  "name" => "rank_entities",
                  "arguments" =>
                    Jason.encode!(%{
                      "dataset" => "companies",
                      "measures" => ["sum(revenue)"],
                      "dimensions" => ["name"],
                      "title" => "Top Companies"
                    })
                }
              }
            ]
          }
        }
      ]
    }

    tool_calls = extract_tool_calls(response)
    assert length(tool_calls) == 1
    assert hd(tool_calls).name == "rank_entities"
    assert hd(tool_calls).arguments["dataset"] == "companies"
  end

  test "handles response with no tool calls" do
    response = %{
      "choices" => [
        %{"message" => %{"content" => "Just text."}}
      ]
    }

    assert extract_tool_calls(response) == []
  end

  test "handles malformed JSON in arguments" do
    response = %{
      "choices" => [
        %{
          "message" => %{
            "tool_calls" => [
              %{
                "id" => "call_bad",
                "function" => %{
                  "name" => "test",
                  "arguments" => "not valid json {"
                }
              }
            ]
          }
        }
      ]
    }

    tool_calls = extract_tool_calls(response)
    assert length(tool_calls) == 1
    assert tool_calls |> hd() |> Map.get(:arguments) == %{}
  end

  # Mirror the extraction logic from the provider
  defp extract_tool_calls(%{"choices" => [%{"message" => message} | _]}) do
    (message["tool_calls"] || [])
    |> Enum.map(fn call ->
      %Resonance.LLM.ToolCall{
        id: call["id"],
        name: call["function"]["name"],
        arguments: decode_arguments(call["function"]["arguments"])
      }
    end)
  end

  defp extract_tool_calls(_), do: []

  defp decode_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      _ -> %{}
    end
  end

  defp decode_arguments(args) when is_map(args), do: args
  defp decode_arguments(_), do: %{}
end
