defmodule ResonanceDemoWeb.ExploreLive do
  use ResonanceDemoWeb, :live_view

  import Ecto.Query
  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Company, Deal}

  @suggestions [
    "Show me deal pipeline by stage",
    "Who are our largest accounts by revenue?",
    "Compare Q1 vs Q2 deal performance",
    "Break down activity types by outcome",
    "Which sales reps close the most revenue?",
    "What does our contact funnel look like from lead to customer?",
    "Give me a full pipeline review with trends and top accounts"
  ]

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)
  @owners ~w(Alice Bob Carol Dave)
  @quarters ~w(2025-Q1 2025-Q2 2025-Q3 2025-Q4 2026-Q1 2026-Q2)

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
    company_ids = Repo.all(from c in Company, select: c.id)
    count = Enum.random(5..12)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    deals =
      for _i <- 1..count do
        %{
          name: "New Deal ##{System.unique_integer([:positive, :monotonic])}",
          value: Enum.random(10..500) * 1000,
          stage: Enum.random(@stages),
          close_date: Date.add(Date.utc_today(), Enum.random(-90..180)),
          owner: Enum.random(@owners),
          quarter: Enum.random(@quarters),
          company_id: Enum.random(company_ids),
          inserted_at: now,
          updated_at: now
        }
      end

    {inserted, _} = Repo.insert_all(Deal, deals)
    total_value = deals |> Enum.map(& &1.value) |> Enum.sum()

    socket = assign(socket, data_flash: "Added #{inserted} deals worth $#{format_value(total_value)}")

    # Re-resolve the current report against fresh data (no LLM re-call)
    send_update(Resonance.Live.Report, id: "explore-report", refresh: true)

    {:noreply, socket}
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

  defp format_value(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_value(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n), do: Integer.to_string(n)
end
