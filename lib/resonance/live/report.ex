defmodule Resonance.Live.Report do
  @moduledoc """
  Drop-in LiveView component for Resonance report generation.

  ## Usage

      <.live_component
        module={Resonance.Live.Report}
        id="resonance-report"
        resolver={MyApp.DataResolver}
        current_user={@current_user}
      />

  Or in a dedicated LiveView:

      defmodule MyAppWeb.ExploreLive do
        use MyAppWeb, :live_view

        def mount(_params, _session, socket) do
          {:ok, assign(socket, resolver: MyApp.DataResolver)}
        end

        def render(assigns) do
          ~H\"\"\"
          <.live_component
            module={Resonance.Live.Report}
            id="explore"
            resolver={@resolver}
            current_user={@current_user}
          />
          \"\"\"
        end
      end
  """

  use Phoenix.LiveComponent

  alias Resonance.{Layout, Renderable}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       components: [],
       loading: false,
       prompt: "",
       error: nil,
       expected_count: 0
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, resolver: assigns.resolver, current_user: assigns[:current_user])}
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) when byte_size(prompt) > 0 do
    socket =
      assign(socket,
        loading: true,
        components: [],
        prompt: prompt,
        error: nil
      )

    context = %{
      resolver: socket.assigns.resolver,
      current_user: socket.assigns[:current_user]
    }

    pid = self()

    Task.start(fn ->
      case Resonance.generate(prompt, context) do
        {:ok, renderables} ->
          send(pid, {:resonance_report, :complete, renderables})

        {:error, reason} ->
          send(pid, {:resonance_report, :error, reason})
      end
    end)

    {:noreply, socket}
  end

  def handle_event("generate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, components: [], loading: false, prompt: "", error: nil)}
  end

  # These handle_info callbacks must be implemented in the parent LiveView.
  # The parent should forward these messages to the live_component via send_update.
  #
  # In the parent LiveView:
  #
  #   def handle_info({:resonance_report, :complete, renderables}, socket) do
  #     send_update(Resonance.Live.Report, id: "resonance-report", renderables: renderables)
  #     {:noreply, socket}
  #   end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="resonance-report" id={@id}>
      <form phx-submit="generate" phx-target={@myself}>
        <div class="resonance-prompt-container">
          <input
            type="text"
            name="prompt"
            value={@prompt}
            placeholder="What would you like to see?"
            class="resonance-prompt-input"
            disabled={@loading}
            autocomplete="off"
          />
          <button type="submit" class="resonance-generate-btn" disabled={@loading}>
            <%= if @loading, do: "Generating...", else: "Generate" %>
          </button>
        </div>
      </form>

      <div :if={@error} class="resonance-error-banner">
        <p>Something went wrong: <%= inspect(@error) %></p>
      </div>

      <div :if={@loading} class="resonance-loading">
        <div class="resonance-loading-indicator">Composing your report...</div>
      </div>

      <div :if={@components != []} class="resonance-components">
        <%= for component <- Layout.order(@components) do %>
          <div class="resonance-component-wrapper">
            <%= render_component(component) %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_component(%Renderable{status: :error} = r) do
    assigns = %{error: r.error}

    ~H"""
    <div class="resonance-component resonance-error">
      <p>Failed to load: <%= inspect(@error) %></p>
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props}) do
    assigns = %{props: props}
    component.render(assigns)
  end

  defp render_component(_), do: nil
end
