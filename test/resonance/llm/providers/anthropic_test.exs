defmodule Resonance.LLM.Providers.AnthropicTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.Providers.Anthropic
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
          "content" => [
            %{
              "type" => "tool_use",
              "id" => "toolu_123",
              "name" => "rank_entities",
              "input" => %{
                "dataset" => "deals",
                "measures" => ["count(*)"],
                "dimensions" => ["stage"],
                "title" => "Deals by Stage"
              }
            }
          ]
        })
      )
    end

    assert {:ok, [%ToolCall{} = call]} = Anthropic.chat("test prompt", [], plug_opts(plug))
    assert call.id == "toolu_123"
    assert call.name == "rank_entities"
    assert call.arguments["dataset"] == "deals"
    assert call.arguments["measures"] == ["count(*)"]
  end

  test "extracts multiple tool calls" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "content" => [
            %{"type" => "text", "text" => "I'll analyze that for you."},
            %{
              "type" => "tool_use",
              "id" => "toolu_1",
              "name" => "compare_over_time",
              "input" => %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "dimensions" => ["quarter"],
                "title" => "Q Trend"
              }
            },
            %{
              "type" => "tool_use",
              "id" => "toolu_2",
              "name" => "summarize_findings",
              "input" => %{
                "dataset" => "deals",
                "measures" => ["sum(value)"],
                "title" => "Summary"
              }
            }
          ]
        })
      )
    end

    assert {:ok, calls} = Anthropic.chat("test", [], plug_opts(plug))
    assert length(calls) == 2
    assert Enum.at(calls, 0).name == "compare_over_time"
    assert Enum.at(calls, 1).name == "summarize_findings"
  end

  test "returns empty list when response has no tool calls" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "content" => [
            %{"type" => "text", "text" => "No tools needed."}
          ]
        })
      )
    end

    assert {:ok, []} = Anthropic.chat("test", [], plug_opts(plug))
  end

  test "returns api_error tuple on 4xx status" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        401,
        Jason.encode!(%{
          "error" => %{"type" => "authentication_error", "message" => "invalid x-api-key"}
        })
      )
    end

    assert {:error, {:api_error, 401, body}} = Anthropic.chat("test", [], plug_opts(plug))
    assert body["error"]["type"] == "authentication_error"
  end

  test "returns api_error tuple on 500 status" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(500, Jason.encode!(%{"error" => "internal"}))
    end

    assert {:error, {:api_error, 500, _body}} = Anthropic.chat("test", [], plug_opts(plug))
  end

  test "formats tools in Anthropic schema with input_schema" do
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

      # Verify tool formatting
      [tool] = decoded["tools"]
      assert tool["name"] == "rank_entities"
      assert tool["input_schema"]["type"] == "object"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => []}))
    end

    assert {:ok, []} = Anthropic.chat("test", tools, plug_opts(plug))
  end

  test "sends system prompt when provided" do
    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["system"] == "You are a helpful analyst."

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"content" => []}))
    end

    opts = plug_opts(plug) ++ [system: "You are a helpful analyst."]
    assert {:ok, []} = Anthropic.chat("test", [], opts)
  end

  test "tool call with empty input returns empty map for arguments" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "content" => [
            %{"type" => "tool_use", "id" => "toolu_x", "name" => "summarize_findings"}
          ]
        })
      )
    end

    assert {:ok, [%ToolCall{arguments: args}]} = Anthropic.chat("test", [], plug_opts(plug))
    assert args == %{}
  end
end
