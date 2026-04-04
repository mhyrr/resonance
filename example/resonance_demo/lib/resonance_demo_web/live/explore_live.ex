defmodule ResonanceDemoWeb.ExploreLive do
  use ResonanceDemoWeb, :live_view

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
    {:ok, assign(socket, suggestions: @suggestions)}
  end

  @impl true
  def handle_event("try_query", %{"prompt" => prompt}, socket) do
    send_update(Resonance.Live.Report, id: "explore-report", set_prompt: prompt)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-8">
        <h1 class="text-2xl font-bold mb-2">Explore</h1>
        <p class="text-gray-600">Ask anything about your CRM data.</p>
      </div>

      <.live_component
        module={Resonance.Live.Report}
        id="explore-report"
        resolver={ResonanceDemo.CRM.Resolver}
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
