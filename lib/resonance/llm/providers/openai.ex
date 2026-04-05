defmodule Resonance.LLM.Providers.OpenAI do
  @moduledoc """
  OpenAI provider for Resonance.
  """

  @behaviour Resonance.LLM.Provider

  @api_url "https://api.openai.com/v1/chat/completions"

  @impl true
  def chat(prompt, tools, opts) do
    api_key = Keyword.fetch!(opts, :api_key)
    model = Keyword.fetch!(opts, :model)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    system = Keyword.get(opts, :system)

    messages =
      case system do
        nil -> [%{role: "user", content: prompt}]
        sys -> [%{role: "system", content: sys}, %{role: "user", content: prompt}]
      end

    body = %{
      model: model,
      max_tokens: max_tokens,
      tools: format_tools(tools),
      messages: messages
    }

    headers = [
      {"authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"}
    ]

    req_options = Keyword.get(opts, :req_options, [])

    case Req.post(
           @api_url,
           [json: body, headers: headers, receive_timeout: 60_000] ++ req_options
         ) do
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
        type: "function",
        function: %{
          name: tool[:name] || tool["name"],
          description: tool[:description] || tool["description"],
          parameters: tool[:parameters] || tool["parameters"] || %{}
        }
      }
    end)
  end

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
