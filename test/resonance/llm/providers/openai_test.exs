defmodule Resonance.LLM.Providers.OpenAITest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.Providers.OpenAI
  alias Resonance.LLM.ToolCall

  @base_opts [api_key: "test-key", model: "test-model", max_tokens: 100]

  defp plug_opts(plug) do
    @base_opts ++ [req_options: [plug: plug]]
  end

  test "extracts a single tool call from successful response" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
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
        })
      )
    end

    assert {:ok, [%ToolCall{} = call]} = OpenAI.chat("test prompt", [], plug_opts(plug))
    assert call.id == "call_abc"
    assert call.name == "rank_entities"
    assert call.arguments["dataset"] == "companies"
  end

  test "extracts multiple tool calls" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [
            %{
              "message" => %{
                "tool_calls" => [
                  %{
                    "id" => "call_1",
                    "function" => %{
                      "name" => "compare_over_time",
                      "arguments" => Jason.encode!(%{"dataset" => "deals", "title" => "Trend"})
                    }
                  },
                  %{
                    "id" => "call_2",
                    "function" => %{
                      "name" => "rank_entities",
                      "arguments" => Jason.encode!(%{"dataset" => "deals", "title" => "Top"})
                    }
                  }
                ]
              }
            }
          ]
        })
      )
    end

    assert {:ok, calls} = OpenAI.chat("test", [], plug_opts(plug))
    assert length(calls) == 2
    assert Enum.at(calls, 0).name == "compare_over_time"
    assert Enum.at(calls, 1).name == "rank_entities"
  end

  test "returns empty list when response has no tool calls" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [
            %{"message" => %{"content" => "Just text, no tools."}}
          ]
        })
      )
    end

    assert {:ok, []} = OpenAI.chat("test", [], plug_opts(plug))
  end

  test "handles malformed JSON in function arguments" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [
            %{
              "message" => %{
                "tool_calls" => [
                  %{
                    "id" => "call_bad",
                    "function" => %{
                      "name" => "test_tool",
                      "arguments" => "not valid json {"
                    }
                  }
                ]
              }
            }
          ]
        })
      )
    end

    assert {:ok, [%ToolCall{name: "test_tool", arguments: args}]} =
             OpenAI.chat("test", [], plug_opts(plug))

    assert args == %{}
  end

  test "handles arguments already decoded as map" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [
            %{
              "message" => %{
                "tool_calls" => [
                  %{
                    "id" => "call_map",
                    "function" => %{
                      "name" => "rank_entities",
                      "arguments" => %{"dataset" => "deals"}
                    }
                  }
                ]
              }
            }
          ]
        })
      )
    end

    assert {:ok, [%ToolCall{arguments: %{"dataset" => "deals"}}]} =
             OpenAI.chat("test", [], plug_opts(plug))
  end

  test "returns api_error tuple on 4xx status" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        401,
        Jason.encode!(%{
          "error" => %{"message" => "Incorrect API key", "type" => "invalid_request_error"}
        })
      )
    end

    assert {:error, {:api_error, 401, body}} = OpenAI.chat("test", [], plug_opts(plug))
    assert body["error"]["type"] == "invalid_request_error"
  end

  test "returns api_error tuple on 500 status" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal"}))
    end

    assert {:error, {:api_error, 500, _body}} = OpenAI.chat("test", [], plug_opts(plug))
  end

  test "formats tools in OpenAI function-calling schema" do
    tools = [
      %{
        name: "rank_entities",
        description: "Rank things",
        parameters: %{type: "object", properties: %{dataset: %{type: "string"}}}
      }
    ]

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      [tool] = decoded["tools"]
      assert tool["type"] == "function"
      assert tool["function"]["name"] == "rank_entities"
      assert tool["function"]["parameters"]["type"] == "object"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [%{"message" => %{"content" => "ok"}}]
        })
      )
    end

    assert {:ok, []} = OpenAI.chat("test", tools, plug_opts(plug))
  end

  test "sends system message when provided" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      [sys_msg, user_msg] = decoded["messages"]
      assert sys_msg["role"] == "system"
      assert sys_msg["content"] == "You are a helpful analyst."
      assert user_msg["role"] == "user"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "choices" => [%{"message" => %{"content" => "ok"}}]
        })
      )
    end

    opts = plug_opts(plug) ++ [system: "You are a helpful analyst."]
    assert {:ok, []} = OpenAI.chat("test", [], opts)
  end
end
