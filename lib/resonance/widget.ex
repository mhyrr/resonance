defmodule Resonance.Widget do
  @moduledoc """
  Behaviour for interactive Resonance widgets.

  A Widget is a Phoenix LiveComponent that knows it can render certain
  Resonance `Result` kinds. After Resonance composes the page from the user's
  question, the widget is **just a Phoenix LiveComponent** — it calls your
  app's contexts from `handle_event/3`, subscribes to `Phoenix.PubSub` for
  live updates, manages local state in socket assigns, and handles mutations
  the way every other LiveComponent does. **The library composes; Phoenix
  runs.**

  ## Usage

      defmodule MyApp.Widgets.FilterableLeaderboard do
        use Resonance.Widget

        alias MyApp.Deals

        @impl Resonance.Widget
        def accepts_results, do: [:ranking]

        @impl Resonance.Widget
        def capabilities, do: [:filter, :live_updates]

        @impl Resonance.Widget
        def example_renderable do
          # Synthetic Renderable for the playground.
          %Resonance.Renderable{
            id: "example",
            type: "rank_entities",
            component: __MODULE__,
            props: %{title: "Top deals (example)", rows: [...]},
            status: :ready,
            render_via: :live
          }
        end

        # Optional: only used by the playground when on_mount provides a
        # widget_assigns map. Returns a Renderable built from real data
        # fetched via your own contexts.
        def playground_renderable(widget_assigns) do
          rows = widget_assigns.deals_ctx.top_by_value(limit: 10)
          Resonance.Renderable.ready_live(
            "rank_entities",
            __MODULE__,
            %{title: "Top deals", rows: rows}
          )
        end

        # Standard Phoenix.LiveComponent callbacks below — Resonance has
        # nothing to teach you here.
        @impl Phoenix.LiveComponent
        def mount(socket) do
          if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "deals")
          {:ok, socket}
        end

        @impl Phoenix.LiveComponent
        def update(%{renderable: r} = assigns, socket) do
          {:ok,
           socket
           |> assign(:title, r.props.title)
           |> assign(:rows, r.props.rows)
           |> assign(:current_user, assigns[:current_user])}
        end

        @impl Phoenix.LiveComponent
        def handle_event("filter_stage", %{"stage" => stage}, socket) do
          rows = Deals.top_by_value(stage: stage, user: socket.assigns.current_user)
          {:noreply, assign(socket, :rows, rows)}
        end

        @impl Phoenix.LiveComponent
        def handle_info({:deals_changed, _}, socket) do
          rows = Deals.top_by_value(user: socket.assigns.current_user)
          {:noreply, assign(socket, :rows, rows)}
        end

        def render(assigns), do: ~H"..."
      end

  ## The contract

  - **Required:** `accepts_results/0` returns the list of `Resonance.Result`
    kinds this widget can render. Drives Presenter dispatch and playground
    enumeration.
  - **Optional:** `capabilities/0` declares which user gestures the widget
    supports (developer documentation; the playground shows them).
  - **Optional:** `example_renderable/0` returns a synthetic `Renderable` the
    playground draws against when no live context is wired.
  - **Optional:** `playground_renderable/1` takes the on-mount-provided
    `widget_assigns` map and returns a `Renderable` built from real data.
    The widget builds it however it wants — typically by calling its own
    app contexts.
  - **From `Phoenix.LiveComponent`:** `update/2` accepts a `:renderable`
    assign carrying a `%Resonance.Renderable{}`. The widget reads `:props`
    off it for initial state. Everything else is normal LiveComponent.

  ## Symmetry with `Resonance.Component`

  `Resonance.Component` is the read-only contract for function components
  (charts, tables, prose). `Resonance.Widget` is the interactive contract
  for LiveComponents. A Presenter may map a `Result` kind to either by
  calling `Renderable.ready/3` or `Renderable.ready_live/3`. The two
  contracts are parallel and independent — pick whichever each `Result`
  kind needs.
  """

  @type capability :: atom()

  @doc """
  The list of `Resonance.Result` kinds this widget can render.

  Required. Powers Presenter dispatch and playground enumeration.
  """
  @callback accepts_results() :: [atom()]

  @doc """
  The user gestures this widget supports.

  Optional. Defaults to `[]` when not implemented. Documentation only —
  the playground shows it; nothing in the runtime depends on it.
  """
  @callback capabilities() :: [capability()]

  @doc """
  A synthetic `Renderable` for the playground.

  Optional. Widgets that omit this callback can still be enumerated by the
  playground but won't be auto-rendered against synthetic data.
  """
  @callback example_renderable() :: Resonance.Renderable.t()

  @doc """
  A `Renderable` built from real data, for the playground.

  Optional. Receives the `widget_assigns` map an `on_mount` hook attached
  to the playground (typically containing handles to app contexts and the
  current user). Returns a `Renderable` built however the widget wants —
  usually by calling app contexts directly.
  """
  @callback playground_renderable(widget_assigns :: map()) :: Resonance.Renderable.t()

  @optional_callbacks [
    capabilities: 0,
    example_renderable: 0,
    playground_renderable: 1
  ]

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
  Returns a Renderable built from real data via a widget's
  `playground_renderable/1` callback, or `:not_implemented` if the optional
  callback isn't defined. Returns `{:error, reason}` if the callback raises.
  """
  @spec playground_renderable(module(), map()) ::
          {:ok, Resonance.Renderable.t()} | {:error, term()} | :not_implemented
  def playground_renderable(widget_module, widget_assigns) do
    if function_exported?(widget_module, :playground_renderable, 1) do
      try do
        {:ok, widget_module.playground_renderable(widget_assigns)}
      rescue
        e -> {:error, Exception.message(e)}
      end
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
