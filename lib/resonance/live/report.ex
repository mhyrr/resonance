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

  No parent LiveView wiring needed — the component handles the full
  lifecycle internally via `send_update/3`.
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
       error: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:id, assigns.id)
      |> assign_new(:resolver, fn -> assigns[:resolver] end)
      |> assign_new(:current_user, fn -> assigns[:current_user] end)
      |> assign_new(:components, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:prompt, fn -> "" end)
      |> assign_new(:error, fn -> nil end)

    # Handle async results from send_update
    socket =
      case assigns[:resonance_result] do
        {:ok, renderables} -> assign(socket, components: renderables, loading: false)
        {:error, reason} -> assign(socket, error: reason, loading: false)
        _ -> socket
      end

    # Allow resolver to be updated
    socket =
      if assigns[:resolver], do: assign(socket, :resolver, assigns.resolver), else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) when byte_size(prompt) > 0 do
    socket = assign(socket, loading: true, components: [], prompt: prompt, error: nil)

    context = %{
      resolver: socket.assigns.resolver,
      current_user: socket.assigns[:current_user]
    }

    component_id = socket.assigns.id
    lv_pid = self()

    Task.start(fn ->
      result =
        case Resonance.generate(prompt, context) do
          {:ok, renderables} -> {:ok, renderables}
          {:error, reason} -> {:error, reason}
        end

      send_update(lv_pid, Resonance.Live.Report, id: component_id, resonance_result: result)
    end)

    {:noreply, socket}
  end

  def handle_event("generate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, components: [], loading: false, prompt: "", error: nil)}
  end

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
            {if @loading, do: "Generating...", else: "Generate"}
          </button>
        </div>
      </form>

      <div :if={@error} class="resonance-error-banner">
        <p>Something went wrong: {format_error(@error)}</p>
      </div>

      <div :if={@loading} class="resonance-loading">
        <div class="resonance-loading-indicator">Composing your report...</div>
      </div>

      <div :if={@components != []} class="resonance-components">
        <%= for component <- Layout.order(@components) do %>
          <div class="resonance-component-wrapper">
            {render_component(component)}
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
      <p class="resonance-error-text">{format_error(@error)}</p>
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props}) do
    assigns = %{props: props}
    component.render(assigns)
  end

  defp render_component(_), do: nil

  defp format_error({:api_error, status, %{"error" => %{"message" => msg}}}),
    do: "API error (#{status}): #{msg}"

  defp format_error({:api_error, status, _}),
    do: "API error (#{status})"

  defp format_error({:request_failed, _}),
    do: "Could not reach the LLM provider. Check your network and API key."

  defp format_error({:unknown_primitive, name}),
    do: "Unknown analysis type: #{name}"

  defp format_error({:unsupported_query, dataset}),
    do: "The query combination for \"#{dataset}\" is not supported yet."

  defp format_error({:query_failed, msg}) when is_binary(msg),
    do: "Data query failed: #{msg}"

  defp format_error({:invalid_field, field, msg}),
    do: "Invalid #{field}: #{msg}"

  defp format_error(error), do: inspect(error)
end
