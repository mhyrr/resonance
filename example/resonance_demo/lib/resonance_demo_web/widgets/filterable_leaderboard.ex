defmodule ResonanceDemoWeb.Widgets.FilterableLeaderboard do
  @moduledoc """
  Interactive deals leaderboard.

  Receives an initial Renderable from the Resonance presenter (with `:rows`
  and `:active_stage` already unpacked from the LLM-generated query). After
  that it's a normal Phoenix LiveComponent: the stage chips call
  `ResonanceDemo.Deals.top_by_value/1` directly from `handle_event/3`.

  When external data changes (e.g. the Simulate button broadcasts on the
  `"deals"` PubSub topic), the parent LiveView is responsible for forwarding
  a refreshed `:renderable` to this component via `send_update/2`.
  LiveComponents share their parent's process and can't subscribe to PubSub
  themselves — so the parent owns the subscription and the component owns
  its rendering.

  Resonance built the page; Phoenix runs the rest.
  """

  use Resonance.Widget

  alias ResonanceDemo.Deals

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)

  @impl Resonance.Widget
  def accepts_results, do: [:ranking]

  @impl Resonance.Widget
  def capabilities, do: [:filter, :live_updates]

  @impl Resonance.Widget
  def example_renderable do
    %Resonance.Renderable{
      id: "example-filterable-leaderboard",
      type: "rank_entities",
      component: __MODULE__,
      status: :ready,
      render_via: :live,
      props: %{
        title: "Top deals (example)",
        active_stage: nil,
        rows: [
          %{label: "Acme retainer", value: 480_000, stage: "negotiation"},
          %{label: "Globex platform deal", value: 410_000, stage: "proposal"},
          %{label: "Initech Q3 expansion", value: 365_000, stage: "discovery"},
          %{label: "Umbrella renewal", value: 290_000, stage: "closed_won"},
          %{label: "Stark Industries pilot", value: 240_000, stage: "discovery"}
        ]
      }
    }
  end

  @impl Resonance.Widget
  def playground_renderable(_widget_assigns) do
    rows = Deals.top_by_value(limit: 10)

    Resonance.Renderable.ready_live("rank_entities", __MODULE__, %{
      title: "Top deals",
      active_stage: nil,
      rows: rows
    })
  end

  # =====
  # From here down it's a normal Phoenix LiveComponent — Resonance has
  # nothing to teach you. Call your own contexts from handle_event, manage
  # local state in assigns. PubSub auto-updates are handled by the parent
  # LiveView (it subscribes and forwards via send_update with a refreshed
  # `:rows` assign).
  # =====

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, stages: @stages)}
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: r} = assigns, socket) do
    {:ok,
     socket
     |> assign(:title, r.props[:title] || "Leaderboard")
     |> assign(:rows, r.props[:rows] || [])
     |> assign(:active_stage, r.props[:active_stage])
     |> assign(:current_user, assigns[:current_user])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("filter_stage", %{"stage" => stage}, socket) do
    rows = Deals.top_by_value(stage: stage, limit: 10)
    {:noreply, socket |> assign(:active_stage, stage) |> assign(:rows, rows)}
  end

  def handle_event("clear_filter", _params, socket) do
    rows = Deals.top_by_value(limit: 10)
    {:noreply, socket |> assign(:active_stage, nil) |> assign(:rows, rows)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-widget filterable-leaderboard rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@title}</h3>
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

      <ol class="space-y-1.5">
        <%= for {row, idx} <- Enum.with_index(@rows, 1) do %>
          <li class="flex items-baseline justify-between py-1.5 px-2 rounded hover:bg-gray-50">
            <div class="flex items-baseline gap-3 min-w-0">
              <span class="text-xs font-mono text-gray-400 w-6">{idx}.</span>
              <span class="text-sm text-gray-900 truncate">{row_label(row)}</span>
            </div>
            <span class="text-sm font-medium text-gray-700 tabular-nums">${format_value(row_value(row))}</span>
          </li>
        <% end %>
        <li :if={@rows == []} class="text-sm text-gray-400 italic px-2 py-3">
          No results for this filter.
        </li>
      </ol>
    </div>
    """
  end

  defp row_label(row), do: row[:label] || row["label"] || "—"
  defp row_value(row), do: row[:value] || row["value"] || 0

  defp format_value(n) when is_number(n) and n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_value(n) when is_number(n) and n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_value(_), do: "—"
end
