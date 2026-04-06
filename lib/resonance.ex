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

  ## Interactive widgets (v2)

  Read-only reports use `Resonance.Component` (function components). For
  interactive surfaces, return a `Resonance.Widget` from your Presenter
  instead — a Phoenix LiveComponent with one extra behaviour. Widgets
  receive the full `Renderable` (including the resolved `Result` and the
  original `QueryIntent`) and call `Resonance.refine/3` to re-resolve with
  a tweaked intent — no LLM round-trip, same trust boundary.

  See `Resonance.Widget` for the full contract and `Resonance.Live.Playground`
  for a developer page that enumerates every loaded widget.
  """

  alias Resonance.{Composer, LLM, Primitive, Registry, Renderable, Result}

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

  @doc """
  Re-resolve an existing Renderable with a tweaked `QueryIntent`.

  Used by interactive widgets (`Resonance.Widget`) to react to user gestures —
  filter changes, drilldowns, etc. — without going back through the LLM.

  Takes the current Renderable and a function that mutates the Renderable's
  `QueryIntent` (passing a function instead of a new intent forces the widget
  to start from the existing intent, preserving the LLM's original constraints
  and making refinement composable).

  ## Trust boundary

  `refine/3` calls the resolver's existing `validate/2` callback before
  resolving — the same trust boundary the read-only path uses. If a developer
  needs stricter rules for user-driven refinements than for LLM-generated ones,
  they can branch on a flag in `context`.

  ## Example

      def handle_event("filter", %{"stage" => stage}, socket) do
        context = %{
          resolver: socket.assigns.resolver,
          current_user: socket.assigns[:current_user],
          presenter: socket.assigns[:presenter]
        }

        {:ok, refined} =
          Resonance.refine(socket.assigns.renderable, fn intent ->
            update_in(intent.filters, fn filters ->
              [%{field: "stage", op: "=", value: stage} | filters || []]
            end)
          end, context)

        {:noreply, assign(socket, :renderable, refined)}
      end

  Returns `{:ok, new_renderable}` on success or `{:error, reason}` if the
  mutated intent fails validation or the resolver returns an error. The new
  Renderable preserves the original `id` so the LiveComponent rerenders in
  place rather than remounting.
  """
  @spec refine(Renderable.t(), (Resonance.QueryIntent.t() -> Resonance.QueryIntent.t()), map()) ::
          {:ok, Renderable.t()} | {:error, term()}
  def refine(renderable, intent_fn, context \\ %{})

  def refine(
        %Renderable{result: %Result{intent: intent} = result, primitive: primitive_name} =
          renderable,
        intent_fn,
        context
      )
      when is_function(intent_fn, 1) and is_binary(primitive_name) do
    new_intent = intent_fn.(intent)

    case Primitive.resolve_with_intent(result.kind, new_intent, result.title, context) do
      {:ok, %Result{} = new_result} ->
        presenter = context[:presenter] || Resonance.Presenters.Default
        new_renderable = presenter.present(new_result, context)

        {:ok,
         %{
           new_renderable
           | id: renderable.id,
             result: new_result,
             primitive: primitive_name
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def refine(%Renderable{result: nil}, _intent_fn, _context) do
    {:error, :renderable_missing_result}
  end

  def refine(%Renderable{primitive: nil}, _intent_fn, _context) do
    {:error, :renderable_missing_primitive}
  end
end
