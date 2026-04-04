defmodule Resonance.LLM.Provider do
  @moduledoc """
  Behaviour for LLM providers.

  Resonance ships with Anthropic and OpenAI providers. Implement this
  behaviour to add support for other providers.
  """

  @doc """
  Send a prompt with tool schemas to the LLM and return normalized tool calls.

  `tools` is a list of tool schema maps from `Resonance.Registry.all_schemas/0`.
  `opts` comes from application config (api_key, model, max_tokens, etc.).
  """
  @callback chat(prompt :: String.t(), tools :: [map()], opts :: keyword()) ::
              {:ok, [Resonance.LLM.ToolCall.t()]} | {:error, term()}
end
