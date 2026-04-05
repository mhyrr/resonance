defmodule Resonance do
  @moduledoc """
  Generative analysis surfaces for Phoenix LiveView.

  Resonance lets users ask questions about application data and receive
  composed, app-native UI — reports, dashboards, and contextual insights —
  built from semantic primitives and streamed in real-time via LiveView.

  ## Quick Start

      # config/runtime.exs
      config :resonance,
        provider: :anthropic,
        api_key: System.get_env("ANTHROPIC_API_KEY"),
        model: "claude-sonnet-4-5"

      # In your LiveView or controller
      {:ok, components} = Resonance.generate(prompt, %{
        resolver: MyApp.DataResolver,
        current_user: user
      })

  The LLM selects semantic operations. Your app resolves truth.
  Resonance composes the UI.
  """

  alias Resonance.{Composer, LLM, Registry}

  @doc """
  Generate a composed report from a natural language prompt.

  Returns a list of `Resonance.Renderable` structs ready for LiveView rendering.

  ## Options in context

    * `:resolver` - (required) module implementing `Resonance.Resolver`
    * `:current_user` - (optional) passed through to resolver for authorization

  """
  @spec generate(String.t(), map()) :: {:ok, [Resonance.Renderable.t()]} | {:error, term()}
  def generate(prompt, context) do
    metadata = %{prompt: prompt, resolver: context[:resolver]}

    :telemetry.span([:resonance, :generate], metadata, fn ->
      result =
        with {:ok, tool_calls} <- LLM.chat(prompt, Registry.all_schemas(), context),
             {:ok, renderables} <- Composer.compose(tool_calls, context) do
          {:ok, renderables}
        end

      {result, Map.put(metadata, :result, result)}
    end)
  end

  @doc """
  Stream composed report components to a process as they resolve.

  Sends `{:resonance, {:component_ready, renderable}}` messages to `pid`
  as each component finishes resolving. Sends `{:resonance, :done}` when complete.
  """
  @spec generate_stream(String.t(), map(), pid()) :: :ok | {:error, term()}
  def generate_stream(prompt, context, pid) do
    case LLM.chat(prompt, Registry.all_schemas(), context) do
      {:ok, tool_calls} ->
        Composer.compose_stream(tool_calls, context, pid)

      {:error, reason} ->
        {:error, reason}
    end
  end
end
