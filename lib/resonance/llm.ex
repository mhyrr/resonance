defmodule Resonance.LLM do
  @moduledoc """
  Internal LLM client. Reads application config and delegates to the
  configured provider.

  ## Configuration

      config :resonance,
        provider: :anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        model: "claude-sonnet-4-5",
        max_tokens: 4096

  Supported providers: `:anthropic`, `:openai`, or a module implementing
  `Resonance.LLM.Provider`.
  """

  @providers %{
    anthropic: Resonance.LLM.Providers.Anthropic,
    openai: Resonance.LLM.Providers.OpenAI
  }

  @doc """
  Call the configured LLM with a prompt and tool schemas.

  Returns `{:ok, [%ToolCall{}]}` or `{:error, reason}`.
  """
  @spec chat(String.t(), [map()], map()) :: {:ok, [Resonance.LLM.ToolCall.t()]} | {:error, term()}
  def chat(prompt, tools, context \\ %{}) do
    config = Application.get_all_env(:resonance)
    provider = resolve_provider(config[:provider])

    system_prompt = build_system_prompt(context)
    opts = config |> Keyword.drop([:provider]) |> Keyword.put(:system, system_prompt)

    provider.chat(prompt, tools, opts)
  end

  @doc false
  def build_system_prompt(context) do
    resolver = context[:resolver]

    base = """
    You are a data analysis assistant. The user will ask questions about their data.
    Select the appropriate semantic primitives (tools) to answer their question.

    CRITICAL RULES — violations will cause query failures:
    1. Use ONLY the exact dataset names listed below. Never invent synonyms.
       Wrong: "expenses", "vendors", "spending" — Right: "transactions", "merchants"
    2. Use ONLY the exact dimension names listed for each dataset.
       Wrong: "vendor", "category_name" — Right: "merchant", "category"
    3. Use ONLY the exact measure expressions listed.
       Wrong: "sum(expenses)" — Right: "sum(amount)"
    4. Filter values must be real values, not placeholders.
       Wrong: "last_month_start" — Right: "2026-03" (for month filters)
       For date-range queries, use the category or month dimension instead of date filters.

    COMPOSITION: For rich questions, combine multiple primitives. A good report uses 2-3 tools together.
    Always include summarize_findings when the user asks for analysis, review, or insight.

    Available data is described below. Use these exact names.
    """

    if resolver && function_exported?(resolver, :describe, 0) do
      base <> "\n" <> resolver.describe()
    else
      base
    end
  end

  defp resolve_provider(name) when is_atom(name) and not is_nil(name) do
    Map.get(@providers, name) || name
  end

  defp resolve_provider(nil) do
    raise ArgumentError, """
    No LLM provider configured for Resonance.

    Add to your config:

        config :resonance,
          provider: :anthropic,
          api_key: System.get_env("ANTHROPIC_API_KEY")
    """
  end
end
