defmodule ResonanceDemoWeb.WorkspaceLive do
  use ResonanceDemoWeb, :live_view

  alias Resonance.{Renderable, WorkspaceCompiler, WorkspaceSnapshot}
  alias ResonanceDemo.{Deals, Workspaces}

  @prompt "Give me a full pipeline review with trends and top accounts"

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        renderables: [],
        snapshot_json: nil,
        snapshot_fingerprint: nil,
        original_prompt: @prompt,
        loading: true,
        error: nil,
        data_flash: nil,
        rerun_count: 0,
        last_refreshed_at: nil
      )

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Deals.pubsub(), Deals.topic())
      send(self(), :compile_workspace)
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("rerun_workspace", _params, socket) do
    {:noreply, rerun_saved_workspace(socket)}
  end

  def handle_event("simulate_deals", _params, socket) do
    {:ok, message} = Deals.simulate_batch()

    {:noreply,
     assign(socket,
       data_flash: message,
       loading: true,
       error: nil
     )}
  end

  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, data_flash: nil)}
  end

  @impl true
  def handle_info(:compile_workspace, socket) do
    case WorkspaceCompiler.compile(Workspaces.pipeline_review(), workspace_context()) do
      {:ok, compiled} ->
        {:ok, snapshot_json} =
          compiled
          |> WorkspaceSnapshot.from_compiled(original_prompt: @prompt)
          |> WorkspaceSnapshot.to_json()

        {:noreply,
         assign(socket,
           renderables: compiled.renderables,
           snapshot_json: snapshot_json,
           snapshot_fingerprint: WorkspaceSnapshot.fingerprint(compiled.plan),
           loading: false,
           error: nil,
           last_refreshed_at: DateTime.utc_now()
         )}

      {:error, reason} ->
        {:noreply, assign(socket, loading: false, error: reason)}
    end
  end

  def handle_info({:deals_changed, _meta}, socket) do
    {:noreply, rerun_saved_workspace(socket)}
  end

  def handle_info({:workspace_rerun, {:component_ready, %Renderable{} = renderable}}, socket) do
    socket =
      socket
      |> assign(:renderables, replace_renderable(socket.assigns.renderables, renderable))
      |> route_renderable_update(renderable)

    {:noreply, socket}
  end

  def handle_info({:workspace_rerun, :done}, socket) do
    {:noreply,
     assign(socket,
       loading: false,
       error: nil,
       rerun_count: socket.assigns.rerun_count + 1,
       last_refreshed_at: DateTime.utc_now()
     )}
  end

  def handle_info({:workspace_rerun, {:error, reason}}, socket) do
    {:noreply, assign(socket, loading: false, error: reason)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div class="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">Workspace</p>
          <h1 class="text-2xl font-bold text-slate-950">Pipeline review</h1>
          <p class="mt-1 max-w-2xl text-sm text-slate-600">{@original_prompt}</p>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            phx-click="rerun_workspace"
            disabled={@loading or is_nil(@snapshot_json)}
            class="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition-colors hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {if @loading, do: "Refreshing...", else: "Rerun Workspace"}
          </button>
          <button
            phx-click="simulate_deals"
            disabled={@loading or is_nil(@snapshot_json)}
            class="rounded-md bg-slate-950 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Simulate New Deals
          </button>
        </div>
      </div>

      <div class="mb-6 grid gap-3 text-sm sm:grid-cols-3">
        <div class="rounded-md border border-slate-200 bg-white px-4 py-3">
          <div class="text-xs font-medium uppercase tracking-wide text-slate-500">Snapshot</div>
          <div class="mt-1 truncate font-mono text-xs text-slate-700" title={@snapshot_fingerprint || "pending"}>
            {short_fingerprint(@snapshot_fingerprint)}
          </div>
        </div>
        <div class="rounded-md border border-slate-200 bg-white px-4 py-3">
          <div class="text-xs font-medium uppercase tracking-wide text-slate-500">Sections</div>
          <div class="mt-1 text-slate-900">{length(@renderables)}</div>
        </div>
        <div class="rounded-md border border-slate-200 bg-white px-4 py-3">
          <div class="text-xs font-medium uppercase tracking-wide text-slate-500">Reruns</div>
          <div class="mt-1 text-slate-900">{@rerun_count}</div>
        </div>
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

      <div :if={@error} class="mb-4 rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
        {format_error(@error)}
      </div>

      <div :if={@loading} class="mb-4 rounded-md border border-slate-200 bg-slate-50 px-4 py-3 text-sm text-slate-600">
        Refreshing workspace...
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <div
          :for={renderable <- @renderables}
          id={"workspace-section-#{renderable.id}"}
          class={section_class(renderable)}
        >
          <%= if renderable.render_via == :live and renderable.status == :ready do %>
            <.live_component
              module={renderable.component}
              id={renderable.id}
              renderable={renderable}
              current_user={nil}
            />
          <% else %>
            {render_component(renderable)}
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp rerun_saved_workspace(%{assigns: %{snapshot_json: nil}} = socket), do: socket

  defp rerun_saved_workspace(socket) do
    case WorkspaceSnapshot.from_json(socket.assigns.snapshot_json) do
      {:ok, snapshot} ->
        parent = self()

        WorkspaceSnapshot.rerun(snapshot, workspace_context(), fn event ->
          send(parent, {:workspace_rerun, event})
        end)

        assign(socket, loading: true, error: nil)

      {:error, reason} ->
        assign(socket, loading: false, error: reason)
    end
  end

  defp workspace_context do
    %{
      resolver: ResonanceDemo.CRM.Resolver,
      presenter: ResonanceDemoWeb.Presenters.Interactive
    }
  end

  defp replace_renderable([], renderable), do: [renderable]

  defp replace_renderable(renderables, renderable) do
    if Enum.any?(renderables, &(&1.id == renderable.id)) do
      Enum.map(renderables, fn existing ->
        if existing.id == renderable.id, do: renderable, else: existing
      end)
    else
      renderables ++ [renderable]
    end
  end

  defp route_renderable_update(
         socket,
         %Renderable{render_via: :live, component: module, id: id} = renderable
       ) do
    send_update(module, id: id, renderable: renderable)
    socket
  end

  defp route_renderable_update(socket, %Renderable{render_via: :function} = renderable) do
    push_chart_update(socket, renderable)
  end

  defp push_chart_update(socket, %Renderable{component: component, id: id} = renderable) do
    if function_exported?(component, :chart_dom_id, 1) do
      push_event(socket, "resonance:update-chart", %{
        id: component.chart_dom_id(id),
        data: renderable.props[:data] || renderable.props["data"] || []
      })
    else
      socket
    end
  end

  defp render_component(%Renderable{status: :error, error: error}) do
    assigns = %{error: format_error(error)}

    ~H"""
    <div class="rounded-md border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
      {@error}
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props, id: id}) do
    assigns = %{__changed__: nil, props: props, renderable_id: id}
    component.render(assigns)
  end

  defp render_component(_renderable), do: nil

  defp section_class(%Renderable{type: "summarize_findings"}) do
    "rounded-md border border-slate-200 bg-white p-4 lg:col-span-2"
  end

  defp section_class(_renderable), do: "rounded-md border border-slate-200 bg-white p-4"

  defp short_fingerprint(nil), do: "Pending"
  defp short_fingerprint(fingerprint), do: String.slice(fingerprint, 0, 12)

  defp format_error({:validation_failed, errors}) do
    "Workspace validation failed: #{Enum.map_join(errors, ", ", & &1.message)}"
  end

  defp format_error(reason), do: inspect(reason)
end
