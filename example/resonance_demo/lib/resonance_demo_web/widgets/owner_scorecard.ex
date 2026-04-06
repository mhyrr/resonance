defmodule ResonanceDemoWeb.Widgets.OwnerScorecard do
  @moduledoc """
  Interactive sales-rep scorecard.

  Renders a `:segmentation` Result (deals grouped by owner) and lets the
  user scope the view to a specific quarter via chip filters. Quarter
  selection calls `Deals.by_owner/1` directly.

  Subscribes to the `"deals"` PubSub topic for live updates.
  """

  use Resonance.Widget

  alias ResonanceDemo.Deals

  @quarters ~w(2025-Q1 2025-Q2 2025-Q3 2025-Q4 2026-Q1 2026-Q2)

  @impl Resonance.Widget
  def accepts_results, do: [:segmentation]

  @impl Resonance.Widget
  def capabilities, do: [:filter, :live_updates]

  @impl Resonance.Widget
  def example_renderable do
    rows = [
      %{label: "Alice", value: 1_240_000, count: 14},
      %{label: "Bob", value: 980_000, count: 11},
      %{label: "Carol", value: 1_510_000, count: 9},
      %{label: "Dave", value: 720_000, count: 6}
    ]

    %Resonance.Renderable{
      id: "example-owner-scorecard",
      type: "segment_population",
      component: __MODULE__,
      status: :ready,
      render_via: :live,
      props: %{
        title: "Reps by pipeline value (example)",
        rows: rows,
        active_quarter: nil
      }
    }
  end

  @impl Resonance.Widget
  def playground_renderable(_widget_assigns) do
    rows = Deals.by_owner()

    Resonance.Renderable.ready_live("segment_population", __MODULE__, %{
      title: "Reps by pipeline value",
      rows: rows,
      active_quarter: nil
    })
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, quarters: @quarters)}
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: r} = assigns, socket) do
    {:ok,
     socket
     |> assign(:title, r.props[:title] || "Reps")
     |> assign(:rows, r.props[:rows] || [])
     |> assign(:active_quarter, r.props[:active_quarter])
     |> assign(:current_user, assigns[:current_user])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_quarter", %{"quarter" => quarter}, socket) do
    rows = Deals.by_owner(quarter: quarter)
    {:noreply, socket |> assign(:active_quarter, quarter) |> assign(:rows, rows)}
  end

  def handle_event("clear_quarter", _params, socket) do
    rows = Deals.by_owner()
    {:noreply, socket |> assign(:active_quarter, nil) |> assign(:rows, rows)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-widget owner-scorecard rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@title}</h3>
        <span class="text-xs uppercase tracking-wide text-gray-400">Interactive</span>
      </div>

      <div class="mb-4 flex flex-wrap items-center gap-2">
        <span class="text-xs font-medium text-gray-500 mr-1">Quarter:</span>
        <button
          type="button"
          phx-click="clear_quarter"
          phx-target={@myself}
          class={[
            "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
            if(is_nil(@active_quarter),
              do: "bg-blue-50 border-blue-300 text-blue-700",
              else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
            )
          ]}
        >
          all time
        </button>
        <%= for q <- @quarters do %>
          <button
            type="button"
            phx-click="set_quarter"
            phx-value-quarter={q}
            phx-target={@myself}
            class={[
              "px-2.5 py-1 text-xs font-medium rounded-full border transition-colors cursor-pointer",
              if(@active_quarter == q,
                do: "bg-blue-50 border-blue-300 text-blue-700",
                else: "bg-white border-gray-200 text-gray-500 hover:border-gray-300"
              )
            ]}
          >
            {q}
          </button>
        <% end %>
      </div>

      <div class="grid gap-3" style="grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));">
        <%= for row <- @rows do %>
          <div class="rounded-lg border border-gray-200 bg-gradient-to-br from-white to-gray-50 p-4">
            <div class="flex items-center gap-3 mb-3">
              <div class="w-9 h-9 rounded-full bg-blue-100 text-blue-700 flex items-center justify-center font-semibold text-sm">
                {initial(row_label(row))}
              </div>
              <div class="text-sm font-semibold text-gray-900 truncate">{row_label(row)}</div>
            </div>
            <div class="text-2xl font-semibold text-gray-900 tabular-nums">${format_value(row_value(row))}</div>
            <div :if={row[:count]} class="text-xs text-gray-500 mt-1">{row[:count]} deal{if row[:count] == 1, do: "", else: "s"}</div>
          </div>
        <% end %>
        <div :if={@rows == []} class="text-sm text-gray-400 italic px-2 py-3">
          No reps for this scope.
        </div>
      </div>
    </div>
    """
  end

  defp row_label(row), do: row[:label] || row["label"] || "—"
  defp row_value(row), do: row[:value] || row["value"] || 0

  defp initial(name) when is_binary(name), do: name |> String.first() |> String.upcase()
  defp initial(_), do: "?"

  defp format_value(n) when is_number(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 2)}M"
  defp format_value(n) when is_number(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_value(_), do: "—"
end
