defmodule ResonanceDemoWeb.Widgets.FilterableLeaderboard do
  @moduledoc """
  Interactive deals leaderboard. Renders a ranked list of deals and lets the
  user filter by stage without going back through the LLM.

  This is the v2 validation widget — it uses every piece of the new contract:

  - `use Resonance.Widget` (the behaviour)
  - `accepts_results/0`, `capabilities/0`, `example_renderable/0`
  - reads `:renderable` from `update/2` and props from the underlying Result
  - `handle_event("filter_stage", ...)` calls `Resonance.refine/3` to re-resolve

  When the playground renders this widget against `example_renderable/0`, the
  filter buttons are still visible — they only have side effects when the
  widget is mounted inside `Live.Report` with a real resolver in context.
  """

  use Resonance.Widget

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)

  @impl Resonance.Widget
  def accepts_results, do: [:ranking]

  @impl Resonance.Widget
  def capabilities, do: [:refine]

  @impl Resonance.Widget
  def live_renderable(context) do
    intent = %Resonance.QueryIntent{
      dataset: "deals",
      measures: ["sum(value)"],
      sort: %{field: "sum(value)", direction: :desc},
      limit: 10
    }

    case Resonance.Primitive.resolve_with_intent(:ranking, intent, "Top deals", context) do
      {:ok, %Resonance.Result{} = result} ->
        {:ok,
         %Resonance.Renderable{
           id: "live-filterable-leaderboard",
           type: "rank_entities",
           component: __MODULE__,
           props: %{title: result.title, data: result.data},
           status: :ready,
           render_via: :live,
           primitive: "rank_entities",
           result: result
         }}

      {:error, _} = error ->
        error
    end
  end

  @impl Resonance.Widget
  def example_renderable do
    %Resonance.Renderable{
      id: "example-filterable-leaderboard",
      type: "rank_entities",
      component: __MODULE__,
      status: :ready,
      render_via: :live,
      primitive: "rank_entities",
      props: %{
        title: "Top deals (example)",
        data: [
          %{label: "Acme retainer", value: 480_000, stage: "negotiation"},
          %{label: "Globex platform deal", value: 410_000, stage: "proposal"},
          %{label: "Initech Q3 expansion", value: 365_000, stage: "discovery"},
          %{label: "Umbrella renewal", value: 290_000, stage: "closed_won"},
          %{label: "Stark Industries pilot", value: 240_000, stage: "discovery"}
        ]
      },
      result: %Resonance.Result{
        kind: :ranking,
        title: "Top deals (example)",
        data: [],
        intent: %Resonance.QueryIntent{
          dataset: "deals",
          measures: ["sum(value)"],
          filters: nil,
          sort: %{field: "sum(value)", direction: :desc},
          limit: 10
        }
      }
    }
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, active_stage: nil, refine_error: nil, stages: @stages)}
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: renderable} = assigns, socket) do
    {:ok,
     socket
     |> assign(:renderable, renderable)
     |> assign(:resolver, assigns[:resolver])
     |> assign(:current_user, assigns[:current_user])
     |> assign(:presenter, assigns[:presenter])
     |> assign_active_stage_from_intent(renderable)}
  end

  defp assign_active_stage_from_intent(socket, %Resonance.Renderable{
         result: %Resonance.Result{intent: %Resonance.QueryIntent{filters: filters}}
       }) do
    stage =
      case filters do
        list when is_list(list) ->
          case Enum.find(list, fn f -> f.field == "stage" end) do
            %{value: s} -> s
            _ -> nil
          end

        _ ->
          nil
      end

    assign(socket, :active_stage, stage)
  end

  defp assign_active_stage_from_intent(socket, _), do: assign(socket, :active_stage, nil)

  @impl Phoenix.LiveComponent
  def handle_event("filter_stage", %{"stage" => stage}, socket) do
    refine_with(socket, fn intent ->
      filters = drop_stage(intent.filters) ++ [%{field: "stage", op: "=", value: stage}]
      %{intent | filters: filters}
    end)
  end

  def handle_event("clear_filter", _params, socket) do
    refine_with(socket, fn intent ->
      case drop_stage(intent.filters) do
        [] -> %{intent | filters: nil}
        rest -> %{intent | filters: rest}
      end
    end)
  end

  defp refine_with(socket, intent_fn) do
    context = %{
      resolver: socket.assigns[:resolver],
      current_user: socket.assigns[:current_user],
      presenter: socket.assigns[:presenter]
    }

    if is_nil(context.resolver) do
      # Playground / no-context scenario — surface a clear message instead of crashing.
      {:noreply,
       assign(socket,
         refine_error: "Filter only works inside Live.Report with a resolver in context."
       )}
    else
      case Resonance.refine(socket.assigns.renderable, intent_fn, context) do
        {:ok, refined} ->
          {:noreply,
           socket
           |> assign(:renderable, refined)
           |> assign(:refine_error, nil)
           |> assign_active_stage_from_intent(refined)}

        {:error, reason} ->
          {:noreply, assign(socket, :refine_error, format_error(reason))}
      end
    end
  end

  defp drop_stage(nil), do: []
  defp drop_stage(filters), do: Enum.reject(filters, fn f -> f.field == "stage" end)

  defp format_error({:invalid_field, field, msg}), do: "Invalid #{field}: #{msg}"
  defp format_error({:unsupported_query, dataset}), do: "Cannot filter #{dataset} this way."
  defp format_error(other), do: "Refine failed: #{inspect(other)}"

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-widget filterable-leaderboard rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@renderable.props[:title] || "Leaderboard"}</h3>
        <span class="text-xs uppercase tracking-wide text-gray-400">Interactive</span>
      </div>

      <div class="mb-4 flex flex-wrap items-center gap-2">
        <span class="text-xs font-medium text-gray-500 mr-1">Stage:</span>
        <button
          type="button"
          phx-click="clear_filter"
          phx-target={@myself}
          class={[
            "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
            if(is_nil(@active_stage),
              do: "bg-blue-50 border-blue-300 text-blue-700",
              else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
            )
          ]}
        >
          all
        </button>
        <%= for stage <- @stages do %>
          <button
            type="button"
            phx-click="filter_stage"
            phx-value-stage={stage}
            phx-target={@myself}
            class={[
              "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
              if(@active_stage == stage,
                do: "bg-blue-50 border-blue-300 text-blue-700",
                else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
              )
            ]}
          >
            {stage}
          </button>
        <% end %>
      </div>

      <div :if={@refine_error} class="mb-3 px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-xs text-amber-800">
        {@refine_error}
      </div>

      <ol class="space-y-1.5">
        <%= for {row, idx} <- Enum.with_index(rows(@renderable), 1) do %>
          <li class="flex items-baseline justify-between py-1.5 px-2 rounded hover:bg-gray-50">
            <div class="flex items-baseline gap-3 min-w-0">
              <span class="text-xs font-mono text-gray-400 w-6">{idx}.</span>
              <span class="text-sm text-gray-900 truncate">{row_label(row)}</span>
            </div>
            <span class="text-sm font-medium text-gray-700 tabular-nums">${format_value(row_value(row))}</span>
          </li>
        <% end %>
        <li :if={rows(@renderable) == []} class="text-sm text-gray-400 italic px-2 py-3">
          No results for this filter.
        </li>
      </ol>
    </div>
    """
  end

  defp rows(%Resonance.Renderable{props: props}) do
    props[:data] || props["data"] || []
  end

  defp row_label(row), do: row[:label] || row["label"] || "—"
  defp row_value(row), do: row[:value] || row["value"] || 0

  defp format_value(n) when is_number(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_value(n) when is_number(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_value(_), do: "—"
end
