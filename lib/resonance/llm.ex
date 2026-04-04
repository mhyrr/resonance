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

    CRITICAL: You must use ONLY the exact dataset names listed below. Do not invent dataset names.
    For example, if "companies" is listed, use "companies" — not "accounts", "organizations", or "clients".
    Use only the listed measures and dimensions for each dataset.

    COMPOSITION: For rich questions, combine multiple primitives. A good report uses 2-3 tools together.

    Examples:

    User: "Show me deals by stage"
    → Use show_distribution with dataset "deals", dimensions ["stage"]

    User: "Give me a pipeline review with trends and key metrics"
    → Use segment_population for the stage breakdown
    → Use compare_over_time for the trend chart
    → Use summarize_findings for a narrative overview

    Always include summarize_findings when the user asks for analysis, review, or insight — not just raw numbers.
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
