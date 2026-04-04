defmodule ResonanceDemoWeb.ExploreLive do
  use ResonanceDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
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
    </div>
    """
  end
end
