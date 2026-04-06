defmodule Resonance.Widget do
  @moduledoc """
  Behaviour for interactive Resonance widgets.

  A Widget is a Phoenix LiveComponent that knows how to render a
  `Resonance.Renderable` and how to react to user gestures. Widgets are the
  developer-supplied surface that turns a read-only Resonance report into an
  interactive UI page.

  ## Usage

      defmodule MyApp.Widgets.FilterableLeaderboard do
        use Resonance.Widget

        @impl Resonance.Widget
        def accepts_results, do: [:ranking]

        @impl Resonance.Widget
        def capabilities, do: [:refine]

        @impl Resonance.Widget
        def example_renderable do
          %Resonance.Renderable{
            id: "example",
            type: "ranking",
            component: __MODULE__,
            props: %{title: "Top reps", rows: [...]},
            status: :ready,
            render_via: :live
          }
        end

        # Standard LiveComponent callbacks below
        @impl Phoenix.LiveComponent
        def update(%{renderable: r} = assigns, socket) do
          {:ok, assign(socket, :renderable, r)}
        end

        def handle_event("filter", %{"stage" => stage}, socket) do
          {:ok, refined} =
            Resonance.refine(socket.assigns.renderable, fn intent ->
              update_in(intent.filters, &[%{field: "stage", op: "=", value: stage} | &1 || []])
            end)

          {:noreply, assign(socket, :renderable, refined)}
        end

        def render(assigns), do: ~H\"\"\"...\"\"\"
      end

  ## The contract

  - `accepts_results/0` (required) — list of `Resonance.Result` kinds this
    widget can render. Powers Presenter dispatch and playground enumeration.
  - `capabilities/0` (optional, default `[]`) — declares which user gestures
    the widget supports (`:refine`, `:mutate`, `:drilldown`). Documentation
    in v2; future versions may feed this into the LLM's system prompt.
  - `example_renderable/0` (optional) — synthetic `Renderable` used by the
    playground to render the widget without real data.
  - **From `Phoenix.LiveComponent`:** `update/2` must accept an assign named
    `:renderable` carrying a `%Resonance.Renderable{}` (which includes the
    `Result`, the `QueryIntent`, and a stable id).

  To re-resolve a Renderable with a tweaked QueryIntent (filter changes,
  drilldown), call `Resonance.refine/2`. To mutate app state, call your own
  contexts from `handle_event/3` like any LiveComponent.

  ## Symmetry with `Resonance.Component`

  `Resonance.Component` is the read-only contract for function components.
  `Resonance.Widget` is the interactive contract for LiveComponents. A
  Presenter may map a given Result kind to either kind of target by setting
  `render_via: :function | :live` on the `%Renderable{}` it produces.
  """

  @type capability :: :refine | :mutate | :drilldown

  @doc """
  The list of `Resonance.Result` kinds this widget can render.

  Required. Powers Presenter dispatch and playground enumeration.
  """
  @callback accepts_results() :: [atom()]

  @doc """
  The user gestures this widget supports.

  Optional. Defaults to `[]` when not implemented.
  """
  @callback capabilities() :: [capability()]

  @doc """
  A synthetic Renderable for use in the playground.

  Optional. Widgets that omit this callback can still be enumerated by the
  playground but won't be auto-rendered.
  """
  @callback example_renderable() :: Resonance.Renderable.t()

  @doc """
  A Renderable produced from real data via the given context's resolver.

  Optional. Used by the playground when a context is configured (e.g. via an
  `on_mount` hook in the consuming app's router) so widgets render against
  live data instead of the synthetic `example_renderable/0`.

  Implementations typically build a `QueryIntent`, call
  `Resonance.Primitive.resolve_with_intent/4`, and wrap the result in a
  `Renderable` whose `component` is the widget itself. The widget can then
  be re-resolved on user gestures via `Resonance.refine/3`.
  """
  @callback live_renderable(context :: map()) :: {:ok, Resonance.Renderable.t()} | {:error, term()}

  @optional_callbacks [capabilities: 0, example_renderable: 0, live_renderable: 1]

  @doc """
  Returns the capabilities declared by a widget module, or `[]` if the
  optional callback isn't implemented.
  """
  @spec capabilities(module()) :: [capability()]
  def capabilities(widget_module) do
    if function_exported?(widget_module, :capabilities, 0) do
      widget_module.capabilities()
    else
      []
    end
  end

  @doc """
  Returns the example Renderable for a widget module, or `:error` if the
  optional callback isn't implemented.
  """
  @spec example_renderable(module()) :: {:ok, Resonance.Renderable.t()} | :error
  def example_renderable(widget_module) do
    if function_exported?(widget_module, :example_renderable, 0) do
      {:ok, widget_module.example_renderable()}
    else
      :error
    end
  end

  @doc """
  Returns a live Renderable for a widget module by calling its
  `live_renderable/1` callback with the given context.

  Returns `:not_implemented` if the callback isn't defined, `{:ok, r}` on
  success, or `{:error, reason}` on resolver/validation failures.
  """
  @spec live_renderable(module(), map()) ::
          {:ok, Resonance.Renderable.t()} | {:error, term()} | :not_implemented
  def live_renderable(widget_module, context) do
    if function_exported?(widget_module, :live_renderable, 1) do
      widget_module.live_renderable(context)
    else
      :not_implemented
    end
  end

  @doc """
  Returns the Result kinds a widget module accepts.
  """
  @spec accepts_results(module()) :: [atom()]
  def accepts_results(widget_module) do
    widget_module.accepts_results()
  end

  @doc """
  Returns true if the given module implements `Resonance.Widget`.

  Used by the playground for runtime enumeration of loaded widget modules.
  """
  @spec widget?(module()) :: boolean()
  def widget?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__info__, 1) and
      __MODULE__ in declared_behaviours(module)
  rescue
    _ -> false
  end

  defp declared_behaviours(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  defmacro __using__(_opts) do
    quote do
      use Phoenix.LiveComponent
      @behaviour Resonance.Widget
    end
  end
end
