defmodule Resonance.Live.Playground do
  @moduledoc """
  Library-provided LiveView that enumerates `Resonance.Widget`-implementing
  modules in the running application(s), shows their declared metadata, and
  renders each one against either its synthetic `example_renderable/0` or —
  when an `on_mount` hook provides `widget_assigns` — its
  `playground_renderable/1` against real data via the developer's own
  contexts.

  ## Mounting in your app

  ### Static (synthetic data only)

      # router.ex
      live "/resonance/playground", Resonance.Live.Playground

  ### Live data (the playground passes app handles to your widgets)

  Add an `on_mount` hook that puts a `widget_assigns` map into socket assigns.
  When the playground sees `:widget_assigns`, it prefers each widget's
  `playground_renderable/1` over its synthetic example, and merges
  `widget_assigns` into every mounted widget so the widget can call your
  contexts directly.

      # router.ex
      live_session :playground, on_mount: MyAppWeb.PlaygroundContext do
        live "/resonance/playground", Resonance.Live.Playground
      end

      # my_app_web/playground_context.ex
      defmodule MyAppWeb.PlaygroundContext do
        import Phoenix.Component, only: [assign: 3]

        def on_mount(:default, _params, _session, socket) do
          {:cont,
           socket
           |> assign(:widget_assigns, %{
             deals_ctx: MyApp.Deals,
             current_user: nil
           })
           |> assign(:simulate_label, "Simulate New Data")
           |> assign(:simulate_fn, &MyApp.Demo.simulate_and_broadcast/0)}
        end
      end

  ## Widget callbacks the playground uses

  - `accepts_results/0` (required) — drives the index list and metadata table.
  - `capabilities/0` (optional) — shown in the metadata table.
  - `example_renderable/0` (optional) — synthetic data for the static path.
  - `playground_renderable/1` (optional) — real-data path; receives the
    `widget_assigns` map and returns a `Renderable` built from the widget's
    own contexts.

  The playground is intentionally a developer tool, not a production page —
  it ships with minimal styling and no auth. Don't mount it under a public
  route.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    widgets = discover_widgets()

    socket =
      socket
      |> assign_new(:widget_assigns, fn -> nil end)
      |> assign_new(:simulate_fn, fn -> nil end)
      |> assign_new(:simulate_label, fn -> "Simulate" end)
      |> assign_new(:pubsub, fn -> nil end)
      |> assign_new(:subscribe_topics, fn -> [] end)

    if connected?(socket) and socket.assigns.pubsub do
      Enum.each(socket.assigns.subscribe_topics, fn topic ->
        Phoenix.PubSub.subscribe(socket.assigns.pubsub, topic)
      end)
    end

    {:ok,
     socket
     |> assign(:widgets, widgets)
     |> assign(:selected, nil)
     |> assign(:current_renderable, nil)
     |> assign(:render_mode, :example)
     |> assign(:flash_message, nil)
     |> assign(:page_title, "Resonance Widget Playground")}
  end

  @impl true
  def handle_info(_msg, socket) do
    # Any subscribed topic message — re-resolve the current widget so its
    # data refreshes. We don't inspect the message; the assumption is that
    # if the developer asked us to subscribe to it, any message on it means
    # data may have changed.
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      selected ->
        {:noreply, load_selected(socket, selected)}
    end
  end

  @impl true
  def handle_params(%{"widget" => name}, _uri, socket) do
    selected =
      Enum.find(socket.assigns.widgets, fn w -> Atom.to_string(w.module) == name end)

    {:noreply, load_selected(socket, selected)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, load_selected(socket, nil)}
  end

  defp load_selected(socket, nil) do
    socket
    |> assign(:selected, nil)
    |> assign(:current_renderable, nil)
    |> assign(:render_mode, :example)
  end

  defp load_selected(socket, selected) do
    {renderable, mode} = resolve_renderable(selected, socket.assigns.widget_assigns)

    socket
    |> assign(:selected, selected)
    |> assign(:current_renderable, renderable)
    |> assign(:render_mode, mode)
  end

  # Returns {renderable | nil, :live | :example | :none}
  defp resolve_renderable(widget, nil) do
    {widget.example, if(widget.example, do: :example, else: :none)}
  end

  defp resolve_renderable(widget, widget_assigns) do
    case Resonance.Widget.playground_renderable(widget.module, widget_assigns) do
      {:ok, renderable} ->
        {renderable, :live}

      :not_implemented ->
        {widget.example, if(widget.example, do: :example, else: :none)}

      {:error, _reason} ->
        # Fall back to example so the developer still sees something.
        {widget.example, if(widget.example, do: :example, else: :none)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      selected ->
        {:noreply,
         socket
         |> load_selected(selected)
         |> assign(:flash_message, "Refreshed.")}
    end
  end

  def handle_event("simulate", _params, socket) do
    case socket.assigns.simulate_fn do
      fun when is_function(fun, 0) ->
        result = fun.()
        message = simulate_message(result, socket.assigns.simulate_label)

        socket =
          case socket.assigns.selected do
            nil -> socket
            selected -> load_selected(socket, selected)
          end

        {:noreply, assign(socket, :flash_message, message)}

      _ ->
        {:noreply, socket}
    end
  end

  defp simulate_message(:ok, label), do: "#{label} ran. Refreshed."
  defp simulate_message({:ok, msg}, _label) when is_binary(msg), do: msg <> " — refreshed."
  defp simulate_message(_other, label), do: "#{label} ran."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="resonance-playground" style="width: 100%; padding: 2rem 2.5rem; font-family: system-ui, -apple-system, sans-serif; color: #1f2937; box-sizing: border-box;">
      <header style="margin-bottom: 2rem; max-width: 880px;">
        <h1 style="font-size: 1.75rem; font-weight: 700; margin: 0 0 0.75rem; color: #111827;">
          Resonance Widget Playground
        </h1>
        <p style="color: #1f2937; font-size: 1.05rem; line-height: 1.6; margin: 0 0 1rem; font-weight: 500;">
          A user dreams up the view they want, asks for it in their own words, and your
          app composes it on the fly — from your data, with your components, in the shape
          of the question they actually asked. No PM had to anticipate it. No engineer had
          to build it. The view that exists is the view they needed.
        </p>
        <p style="color: #4b5563; font-size: 0.95rem; line-height: 1.6; margin: 0 0 0.75rem;">
          That's the promise. The mechanism is small: an LLM picks
          <strong>semantic primitives</strong> (rank, compare, distribute, segment, summarize)
          over your data, a <strong>resolver</strong> you write fetches the rows, and a
          <strong>presenter</strong> you write maps each result to a component. Read-only
          results become <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Resonance.Component</code>
          function components (charts, tables, prose). Interactive results become
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Resonance.Widget</code>
          LiveComponents — and after Resonance composes the page, the widgets are
          <em>just LiveComponents</em>: they call your contexts from
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">handle_event/3</code>,
          subscribe to <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Phoenix.PubSub</code>
          for live updates, and handle mutations the way every other LiveComponent does.
          The library composes; Phoenix runs.
        </p>
        <p style="color: #4b5563; font-size: 0.95rem; line-height: 1.6; margin: 0 0 1rem;">
          This page is where you meet the widgets your app provides. Every loaded
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Resonance.Widget</code>
          shows up here. When the consuming app wires
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">widget_assigns</code>
          into the playground via an
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">on_mount</code>
          hook, widgets render against <strong>real data</strong> through their optional
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">playground_renderable/1</code>
          callback; otherwise they fall back to synthetic
          <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">example_renderable/0</code>
          data so you can still see them in isolation.
        </p>
        <div style="display: flex; align-items: center; gap: 0.75rem; margin-top: 0.5rem;">
          <p style="color: #6b7280; font-size: 0.85rem; margin: 0;">
            {length(@widgets)} widget{if length(@widgets) == 1, do: "", else: "s"} discovered
            <%= if @widget_assigns do %>
              <span style="color: #059669; font-weight: 500;">· live data</span>
            <% else %>
              <span style="color: #9ca3af;">· synthetic data</span>
            <% end %>
          </p>
          <button
            :if={@simulate_fn}
            type="button"
            phx-click="simulate"
            style="padding: 0.4rem 0.85rem; font-size: 0.8rem; font-weight: 500; background: #1f2937; color: white; border: none; border-radius: 0.4rem; cursor: pointer;"
          >
            {@simulate_label}
          </button>
          <span :if={@flash_message} style="font-size: 0.8rem; color: #059669;">{@flash_message}</span>
        </div>
      </header>

      <div :if={@widgets == []} style="padding: 3rem; text-align: center; color: #9ca3af; border: 1px dashed #e5e7eb; border-radius: 0.75rem;">
        <p style="margin: 0;">No <code>Resonance.Widget</code> modules loaded.</p>
        <p style="margin: 0.5rem 0 0; font-size: 0.85rem;">
          Define a widget with <code>use Resonance.Widget</code> and reload.
        </p>
      </div>

      <div :if={@widgets != []} style="display: grid; grid-template-columns: 280px 1fr; gap: 1.5rem;">
        <aside>
          <ul style="list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.25rem;">
            <%= for widget <- @widgets do %>
              <li>
                <.link
                  patch={"?widget=#{widget.module}"}
                  style={list_item_style(@selected, widget)}
                >
                  <div style="font-weight: 600; font-size: 0.9rem;">{widget.short_name}</div>
                  <div style="font-size: 0.75rem; color: #6b7280; margin-top: 0.15rem;">
                    accepts: {Enum.join(widget.accepts, ", ")}
                  </div>
                </.link>
              </li>
            <% end %>
          </ul>
        </aside>

        <main style="min-width: 0;">
          <div :if={@selected == nil} style="padding: 2.5rem; border: 1px dashed #e5e7eb; border-radius: 0.75rem; color: #9ca3af; text-align: center;">
            Select a widget from the list.
          </div>

          <div :if={@selected != nil}>
            <div style="margin-bottom: 0.75rem; display: flex; align-items: baseline; justify-content: space-between; gap: 1rem;">
              <div>
                <h2 style="font-size: 1.25rem; font-weight: 600; margin: 0 0 0.25rem; color: #111827;">
                  {@selected.short_name}
                </h2>
                <code style="font-size: 0.75rem; color: #6b7280;">{@selected.module}</code>
              </div>
              <div style="display: flex; align-items: center; gap: 0.5rem;">
                <span style={mode_pill_style(@render_mode)}>{mode_label(@render_mode)}</span>
                <button
                  :if={@render_mode == :live}
                  type="button"
                  phx-click="refresh"
                  style="padding: 0.35rem 0.75rem; font-size: 0.75rem; font-weight: 500; background: white; color: #374151; border: 1px solid #d1d5db; border-radius: 0.4rem; cursor: pointer;"
                >
                  Refresh
                </button>
              </div>
            </div>

            <p style="color: #4b5563; font-size: 0.875rem; line-height: 1.55; margin: 0 0 1.25rem; max-width: 720px;">
              A Phoenix LiveComponent that implements
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Resonance.Widget</code>.
              When the presenter routes a result to this widget,
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Live.Report</code>
              mounts it via
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">&lt;.live_component&gt;</code>
              with the full
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Renderable</code>
              (which carries the resolved
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">Result</code>
              and the original
              <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">QueryIntent</code>)
              as the <code style="background: #f3f4f6; padding: 0.05rem 0.3rem; border-radius: 0.25rem;">:renderable</code>
              assign.
            </p>

            <div style="margin-bottom: 1.5rem; display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1rem; font-size: 0.85rem;">
              <div>
                <div style="text-transform: uppercase; letter-spacing: 0.05em; color: #9ca3af; font-size: 0.7rem; font-weight: 600;">
                  Accepts
                </div>
                <div style="margin-top: 0.25rem; color: #374151; font-weight: 500;">{Enum.join(@selected.accepts, ", ")}</div>
                <div style="margin-top: 0.15rem; color: #9ca3af; font-size: 0.75rem; line-height: 1.4;">
                  <code>Result</code> kinds this widget can render — the presenter dispatches on this.
                </div>
              </div>
              <div>
                <div style="text-transform: uppercase; letter-spacing: 0.05em; color: #9ca3af; font-size: 0.7rem; font-weight: 600;">
                  Capabilities
                </div>
                <div style="margin-top: 0.25rem; color: #374151; font-weight: 500;">
                  {if @selected.capabilities == [], do: "—", else: Enum.join(@selected.capabilities, ", ")}
                </div>
                <div style="margin-top: 0.15rem; color: #9ca3af; font-size: 0.75rem; line-height: 1.4;">
                  User gestures the widget supports (refine, mutate, drilldown).
                </div>
              </div>
              <div>
                <div style="text-transform: uppercase; letter-spacing: 0.05em; color: #9ca3af; font-size: 0.7rem; font-weight: 600;">
                  Renderable source
                </div>
                <div style="margin-top: 0.25rem; color: #374151; font-weight: 500;">
                  {render_source_label(@selected, @render_mode)}
                </div>
                <div style="margin-top: 0.15rem; color: #9ca3af; font-size: 0.75rem; line-height: 1.4;">
                  Where the data being rendered came from.
                </div>
              </div>
            </div>

            <div style="border: 1px solid #e5e7eb; border-radius: 0.75rem; padding: 1.25rem; background: #fafafa;">
              <%= cond do %>
                <% @current_renderable && @widget_assigns -> %>
                  <.live_component
                    module={@selected.module}
                    id={"playground-" <> @selected.short_name}
                    renderable={@current_renderable}
                    {@widget_assigns}
                  />
                <% @current_renderable -> %>
                  <.live_component
                    module={@selected.module}
                    id={"playground-" <> @selected.short_name}
                    renderable={@current_renderable}
                  />
                <% true -> %>
                  <div style="color: #9ca3af; padding: 1.5rem; text-align: center;">
                    No <code>example_renderable/0</code> or <code>playground_renderable/1</code>
                    to render.
                  </div>
              <% end %>
            </div>
          </div>
        </main>
      </div>
    </div>
    """
  end

  defp list_item_style(selected, widget) do
    base = "display: block; padding: 0.6rem 0.75rem; border-radius: 0.5rem; text-decoration: none; color: #1f2937; "

    if selected && selected.module == widget.module do
      base <> "background: #eff6ff; border: 1px solid #bfdbfe;"
    else
      base <> "border: 1px solid transparent;"
    end
  end

  defp mode_pill_style(:live) do
    "padding: 0.2rem 0.55rem; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; background: #ecfdf5; color: #047857; border-radius: 999px;"
  end

  defp mode_pill_style(:example) do
    "padding: 0.2rem 0.55rem; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; background: #f3f4f6; color: #6b7280; border-radius: 999px;"
  end

  defp mode_pill_style(:none) do
    "padding: 0.2rem 0.55rem; font-size: 0.7rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; background: #fef3c7; color: #92400e; border-radius: 999px;"
  end

  defp mode_label(:live), do: "live data"
  defp mode_label(:example), do: "example data"
  defp mode_label(:none), do: "no data"

  defp render_source_label(_, :live), do: "playground_renderable/1"
  defp render_source_label(%{example: ex}, :example) when not is_nil(ex), do: "example_renderable/0"
  defp render_source_label(_, _), do: "—"

  # --- Discovery ---

  defp discover_widgets do
    Application.loaded_applications()
    |> Enum.flat_map(fn {app, _, _} ->
      case Application.spec(app, :modules) do
        modules when is_list(modules) -> modules
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.filter(&Resonance.Widget.widget?/1)
    |> Enum.map(&describe_widget/1)
    |> Enum.sort_by(& &1.short_name)
  end

  defp describe_widget(module) do
    %{
      module: module,
      short_name: short_name(module),
      accepts: safe_accepts(module),
      capabilities: Resonance.Widget.capabilities(module),
      example: safe_example(module)
    }
  end

  defp short_name(module) do
    module |> Atom.to_string() |> String.split(".") |> List.last()
  end

  defp safe_accepts(module) do
    Resonance.Widget.accepts_results(module)
  rescue
    _ -> []
  end

  defp safe_example(module) do
    case Resonance.Widget.example_renderable(module) do
      {:ok, renderable} -> renderable
      :error -> nil
    end
  rescue
    _ -> nil
  end
end
