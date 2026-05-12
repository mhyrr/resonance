defmodule Resonance.Live.Workspace do
  @moduledoc """
  LiveComponent surface for v3 adaptive workspaces.

  `Workspace` owns the UI lifecycle for planning, resolving, rerunning, saving,
  and refining a workspace. The consuming app still owns data access,
  persistence, authorization, and mutations.
  """

  use Phoenix.LiveComponent

  alias Resonance.{
    Planner,
    Renderable,
    WorkspaceCompiler,
    WorkspaceContext,
    WorkspacePlan,
    WorkspaceSnapshot
  }

  @busy_statuses [:planning, :resolving, :saving]

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       status: :idle,
       operation: nil,
       busy: false,
       prompt: "",
       last_prompt: nil,
       ignored_prompt: nil,
       plan: nil,
       planner_result: nil,
       compiled: nil,
       renderables: [],
       snapshot: nil,
       snapshot_json: nil,
       workspace_context: nil,
       rerun_count: 0,
       error: nil,
       save_status: nil,
       save_result: nil,
       auto_started: false,
       resolver: nil,
       current_user: nil,
       presenter: nil,
       patterns: nil,
       widget_assigns: %{},
       context: %{},
       initial_plan: nil,
       initial_prompt: nil,
       auto_run: false,
       on_save: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> apply_base_assigns(assigns)
     |> handle_snapshot_assign(assigns)
     |> handle_planned(assigns)
     |> handle_resolving(assigns)
     |> handle_compiled(assigns)
     |> handle_failed(assigns)
     |> handle_rerun_event(assigns)
     |> handle_external_rerun(assigns)
     |> handle_auto_run()}
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) do
    prompt = String.trim(prompt || "")

    cond do
      prompt == "" ->
        {:noreply, socket}

      busy?(socket) ->
        {:noreply, assign(socket, ignored_prompt: prompt)}

      true ->
        {:noreply, start_planning(socket, prompt)}
    end
  end

  def handle_event("rerun_workspace", _params, socket) do
    if busy?(socket) or is_nil(socket.assigns.snapshot) do
      {:noreply, socket}
    else
      {:noreply, start_rerun(socket)}
    end
  end

  def handle_event("save_workspace", _params, socket) do
    if busy?(socket) or is_nil(socket.assigns.snapshot) do
      {:noreply, socket}
    else
      {:noreply, save_snapshot(socket)}
    end
  end

  def handle_event("clear", _params, socket) do
    {:noreply,
     assign(socket,
       status: :idle,
       operation: nil,
       busy: false,
       prompt: "",
       last_prompt: nil,
       ignored_prompt: nil,
       plan: nil,
       planner_result: nil,
       compiled: nil,
       renderables: [],
       snapshot: nil,
       snapshot_json: nil,
       workspace_context: nil,
       rerun_count: 0,
       error: nil,
       save_status: nil,
       save_result: nil,
       auto_started: false
     )}
  end

  defp apply_base_assigns(socket, assigns) do
    socket
    |> assign(:id, assigns.id)
    |> assign_if_present(assigns, :resolver)
    |> assign_if_present(assigns, :current_user)
    |> assign_if_present(assigns, :presenter)
    |> assign_if_present(assigns, :patterns)
    |> assign_if_present(assigns, :widget_assigns)
    |> assign_if_present(assigns, :context)
    |> assign_if_present(assigns, :initial_plan)
    |> assign_if_present(assigns, :initial_prompt)
    |> assign_if_present(assigns, :auto_run)
    |> assign_if_present(assigns, :on_save)
    |> maybe_set_initial_prompt()
  end

  defp assign_if_present(socket, assigns, key) do
    if Map.has_key?(assigns, key), do: assign(socket, key, Map.fetch!(assigns, key)), else: socket
  end

  defp maybe_set_initial_prompt(socket) do
    if blank?(socket.assigns.prompt) and is_binary(socket.assigns.initial_prompt) do
      assign(socket, :prompt, socket.assigns.initial_prompt)
    else
      socket
    end
  end

  defp handle_snapshot_assign(socket, %{snapshot: %WorkspaceSnapshot{} = snapshot}) do
    assign_snapshot(socket, snapshot)
  end

  defp handle_snapshot_assign(socket, %{workspace_snapshot: %WorkspaceSnapshot{} = snapshot}) do
    assign_snapshot(socket, snapshot)
  end

  defp handle_snapshot_assign(socket, %{snapshot_json: json}) when is_binary(json) do
    if json != socket.assigns.snapshot_json do
      case WorkspaceSnapshot.from_json(json) do
        {:ok, snapshot} -> assign_snapshot(socket, snapshot)
        {:error, reason} -> fail(socket, reason)
      end
    else
      socket
    end
  end

  defp handle_snapshot_assign(socket, _assigns), do: socket

  defp handle_planned(socket, %{
         resonance_workspace_planned: %{plan: %WorkspacePlan{} = plan} = result
       }) do
    assign(socket,
      status: :resolving,
      operation: :resolve,
      plan: plan,
      planner_result: result,
      error: nil
    )
  end

  defp handle_planned(socket, _assigns), do: socket

  defp handle_resolving(socket, %{resonance_workspace_resolving: true}) do
    assign(socket, status: :resolving, operation: :resolve, busy: true)
  end

  defp handle_resolving(socket, _assigns), do: socket

  defp handle_compiled(socket, %{
         resonance_workspace_compiled: %{compiled: compiled, prompt: prompt}
       }) do
    snapshot = WorkspaceSnapshot.from_compiled(compiled, original_prompt: prompt)

    case WorkspaceSnapshot.to_json(snapshot) do
      {:ok, snapshot_json} ->
        workspace_context = WorkspaceContext.from_compiled(compiled, original_prompt: prompt)

        assign(socket,
          status: :ready,
          operation: nil,
          busy: false,
          prompt: prompt || socket.assigns.prompt,
          last_prompt: prompt,
          ignored_prompt: nil,
          plan: compiled.plan,
          compiled: compiled,
          renderables: compiled.renderables,
          snapshot: snapshot,
          snapshot_json: snapshot_json,
          workspace_context: workspace_context,
          error: nil,
          save_status: nil,
          save_result: nil
        )

      {:error, reason} ->
        fail(socket, reason)
    end
  end

  defp handle_compiled(socket, _assigns), do: socket

  defp handle_failed(socket, %{resonance_workspace_failed: reason}) do
    fail(socket, reason)
  end

  defp handle_failed(socket, _assigns), do: socket

  defp handle_rerun_event(socket, %{
         resonance_workspace_rerun_event: {:component_ready, %Renderable{} = renderable}
       }) do
    socket
    |> assign(:renderables, replace_renderable(socket.assigns.renderables, renderable))
    |> route_renderable_update(renderable)
  end

  defp handle_rerun_event(socket, %{resonance_workspace_rerun_event: :done}) do
    case compiled_from_assigns(socket) do
      {:ok, compiled} ->
        prompt =
          socket.assigns.last_prompt ||
            (socket.assigns.snapshot && socket.assigns.snapshot.original_prompt)

        socket
        |> handle_compiled(%{
          resonance_workspace_compiled: %{compiled: compiled, prompt: prompt}
        })
        |> update(:rerun_count, &(&1 + 1))

      {:error, reason} ->
        fail(socket, reason)
    end
  end

  defp handle_rerun_event(socket, %{resonance_workspace_rerun_event: {:error, reason}}) do
    fail(socket, reason)
  end

  defp handle_rerun_event(socket, _assigns), do: socket

  defp handle_external_rerun(socket, %{rerun: true}) do
    if connected_socket?(socket) and not busy?(socket) and socket.assigns.snapshot do
      start_rerun(socket)
    else
      socket
    end
  end

  defp handle_external_rerun(socket, _assigns), do: socket

  defp handle_auto_run(socket) do
    if connected_socket?(socket) and socket.assigns.auto_run and not busy?(socket) and
         not socket.assigns.auto_started and
         socket.assigns.initial_plan do
      socket
      |> assign(auto_started: true)
      |> start_resolving(
        socket.assigns.initial_plan,
        socket.assigns.initial_prompt || socket.assigns.prompt
      )
    else
      socket
    end
  end

  defp start_planning(socket, prompt) do
    context = build_context(socket)
    component_id = socket.assigns.id
    lv_pid = self()

    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      metadata = %{component_id: component_id}

      planning_result =
        :telemetry.span([:resonance, :workspace, :planning], metadata, fn ->
          result = Planner.plan_result(prompt, context)
          {result, Map.put(metadata, :status, result_status(result))}
        end)

      case planning_result do
        {:ok, planner_result} ->
          send_component_update(lv_pid, component_id, resonance_workspace_planned: planner_result)
          send_component_update(lv_pid, component_id, resonance_workspace_resolving: true)
          compile_and_send(lv_pid, component_id, planner_result.plan, prompt, context)

        {:error, planner_result} ->
          send_component_update(lv_pid, component_id,
            resonance_workspace_failed: planner_result.reason
          )
      end
    end)

    assign(socket,
      status: :planning,
      operation: :plan,
      busy: true,
      prompt: prompt,
      ignored_prompt: nil,
      error: nil,
      save_status: nil,
      save_result: nil
    )
  end

  defp start_resolving(socket, %WorkspacePlan{} = plan, prompt) do
    context = build_context(socket)
    component_id = socket.assigns.id
    lv_pid = self()

    Task.Supervisor.start_child(Resonance.TaskSupervisor, fn ->
      send_component_update(lv_pid, component_id, resonance_workspace_resolving: true)
      compile_and_send(lv_pid, component_id, plan, prompt, context)
    end)

    assign(socket,
      status: :resolving,
      operation: :resolve,
      busy: true,
      prompt: prompt || socket.assigns.prompt,
      plan: plan,
      ignored_prompt: nil,
      error: nil
    )
  end

  defp start_rerun(socket) do
    context = build_context(socket)
    component_id = socket.assigns.id
    lv_pid = self()

    WorkspaceSnapshot.rerun(socket.assigns.snapshot, context, fn event ->
      send_component_update(lv_pid, component_id, resonance_workspace_rerun_event: event)
    end)

    assign(socket, status: :resolving, operation: :rerun, busy: true, error: nil)
  end

  defp compile_and_send(lv_pid, component_id, %WorkspacePlan{} = plan, prompt, context) do
    metadata = %{component_id: component_id, section_count: length(plan.sections)}

    compile_result =
      :telemetry.span([:resonance, :workspace, :resolve], metadata, fn ->
        result = WorkspaceCompiler.compile(plan, context)
        {result, Map.put(metadata, :status, result_status(result))}
      end)

    case compile_result do
      {:ok, compiled} ->
        send_component_update(lv_pid, component_id,
          resonance_workspace_compiled: %{compiled: compiled, prompt: prompt}
        )

      {:error, reason} ->
        send_component_update(lv_pid, component_id, resonance_workspace_failed: reason)
    end
  end

  defp send_component_update(pid, component_id, assigns) do
    Phoenix.LiveView.send_update(pid, __MODULE__, Keyword.put(assigns, :id, component_id))
  end

  defp save_snapshot(socket) do
    assign(socket, status: :saving, busy: true, save_status: :saving)
    |> do_save_snapshot()
  end

  defp do_save_snapshot(socket) do
    case call_save(socket.assigns.on_save, socket.assigns.snapshot) do
      {:ok, result} ->
        assign(socket,
          status: :ready,
          operation: nil,
          busy: false,
          save_status: :saved,
          save_result: result,
          error: nil
        )

      {:error, reason} ->
        fail(socket, reason)
    end
  end

  defp call_save(nil, %WorkspaceSnapshot{} = snapshot), do: {:ok, snapshot}

  defp call_save(fun, %WorkspaceSnapshot{} = snapshot) when is_function(fun, 1) do
    case fun.(snapshot) do
      :ok -> {:ok, snapshot}
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  end

  defp call_save(_callback, _snapshot), do: {:error, :missing_workspace_snapshot}

  defp build_context(socket) do
    base_context = if is_map(socket.assigns.context), do: socket.assigns.context, else: %{}

    base_context
    |> Map.merge(%{
      resolver: socket.assigns.resolver,
      current_user: socket.assigns.current_user,
      presenter: socket.assigns.presenter,
      patterns: socket.assigns.patterns,
      workspace_context: current_workspace_context(socket)
    })
    |> drop_nil_values()
  end

  defp current_workspace_context(
         %{assigns: %{compiled: %{plan: %WorkspacePlan{}} = compiled}} = socket
       ) do
    WorkspaceContext.from_compiled(compiled, original_prompt: socket.assigns.last_prompt)
  end

  defp current_workspace_context(%{assigns: %{snapshot: %WorkspaceSnapshot{} = snapshot}}) do
    WorkspaceContext.from_snapshot(snapshot)
  end

  defp current_workspace_context(%{assigns: %{workspace_context: %WorkspaceContext{} = context}}) do
    context
  end

  defp current_workspace_context(_socket), do: nil

  defp assign_snapshot(socket, %WorkspaceSnapshot{} = snapshot) do
    assign(socket,
      status: :ready,
      operation: nil,
      busy: false,
      prompt: snapshot.original_prompt || socket.assigns.prompt,
      last_prompt: snapshot.original_prompt,
      plan: snapshot.plan,
      compiled: nil,
      renderables: [],
      snapshot: snapshot,
      snapshot_json: snapshot_json(snapshot),
      workspace_context: WorkspaceContext.from_snapshot(snapshot),
      error: nil
    )
  end

  defp snapshot_json(%WorkspaceSnapshot{} = snapshot) do
    case WorkspaceSnapshot.to_json(snapshot) do
      {:ok, json} -> json
      {:error, _reason} -> nil
    end
  end

  defp fail(socket, reason) do
    assign(socket,
      status: :failed,
      operation: nil,
      busy: false,
      error: reason,
      save_status: nil
    )
  end

  defp busy?(socket), do: socket.assigns.status in @busy_statuses or socket.assigns.busy

  defp connected_socket?(socket), do: Phoenix.LiveView.connected?(socket)

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

  defp compiled_from_assigns(%{
         assigns: %{plan: %WorkspacePlan{} = plan, renderables: renderables}
       }) do
    sections =
      plan.sections
      |> Enum.zip(renderables)
      |> Enum.map(fn {section, renderable} ->
        %{
          id: section.id,
          role: section.role,
          pattern: section.pattern,
          section: section,
          renderable: renderable
        }
      end)

    {:ok, %{plan: plan, sections: sections, renderables: renderables}}
  end

  defp compiled_from_assigns(_socket), do: {:error, :missing_workspace_plan}

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, _}), do: :error
  defp result_status(_other), do: :unknown

  defp drop_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="resonance-workspace" data-status={@status}>
      <form phx-submit="generate" phx-target={@myself} class="resonance-workspace-prompt">
        <input
          type="text"
          name="prompt"
          id={"#{@id}-prompt"}
          value={@prompt}
          placeholder={prompt_placeholder(@status)}
          class="resonance-prompt-input"
          disabled={@busy}
          autocomplete="off"
          phx-hook="ResonancePromptInput"
        />
        <button type="submit" class="resonance-generate-btn" disabled={@busy}>
          {submit_label(@status)}
        </button>
      </form>

      <div class="resonance-workspace-actions">
        <button
          type="button"
          phx-click="rerun_workspace"
          phx-target={@myself}
          disabled={@busy or is_nil(@snapshot)}
          class="resonance-workspace-action"
        >
          Rerun
        </button>
        <button
          type="button"
          phx-click="save_workspace"
          phx-target={@myself}
          disabled={@busy or is_nil(@snapshot)}
          class="resonance-workspace-action"
        >
          {if @save_status == :saved, do: "Saved", else: "Save"}
        </button>
      </div>

      <div :if={@status in [:planning, :resolving, :saving]} class="resonance-loading">
        <div class="resonance-loading-indicator">{status_label(@status)}</div>
      </div>

      <div :if={@ignored_prompt} class="resonance-error-banner">
        <p>Workspace is busy. Try again when it finishes.</p>
      </div>

      <div :if={@error} class="resonance-error-banner">
        <p>{format_error(@error)}</p>
      </div>

      <div :if={@snapshot} class="resonance-workspace-meta">
        <span>Snapshot {short_fingerprint(@snapshot.fingerprint)}</span>
        <span>{length(@renderables)} sections</span>
        <span>{@rerun_count}</span>
      </div>

      <div :if={@renderables != []} class="resonance-workspace-sections">
        <%= for renderable <- @renderables do %>
          <section id={"#{@id}-section-#{renderable.id}"} class={section_class(renderable)}>
            <%= if renderable.render_via == :live and renderable.status == :ready do %>
              <.live_component
                module={renderable.component}
                id={renderable.id}
                renderable={renderable}
                {@widget_assigns}
              />
            <% else %>
              {render_component(renderable)}
            <% end %>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_component(%Renderable{status: :error, error: error}) do
    assigns = %{error: format_error(error)}

    ~H"""
    <div class="resonance-component resonance-error">
      <p class="resonance-error-text">{@error}</p>
    </div>
    """
  end

  defp render_component(%Renderable{status: :ready, component: component, props: props, id: id}) do
    assigns = %{__changed__: nil, props: props, renderable_id: id}
    component.render(assigns)
  end

  defp render_component(_renderable), do: nil

  defp prompt_placeholder(:ready), do: "Refine this workspace"
  defp prompt_placeholder(_status), do: "What workspace do you need"

  defp submit_label(:ready), do: "Refine"
  defp submit_label(:planning), do: "Planning..."
  defp submit_label(:resolving), do: "Resolving..."
  defp submit_label(:saving), do: "Saving..."
  defp submit_label(_status), do: "Generate"

  defp status_label(:planning), do: "Planning workspace..."
  defp status_label(:resolving), do: "Resolving workspace..."
  defp status_label(:saving), do: "Saving workspace..."
  defp status_label(_status), do: ""

  defp section_class(%Renderable{type: "summarize_findings"}),
    do: "resonance-workspace-section resonance-workspace-section-wide"

  defp section_class(_renderable), do: "resonance-workspace-section"

  defp short_fingerprint(nil), do: "pending"
  defp short_fingerprint(fingerprint), do: String.slice(fingerprint, 0, 12)

  defp format_error({:validation_failed, errors}) when is_list(errors) do
    "Workspace validation failed: #{Enum.map_join(errors, ", ", & &1.message)}"
  end

  defp format_error({:planning_failed, reason, _details}),
    do: "Workspace planning failed: #{reason}"

  defp format_error({:api_error, status, _}), do: "API error (#{status})"
  defp format_error({:request_failed, _}), do: "Could not reach the LLM provider."
  defp format_error({:unsupported_query, dataset}), do: "Unsupported query for #{dataset}."
  defp format_error({:query_failed, msg}) when is_binary(msg), do: "Data query failed: #{msg}"
  defp format_error({:invalid_field, field, msg}), do: "Invalid #{field}: #{msg}"
  defp format_error(reason), do: inspect(reason)
end
