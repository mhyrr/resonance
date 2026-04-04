defmodule Resonance.LLM.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude provider for Resonance.
  """

  @behaviour Resonance.LLM.Provider

  @api_url "https://api.anthropic.com/v1/messages"

  @impl true
  def chat(prompt, tools, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.fetch!(opts, :model)
    max_tokens = Keyword.fetch!(opts, :max_tokens)

    system = Keyword.get(opts, :system)

    body =
      %{
        model: model,
        max_tokens: max_tokens,
        tools: format_tools(tools),
        messages: [
          %{role: "user", content: prompt}
        ]
      }
      |> maybe_put(:system, system)

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, extract_tool_calls(response_body)}

      {:ok, %{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp format_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        name: tool[:name] || tool["name"],
        description: tool[:description] || tool["description"],
        input_schema: format_input_schema(tool[:parameters] || tool["parameters"])
      }
    end)
  end

  defp format_input_schema(params) when is_map(params), do: params
  defp format_input_schema(_), do: %{type: "object", properties: %{}}

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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
