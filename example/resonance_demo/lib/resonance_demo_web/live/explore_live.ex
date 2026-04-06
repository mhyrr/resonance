defmodule ResonanceDemoWeb.ExploreLive do
  use ResonanceDemoWeb, :live_view

  alias ResonanceDemo.Deals

  @suggestions [
    "Show me deal pipeline by stage",
    "Who are our largest accounts by revenue?",
    "Compare Q1 vs Q2 deal performance",
    "Break down activity types by outcome",
    "Which sales reps close the most revenue?",
    "What does our contact funnel look like from lead to customer?",
    "Give me a full pipeline review with trends and top accounts"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, suggestions: @suggestions, prompt: "", data_flash: nil)}
  end

  @impl true
  def handle_event("try_query", %{"prompt" => prompt}, socket) do
    send_update(Resonance.Live.Report, id: "explore-report", set_prompt: prompt)
    {:noreply, assign(socket, prompt: prompt)}
  end

  @impl true
  def handle_event("simulate_deals", _params, socket) do
    {:ok, message} = Deals.simulate_batch()

    # Re-run the same LLM tool calls against fresh data for any non-interactive
    # widgets. Widgets that subscribed to the "deals" PubSub topic already
    # updated themselves via the broadcast inside Deals.simulate_batch/0.
    send_update(Resonance.Live.Report, id: "explore-report", refresh: true)

    {:noreply, assign(socket, data_flash: message)}
  end

  @impl true
  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, data_flash: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-8 flex items-start justify-between">
        <div>
          <h1 class="text-2xl font-bold mb-2">Explore</h1>
          <p class="text-gray-600">Ask anything about your CRM data.</p>
        </div>
        <button
          phx-click="simulate_deals"
          class="px-4 py-2 text-sm font-medium rounded-lg border border-gray-300 text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
        >
          Simulate New Deals
        </button>
      </div>

      <div
        :if={@data_flash}
        class="mb-4 px-4 py-3 rounded-lg bg-emerald-50 border border-emerald-200 text-emerald-800 text-sm flex items-center justify-between"
      >
        <span>{@data_flash}</span>
        <button phx-click="dismiss_flash" class="text-emerald-600 hover:text-emerald-800 ml-4 cursor-pointer">
          &times;
        </button>
      </div>

      <.live_component
        module={Resonance.Live.Report}
        id="explore-report"
        resolver={ResonanceDemo.CRM.Resolver}
        presenter={ResonanceDemoWeb.Presenters.Interactive}
        widget_assigns={%{current_user: nil}}
      />

      <div class="mt-12 text-center text-gray-400">
        <p class="text-sm mb-3">Try one of these:</p>
        <div class="flex flex-wrap justify-center gap-2">
          <button
            :for={suggestion <- @suggestions}
            phx-click="try_query"
            phx-value-prompt={suggestion}
            class="text-sm px-3 py-1.5 rounded-full border border-gray-200 text-gray-500 hover:border-blue-300 hover:text-blue-600 transition-colors cursor-pointer"
          >
            {suggestion}
          </button>
        </div>
      </div>
    </div>
    """
  end

end
