defmodule ResonanceDemoWeb.WorkspaceLive do
  use ResonanceDemoWeb, :live_view

  alias Resonance.Live.Workspace
  alias ResonanceDemo.{Deals, Workspaces}

  @workspace_id "crm-workspace"
  @prompt "Give me a full pipeline review with trends and top accounts"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Deals.pubsub(), Deals.topic())

    {:ok, assign(socket, data_flash: nil, prompt: @prompt, workspace_id: @workspace_id)}
  end

  @impl true
  def handle_event("simulate_deals", _params, socket) do
    {:ok, message} = Deals.simulate_batch()

    {:noreply, assign(socket, data_flash: message)}
  end

  def handle_event("rerun_workspace", _params, socket) do
    send_update(Workspace, id: @workspace_id, rerun: true)
    {:noreply, socket}
  end

  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, data_flash: nil)}
  end

  @impl true
  def handle_info({:deals_changed, _meta}, socket) do
    send_update(Workspace, id: @workspace_id, rerun: true)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">Workspace</p>
          <h1 class="text-2xl font-bold text-slate-950">Pipeline review</h1>
          <p class="mt-1 max-w-2xl text-sm text-slate-600">{@prompt}</p>
        </div>

        <button
          phx-click="simulate_deals"
          class="rounded-md bg-slate-950 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-slate-800"
        >
          Simulate New Deals
        </button>
      </div>

      <div
        :if={@data_flash}
        class="mb-4 flex items-center justify-between rounded-md border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800"
      >
        <span>{@data_flash}</span>
        <button phx-click="dismiss_flash" class="ml-4 text-emerald-700 hover:text-emerald-950">
          &times;
        </button>
      </div>

      <.live_component
        module={Workspace}
        id={@workspace_id}
        resolver={ResonanceDemo.CRM.Resolver}
        patterns={ResonanceDemo.CRM.Patterns}
        presenter={ResonanceDemoWeb.Presenters.Interactive}
        initial_plan={Workspaces.pipeline_review()}
        initial_prompt={@prompt}
        auto_run={true}
        widget_assigns={%{current_user: nil}}
      />
    </div>
    """
  end
end
