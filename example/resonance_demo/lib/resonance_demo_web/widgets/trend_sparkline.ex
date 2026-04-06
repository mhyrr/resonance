defmodule ResonanceDemoWeb.Widgets.TrendSparkline do
  @moduledoc """
  Interactive trend sparkline.

  Renders a `:comparison` Result (deals grouped by quarter) as an inline SVG
  sparkline with min/max/latest annotations and lets the user narrow the
  trend to a single deal stage without an LLM round-trip.

  The interaction is a `Resonance.refine/3` call that adds (or removes) a
  `stage = ...` filter on the existing `QueryIntent`. The widget reads its
  active stage straight off the refined intent so the chips stay accurate
  after a refresh.
  """

  use Resonance.Widget

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)

  @impl Resonance.Widget
  def accepts_results, do: [:comparison]

  @impl Resonance.Widget
  def capabilities, do: [:refine]

  @impl Resonance.Widget
  def live_renderable(context) do
    intent = %Resonance.QueryIntent{
      dataset: "deals",
      measures: ["sum(value)"],
      dimensions: ["quarter"]
    }

    case Resonance.Primitive.resolve_with_intent(
           :comparison,
           intent,
           "Pipeline value over time",
           context
         ) do
      {:ok, %Resonance.Result{} = result} ->
        {:ok,
         %Resonance.Renderable{
           id: "live-trend-sparkline",
           type: "compare_over_time",
           component: __MODULE__,
           props: %{title: result.title, data: result.data},
           status: :ready,
           render_via: :live,
           primitive: "compare_over_time",
           result: result
         }}

      {:error, _} = error ->
        error
    end
  end

  @impl Resonance.Widget
  def example_renderable do
    rows = [
      %{label: "2025-Q1", period: "2025-Q1", value: 820_000},
      %{label: "2025-Q2", period: "2025-Q2", value: 740_000},
      %{label: "2025-Q3", period: "2025-Q3", value: 1_120_000},
      %{label: "2025-Q4", period: "2025-Q4", value: 1_360_000},
      %{label: "2026-Q1", period: "2026-Q1", value: 1_510_000},
      %{label: "2026-Q2", period: "2026-Q2", value: 1_680_000}
    ]

    %Resonance.Renderable{
      id: "example-trend-sparkline",
      type: "compare_over_time",
      component: __MODULE__,
      status: :ready,
      render_via: :live,
      primitive: "compare_over_time",
      props: %{title: "Pipeline value over time (example)", data: rows},
      result: %Resonance.Result{
        kind: :comparison,
        title: "Pipeline value over time (example)",
        data: rows,
        intent: %Resonance.QueryIntent{
          dataset: "deals",
          measures: ["sum(value)"],
          dimensions: ["quarter"],
          filters: nil
        }
      }
    }
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, stages: @stages, refine_error: nil, active_stage: nil)}
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
  def handle_event("set_stage", %{"stage" => stage}, socket) do
    refine_with(socket, fn intent ->
      filters = drop_stage(intent.filters) ++ [%{field: "stage", op: "=", value: stage}]
      %{intent | filters: filters}
    end)
  end

  def handle_event("clear_stage", _params, socket) do
    refine_with(socket, fn intent ->
      case drop_stage(intent.filters) do
        [] -> %{intent | filters: nil}
        rest -> %{intent | filters: rest}
      end
    end)
  end

  defp refine_with(socket, intent_fn) do
    if is_nil(socket.assigns[:resolver]) do
      {:noreply,
       assign(socket,
         refine_error: "Filter only works inside Live.Report with a resolver in context."
       )}
    else
      context = %{
        resolver: socket.assigns[:resolver],
        current_user: socket.assigns[:current_user],
        presenter: socket.assigns[:presenter]
      }

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
  defp format_error({:unsupported_query, dataset}), do: "Cannot trend #{dataset}."
  defp format_error(other), do: "Refine failed: #{inspect(other)}"

  @impl Phoenix.LiveComponent
  def render(assigns) do
    rows = rows(assigns.renderable)
    summary = sparkline_summary(rows)

    assigns =
      assigns
      |> assign(:rows, rows)
      |> assign(:summary, summary)

    ~H"""
    <div class="resonance-component resonance-widget trend-sparkline rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@renderable.props[:title] || "Trend"}</h3>
        <span class="text-xs uppercase tracking-wide text-gray-400">Interactive</span>
      </div>

      <div class="mb-4 flex flex-wrap items-center gap-2">
        <span class="text-xs font-medium text-gray-500 mr-1">Stage:</span>
        <button
          type="button"
          phx-click="clear_stage"
          phx-target={@myself}
          class={[
            "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
            if(is_nil(@active_stage),
              do: "bg-blue-50 border-blue-300 text-blue-700",
              else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
            )
          ]}
        >
          all stages
        </button>
        <%= for stage <- @stages do %>
          <button
            type="button"
            phx-click="set_stage"
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

      <div class="flex items-end gap-6">
        <div class="flex-1 min-w-0">
          <%= if @summary.path do %>
            <svg viewBox="0 0 400 100" preserveAspectRatio="none" class="w-full h-24">
              <defs>
                <linearGradient id={"grad-#{@renderable.id}"} x1="0" x2="0" y1="0" y2="1">
                  <stop offset="0%" stop-color="#3b82f6" stop-opacity="0.35" />
                  <stop offset="100%" stop-color="#3b82f6" stop-opacity="0" />
                </linearGradient>
              </defs>
              <path d={@summary.fill} fill={"url(#grad-#{@renderable.id})"}></path>
              <path d={@summary.path} fill="none" stroke="#3b82f6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"></path>
              <%= for {x, y} <- @summary.points do %>
                <circle cx={x} cy={y} r="3" fill="#3b82f6"></circle>
              <% end %>
            </svg>
            <div class="mt-2 flex justify-between text-[10px] text-gray-400 font-mono">
              <%= for row <- @rows do %>
                <span>{row_label(row)}</span>
              <% end %>
            </div>
          <% else %>
            <div class="text-sm text-gray-400 italic">No data points to trend.</div>
          <% end %>
        </div>
        <div class="flex flex-col gap-2 min-w-[110px]">
          <div>
            <div class="text-[10px] uppercase tracking-wide text-gray-400 font-semibold">Latest</div>
            <div class="text-lg font-semibold text-gray-900 tabular-nums">${format_value(@summary.latest)}</div>
          </div>
          <div>
            <div class="text-[10px] uppercase tracking-wide text-gray-400 font-semibold">Peak</div>
            <div class="text-sm text-gray-700 tabular-nums">${format_value(@summary.max)}</div>
          </div>
          <div>
            <div class="text-[10px] uppercase tracking-wide text-gray-400 font-semibold">Trough</div>
            <div class="text-sm text-gray-700 tabular-nums">${format_value(@summary.min)}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp rows(%Resonance.Renderable{props: props}) do
    props[:data] || props["data"] || []
  end

  defp row_label(row), do: row[:label] || row["label"] || row[:period] || row["period"] || "—"
  defp row_value(row), do: row[:value] || row["value"] || 0

  defp sparkline_summary([]),
    do: %{path: nil, fill: nil, points: [], min: 0, max: 0, latest: 0}

  defp sparkline_summary(rows) do
    values =
      rows
      |> Enum.map(&row_value/1)
      |> Enum.map(fn
        n when is_number(n) -> n
        _ -> 0
      end)

    min_v = Enum.min(values)
    max_v = Enum.max(values)
    latest = List.last(values) || 0

    width = 400
    height = 100
    pad_y = 8
    range = max(max_v - min_v, 1)
    n = length(values)

    points =
      values
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        x = if n == 1, do: width / 2, else: i * width / (n - 1)
        y = height - pad_y - (v - min_v) / range * (height - 2 * pad_y)
        {Float.round(x, 2), Float.round(y, 2)}
      end)

    path =
      points
      |> Enum.with_index()
      |> Enum.map(fn
        {{x, y}, 0} -> "M #{x} #{y}"
        {{x, y}, _} -> "L #{x} #{y}"
      end)
      |> Enum.join(" ")

    fill =
      case points do
        [] ->
          nil

        [{first_x, _} | _] = pts ->
          {last_x, _} = List.last(pts)
          path <> " L #{last_x} #{height} L #{first_x} #{height} Z"
      end

    %{
      path: path,
      fill: fill,
      points: points,
      min: min_v,
      max: max_v,
      latest: latest
    }
  end

  defp format_value(n) when is_number(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 2)}M"
  defp format_value(n) when is_number(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_value(_), do: "—"
end
