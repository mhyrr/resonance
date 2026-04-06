defmodule ResonanceDemoWeb.Widgets.PipelineFunnel do
  @moduledoc """
  Interactive deal pipeline funnel.

  Renders a `:distribution` Result (deals grouped by stage) as a vertical
  funnel and lets the user toggle the underlying measure between deal
  *count* and total *value*. The toggle calls `Deals.by_stage_distribution/1`
  directly — no Resonance machinery on the user-driven path.

  Subscribes to the `"deals"` PubSub topic so the funnel auto-refreshes
  whenever simulate fires.
  """

  use Resonance.Widget

  alias ResonanceDemo.Deals

  @impl Resonance.Widget
  def accepts_results, do: [:distribution]

  @impl Resonance.Widget
  def capabilities, do: [:measure_toggle, :live_updates]

  @impl Resonance.Widget
  def example_renderable do
    rows = [
      %{label: "prospecting", value: 28},
      %{label: "discovery", value: 22},
      %{label: "proposal", value: 15},
      %{label: "negotiation", value: 9},
      %{label: "closed_won", value: 6},
      %{label: "closed_lost", value: 4}
    ]

    %Resonance.Renderable{
      id: "example-pipeline-funnel",
      type: "show_distribution",
      component: __MODULE__,
      status: :ready,
      render_via: :live,
      props: %{title: "Deal pipeline (example)", rows: rows, mode: :count}
    }
  end

  @impl Resonance.Widget
  def playground_renderable(_widget_assigns) do
    rows = Deals.by_stage_distribution(mode: :count)

    Resonance.Renderable.ready_live("show_distribution", __MODULE__, %{
      title: "Deal pipeline",
      rows: rows,
      mode: :count
    })
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: r} = assigns, socket) do
    {:ok,
     socket
     |> assign(:title, r.props[:title] || "Pipeline")
     |> assign(:rows, r.props[:rows] || [])
     |> assign(:mode, r.props[:mode] || :count)
     |> assign(:current_user, assigns[:current_user])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_measure", %{"mode" => mode_str}, socket) do
    mode =
      case mode_str do
        "value" -> :value
        _ -> :count
      end

    rows = Deals.by_stage_distribution(mode: mode)
    {:noreply, socket |> assign(:mode, mode) |> assign(:rows, rows)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :max, max_value(assigns.rows))

    ~H"""
    <div class="resonance-component resonance-widget pipeline-funnel rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@title}</h3>
        <span class="text-xs uppercase tracking-wide text-gray-400">Interactive</span>
      </div>

      <div class="mb-4 flex items-center gap-2">
        <span class="text-xs font-medium text-gray-500 mr-1">Measure:</span>
        <button
          type="button"
          phx-click="set_measure"
          phx-value-mode="count"
          phx-target={@myself}
          class={[
            "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
            if(@mode == :count,
              do: "bg-blue-50 border-blue-300 text-blue-700",
              else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
            )
          ]}
        >
          by count
        </button>
        <button
          type="button"
          phx-click="set_measure"
          phx-value-mode="value"
          phx-target={@myself}
          class={[
            "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
            if(@mode == :value,
              do: "bg-blue-50 border-blue-300 text-blue-700",
              else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
            )
          ]}
        >
          by value
        </button>
      </div>

      <div class="space-y-1.5">
        <%= for row <- @rows do %>
          <div class="flex items-center gap-3">
            <div class="w-24 text-xs font-medium text-gray-600 truncate">{row_label(row)}</div>
            <div class="flex-1 relative h-6 bg-gray-100 rounded">
              <div
                class="absolute inset-y-0 left-0 bg-gradient-to-r from-blue-500 to-blue-400 rounded"
                style={"width: #{bar_pct(row, @max)}%;"}
              >
              </div>
            </div>
            <div class="w-20 text-right text-xs font-medium text-gray-700 tabular-nums">{format_metric(row_value(row), @mode)}</div>
          </div>
        <% end %>
        <div :if={@rows == []} class="text-sm text-gray-400 italic px-2 py-3">
          No stages to display.
        </div>
      </div>
    </div>
    """
  end

  defp row_label(row), do: row[:label] || row["label"] || "—"
  defp row_value(row), do: row[:value] || row["value"] || 0

  defp max_value([]), do: 0

  defp max_value(rows) do
    rows
    |> Enum.map(&row_value/1)
    |> Enum.filter(&is_number/1)
    |> case do
      [] -> 0
      vals -> Enum.max(vals)
    end
  end

  defp bar_pct(_row, 0), do: 0

  defp bar_pct(row, max) do
    case row_value(row) do
      v when is_number(v) and v > 0 -> Float.round(v / max * 100, 1)
      _ -> 0
    end
  end

  defp format_metric(n, :value) when is_number(n) and n >= 1_000_000,
    do: "$#{Float.round(n / 1_000_000, 1)}M"

  defp format_metric(n, :value) when is_number(n) and n >= 1_000,
    do: "$#{Float.round(n / 1_000, 1)}K"

  defp format_metric(n, :value) when is_number(n), do: "$#{trunc(n)}"
  defp format_metric(n, :count) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_metric(_, _), do: "—"
end
