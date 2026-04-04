defmodule FinanceDemoWeb.ExploreLive do
  use FinanceDemoWeb, :live_view

  @suggestions [
    "Where did my money go last month?",
    "Show my spending by category",
    "What are my top 10 merchants by total spend?",
    "Compare my monthly spending trend over the last 6 months",
    "Break down my food spending — groceries vs restaurants vs coffee",
    "How much am I spending on transportation?",
    "Give me a full spending summary with trends and top categories"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, suggestions: @suggestions, prompt: "")}
  end

  @impl true
  def handle_event("try_query", %{"prompt" => prompt}, socket) do
    send_update(Resonance.Live.Report, id: "explore-report", set_prompt: prompt)
    {:noreply, assign(socket, prompt: prompt)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-8">
        <h1 class="text-2xl font-bold mb-2">Spending Explorer</h1>
        <p class="text-gray-600">Ask anything about your personal finances.</p>
      </div>

      <.live_component
        module={Resonance.Live.Report}
        id="explore-report"
        resolver={FinanceDemo.Finance.Resolver}
        presenter={FinanceDemo.Presenters.ECharts}
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
