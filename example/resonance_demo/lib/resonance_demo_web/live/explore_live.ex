defmodule ResonanceDemoWeb.ExploreLive do
  use ResonanceDemoWeb, :live_view

  alias Resonance.{Layout, Renderable}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       components: [],
       loading: false,
       prompt: "",
       error: nil
     )}
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) when byte_size(prompt) > 0 do
    socket = assign(socket, loading: true, components: [], prompt: prompt, error: nil)

    context = %{resolver: ResonanceDemo.CRM.Resolver}
    pid = self()

    Task.start(fn ->
      case Resonance.generate(prompt, context) do
        {:ok, renderables} ->
          send(pid, {:resonance_complete, renderables})

        {:error, reason} ->
          send(pid, {:resonance_error, reason})
      end
    end)

    {:noreply, socket}
  end

  def handle_event("generate", _params, socket), do: {:noreply, socket}

  def handle_event("clear", _params, socket) do
    {:noreply, assign(socket, components: [], loading: false, prompt: "", error: nil)}
  end

  @impl true
  def handle_info({:resonance_complete, renderables}, socket) do
    {:noreply, assign(socket, components: renderables, loading: false)}
  end

  def handle_info({:resonance_error, reason}, socket) do
    {:noreply, assign(socket, error: reason, loading: false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-8">
        <h1 class="text-2xl font-bold mb-2">Explore</h1>
        <p class="text-gray-600">Ask anything about your CRM data.</p>
      </div>

      <form phx-submit="generate" class="mb-8">
        <div class="flex gap-3">
          <input
            type="text"
            name="prompt"
            value={@prompt}
            placeholder="e.g. Show me deal pipeline by stage, or Compare Q1 vs Q2 activity"
            class="flex-1 px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={@loading}
            autocomplete="off"
          />
          <button
            type="submit"
            disabled={@loading}
            class="px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {if @loading, do: "Generating...", else: "Generate"}
          </button>
          <button
            :if={@components != []}
            type="button"
            phx-click="clear"
            class="px-4 py-3 border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            Clear
          </button>
        </div>
      </form>

      <div :if={@error} class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
        <p class="text-red-700">Error: {inspect(@error)}</p>
      </div>

      <div :if={@loading} class="text-center py-12">
        <div class="inline-block animate-pulse text-gray-500">Composing your report...</div>
      </div>

      <div :if={@components != []} class="space-y-6">
        <%= for component <- Layout.order(@components) do %>
          <div class="bg-white rounded-lg shadow p-6">
            {render_component(component)}
          </div>
        <% end %>
      </div>

      <div
        :if={@components == [] and not @loading and @prompt == ""}
        class="text-center py-16 text-gray-400"
      >
        <p class="text-lg mb-4">Try asking:</p>
        <div class="space-y-2 text-sm">
          <p>"Show me deal pipeline by stage"</p>
          <p>"Who are our largest accounts?"</p>
          <p>"Compare activity types this year"</p>
          <p>"What's the distribution of contacts by stage?"</p>
        </div>
      </div>
    </div>
    """
  end

  defp render_component(%Renderable{status: :error} = r) do
    assigns = %{error: r.error}

    ~H"""
    <div class="p-4 bg-red-50 border border-red-200 rounded">
      <p class="text-red-700">Failed to load: {inspect(@error)}</p>
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props}) do
    assigns = %{props: props}
    component.render(assigns)
  end

  defp render_component(_), do: nil
end
