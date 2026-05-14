defmodule ResonanceDemoWeb.PlannerEvalLive do
  use ResonanceDemoWeb, :live_view

  alias Resonance.Live.Workspace
  alias Resonance.WorkspacePlan.Section
  alias ResonanceDemo.{Deals, PlannerEval}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        prompts: PlannerEval.prompts(),
        evaluation: nil,
        summary: empty_summary(),
        results: [],
        selected_id: "pipeline_health",
        selected_result: nil,
        workspace_component_id: nil,
        guardrail_result: nil,
        run_id: 0,
        last_run_at: nil,
        data_flash: nil
      )

    if connected?(socket) do
      {:ok, run_eval(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("run_eval", _params, socket) do
    {:noreply, run_eval(socket)}
  end

  def handle_event("select_prompt", %{"id" => id}, socket) do
    {:noreply, select_prompt(socket, id)}
  end

  def handle_event("simulate_deals", _params, socket) do
    {:ok, message} = Deals.simulate_batch()

    if socket.assigns.workspace_component_id do
      send_update(Workspace, id: socket.assigns.workspace_component_id, rerun: true)
    end

    {:noreply, assign(socket, data_flash: message)}
  end

  def handle_event("dismiss_flash", _params, socket) do
    {:noreply, assign(socket, data_flash: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <div class="mb-6 flex flex-col gap-4 border-b border-slate-200 pb-5 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">
            v3 thesis eval
          </p>
          <h1 class="text-2xl font-bold text-slate-950">CRM planner proof</h1>
          <p class="mt-1 max-w-3xl text-sm text-slate-600">
            User intent to typed workspace plan to validation to compiled Phoenix surface.
          </p>
        </div>

        <div class="flex flex-wrap gap-2">
          <button
            phx-click="run_eval"
            class="rounded-md bg-slate-950 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-slate-800"
          >
            Run Eval
          </button>
          <button
            phx-click="simulate_deals"
            class="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 transition-colors hover:bg-slate-50"
          >
            Simulate New Deals
          </button>
        </div>

        <div :if={@run_id > 0} class="text-xs text-slate-500 lg:text-right">
          Run {@run_id} · {format_run_time(@last_run_at)}
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

      <div class="mb-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
        <.metric label="Prompts" value={@summary.total} />
        <.metric label="Valid Plans" value={"#{@summary.valid_plans}/#{@summary.total}"} />
        <.metric label="Compiled" value={"#{@summary.compiled}/#{@summary.total}"} />
        <.metric label="Retries" value={@summary.retried} />
        <.metric label="Capability Misses" value={@summary.invented_capability_failures} />
        <.metric label="Pattern Misses" value={@summary.invented_pattern_failures} />
      </div>

      <section
        :if={@guardrail_result}
        class="mb-6 rounded-md border border-amber-200 bg-amber-50 px-4 py-3"
      >
        <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h2 class="text-sm font-semibold text-amber-950">Validation guardrail</h2>
            <p class="mt-1 text-sm text-amber-800">
              {@guardrail_result.prompt}
            </p>
          </div>
          <span class="rounded bg-amber-100 px-2 py-1 text-xs font-medium text-amber-900">
            {status_label(@guardrail_result.status)}
          </span>
        </div>
        <ul class="mt-3 grid gap-2 text-sm text-amber-900 md:grid-cols-2">
          <li
            :for={error <- validation_errors(@guardrail_result)}
            class="rounded border border-amber-200 bg-white/70 px-3 py-2"
          >
            {format_validation_error(error)}
          </li>
        </ul>
      </section>

      <div class="grid gap-6 lg:grid-cols-[minmax(18rem,24rem)_1fr]">
        <aside class="border-r border-slate-200 pr-0 lg:pr-6">
          <div class="space-y-2">
            <button
              :for={result <- @results}
              type="button"
              phx-click="select_prompt"
              phx-value-id={result.id}
              class={[
                "block w-full rounded-md border px-3 py-3 text-left text-sm transition-colors",
                if(result.id == @selected_id,
                  do: "border-slate-950 bg-slate-950 text-white",
                  else: "border-slate-200 bg-white text-slate-700 hover:border-slate-400"
                )
              ]}
            >
              <div class="flex items-center justify-between gap-3">
                <span class="font-medium">{result.prompt}</span>
                <span class={status_class(result.status)}>{status_label(result.status)}</span>
              </div>
              <div class={[
                "mt-2 text-xs",
                if(result.id == @selected_id, do: "text-slate-200", else: "text-slate-500")
              ]}>
                {result.diagnostics.section_count} sections · {Enum.join(
                  result.diagnostics.primitives,
                  ", "
                )}
              </div>
            </button>
          </div>
        </aside>

        <main>
          <div :if={@selected_result} class="space-y-6">
            <section>
              <div class="mb-3 flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <h2 class="text-lg font-semibold text-slate-950">{@selected_result.prompt}</h2>
                  <p class="mt-1 text-sm text-slate-600">{@selected_result.expectation}</p>
                </div>
                <div class="flex flex-wrap gap-2 text-xs">
                  <span class="rounded bg-slate-100 px-2 py-1 text-slate-700">
                    attempts {@selected_result.attempts}
                  </span>
                  <span class="rounded bg-slate-100 px-2 py-1 text-slate-700">
                    layout {plan_layout(@selected_result)}
                  </span>
                </div>
              </div>

              <div class="overflow-hidden rounded-md border border-slate-200">
                <table class="min-w-full divide-y divide-slate-200 text-sm">
                  <thead class="bg-slate-50 text-left text-xs font-semibold uppercase tracking-wide text-slate-500">
                    <tr>
                      <th class="px-3 py-2">Section</th>
                      <th class="px-3 py-2">Role</th>
                      <th class="px-3 py-2">Pattern</th>
                      <th class="px-3 py-2">Primitive</th>
                      <th class="px-3 py-2">Intent</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-slate-100 bg-white">
                    <tr :for={section <- plan_sections(@selected_result)}>
                      <td class="px-3 py-2 font-medium text-slate-900">
                        {section.title || section.id}
                      </td>
                      <td class="px-3 py-2 text-slate-600">{section.role}</td>
                      <td class="px-3 py-2 text-slate-600">{section.pattern}</td>
                      <td class="px-3 py-2 text-slate-600">{section_primitive(section)}</td>
                      <td class="px-3 py-2 text-slate-600">{section_intent(section)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div
                :if={@selected_result.status != :compiled}
                class="mt-4 rounded-md border border-rose-200 bg-rose-50 p-4"
              >
                <h3 class="text-sm font-semibold text-rose-950">Validation errors</h3>
                <ul class="mt-2 space-y-1 text-sm text-rose-800">
                  <li :for={error <- validation_errors(@selected_result)}>
                    {format_validation_error(error)}
                  </li>
                </ul>
              </div>
            </section>

            <section :if={@selected_result.status == :compiled}>
              <div class="mb-3 flex items-center justify-between">
                <h2 class="text-lg font-semibold text-slate-950">Compiled workspace preview</h2>
                <span class="text-xs text-slate-500">
                  {length(@selected_result.compiled.renderables)} renderables
                </span>
              </div>
              <.live_component
                module={Workspace}
                id={@workspace_component_id}
                resolver={ResonanceDemo.CRM.Resolver}
                patterns={ResonanceDemo.CRM.Patterns}
                presenter={ResonanceDemoWeb.Presenters.Interactive}
                initial_plan={@selected_result.plan}
                initial_prompt={@selected_result.prompt}
                auto_run={true}
                widget_assigns={%{current_user: nil}}
              />
            </section>
          </div>

          <div
            :if={is_nil(@selected_result)}
            class="rounded-md border border-slate-200 bg-slate-50 p-6 text-sm text-slate-600"
          >
            Connect the LiveView to run the planner eval.
          </div>
        </main>
      </div>
    </div>
    """
  end

  defp metric(assigns) do
    ~H"""
    <div class="rounded-md border border-slate-200 bg-white px-3 py-3">
      <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">{@label}</div>
      <div class="mt-1 text-xl font-semibold text-slate-950">{@value}</div>
    </div>
    """
  end

  defp run_eval(socket) do
    evaluation = PlannerEval.evaluate()

    socket
    |> assign(
      evaluation: evaluation,
      guardrail_result: guardrail_result(),
      summary: evaluation.summary,
      results: evaluation.results,
      run_id: socket.assigns.run_id + 1,
      last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> select_prompt(socket.assigns.selected_id)
  end

  defp select_prompt(socket, id) do
    result =
      Enum.find(socket.assigns.results, &(&1.id == id)) || List.first(socket.assigns.results)

    selected_id = if result, do: result.id, else: id

    assign(socket,
      selected_id: selected_id,
      selected_result: result,
      workspace_component_id: workspace_component_id(selected_id, socket.assigns.run_id)
    )
  end

  defp workspace_component_id(nil, _run_id), do: nil
  defp workspace_component_id(id, run_id), do: "planner-eval-workspace-#{id}-#{run_id}"

  defp guardrail_result do
    PlannerEval.guardrail().results |> List.first()
  end

  defp empty_summary do
    %{
      total: 0,
      valid_plans: 0,
      compiled: 0,
      retried: 0,
      invented_capability_failures: 0,
      invented_pattern_failures: 0
    }
  end

  defp plan_layout(%{plan: %{layout: layout}}), do: layout
  defp plan_layout(_result), do: "n/a"

  defp plan_sections(%{plan: %{sections: sections}}) when is_list(sections), do: sections
  defp plan_sections(_result), do: []

  defp section_primitive(%Section{source: {:tool_call, %{name: name}}}), do: name
  defp section_primitive(_section), do: "n/a"

  defp section_intent(%Section{source: {:tool_call, %{arguments: arguments}}}) do
    dataset = Map.get(arguments, "dataset") || Map.get(arguments, :dataset)
    dimensions = Map.get(arguments, "dimensions") || Map.get(arguments, :dimensions) || []
    measures = Map.get(arguments, "measures") || Map.get(arguments, :measures) || []

    [dataset, Enum.join(dimensions, "+"), Enum.join(measures, "+")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp section_intent(_section), do: "n/a"

  defp validation_errors(%{errors: {:validation_failed, errors}}) when is_list(errors), do: errors
  defp validation_errors(_result), do: []

  defp format_validation_error(%{path: path, code: code, message: message}) do
    "#{Enum.map_join(path, ".", &to_string/1)} #{code}: #{message}"
  end

  defp status_label(:compiled), do: "compiled"
  defp status_label(:invalid_plan), do: "invalid"
  defp status_label(:compile_failed), do: "failed"
  defp status_label(status), do: to_string(status)

  defp status_class(:compiled), do: "rounded bg-emerald-100 px-2 py-1 text-xs text-emerald-800"
  defp status_class(:invalid_plan), do: "rounded bg-rose-100 px-2 py-1 text-xs text-rose-800"
  defp status_class(_status), do: "rounded bg-amber-100 px-2 py-1 text-xs text-amber-800"

  defp format_run_time(nil), do: "not run"
  defp format_run_time(%DateTime{} = time), do: Calendar.strftime(time, "%H:%M:%S UTC")
end
