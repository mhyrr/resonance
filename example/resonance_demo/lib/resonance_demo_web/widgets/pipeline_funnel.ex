defmodule ResonanceDemoWeb.Widgets.PipelineFunnel do
  @moduledoc """
  Interactive deal pipeline funnel.

  Renders a `:distribution` Result (deals grouped by stage) as a vertical
  funnel and lets the user toggle the underlying measure between deal *count*
  and total *value* without an LLM round-trip.

  The interaction is a `Resonance.refine/3` call that swaps the
  `QueryIntent.measures` array — same dataset, same dimensions, different
  aggregation. The widget reads the current mode straight off the Renderable's
  intent so it stays in sync after a refresh.
  """

  use Resonance.Widget

  @impl Resonance.Widget
  def accepts_results, do: [:distribution]

  @impl Resonance.Widget
  def capabilities, do: [:refine]

  @impl Resonance.Widget
  def live_renderable(context) do
    intent = %Resonance.QueryIntent{
      dataset: "deals",
      measures: ["count(*)"],
      dimensions: ["stage"]
    }

    case Resonance.Primitive.resolve_with_intent(:distribution, intent, "Deal pipeline", context) do
      {:ok, %Resonance.Result{} = result} ->
        {:ok,
         %Resonance.Renderable{
           id: "live-pipeline-funnel",
           type: "show_distribution",
           component: __MODULE__,
           props: %{title: result.title, data: result.data},
           status: :ready,
           render_via: :live,
           primitive: "show_distribution",
           result: result
         }}

      {:error, _} = error ->
        error
    end
  end

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
      primitive: "show_distribution",
      props: %{title: "Deal pipeline (example)", data: rows},
      result: %Resonance.Result{
        kind: :distribution,
        title: "Deal pipeline (example)",
        data: rows,
        intent: %Resonance.QueryIntent{
          dataset: "deals",
          measures: ["count(*)"],
          dimensions: ["stage"]
        }
      }
    }
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, refine_error: nil)}
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: renderable} = assigns, socket) do
    {:ok,
     socket
     |> assign(:renderable, renderable)
     |> assign(:resolver, assigns[:resolver])
     |> assign(:current_user, assigns[:current_user])
     |> assign(:presenter, assigns[:presenter])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_measure", %{"mode" => mode}, socket) do
    new_measures =
      case mode do
        "count" -> ["count(*)"]
        "value" -> ["sum(value)"]
        _ -> nil
      end

    if is_nil(new_measures) or is_nil(socket.assigns[:resolver]) do
      {:noreply,
       assign(socket,
         refine_error: "Refine only works inside Live.Report with a resolver in context."
       )}
    else
      context = build_context(socket)

      case Resonance.refine(
             socket.assigns.renderable,
             fn intent -> %{intent | measures: new_measures} end,
             context
           ) do
        {:ok, refined} ->
          {:noreply, assign(socket, renderable: refined, refine_error: nil)}

        {:error, reason} ->
          {:noreply, assign(socket, :refine_error, format_error(reason))}
      end
    end
  end

  defp build_context(socket) do
    %{
      resolver: socket.assigns[:resolver],
      current_user: socket.assigns[:current_user],
      presenter: socket.assigns[:presenter]
    }
  end

  defp format_error({:invalid_field, field, msg}), do: "Invalid #{field}: #{msg}"
  defp format_error({:unsupported_query, dataset}), do: "Cannot funnel #{dataset}."
  defp format_error(other), do: "Refine failed: #{inspect(other)}"

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns =
      assigns
      |> assign(:rows, rows(assigns.renderable))
      |> assign(:mode, current_mode(assigns.renderable))
      |> then(fn a -> assign(a, :max, max_value(a.rows)) end)

    ~H"""
    <div class="resonance-component resonance-widget pipeline-funnel rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@renderable.props[:title] || "Pipeline"}</h3>
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

      <div :if={@refine_error} class="mb-3 px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-xs text-amber-800">
        {@refine_error}
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

  defp rows(%Resonance.Renderable{props: props}) do
    props[:data] || props["data"] || []
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

  defp current_mode(%Resonance.Renderable{
         result: %Resonance.Result{intent: %Resonance.QueryIntent{measures: measures}}
       })
       when is_list(measures) do
    cond do
      Enum.any?(measures, &String.contains?(&1, "sum(value)")) -> :value
      Enum.any?(measures, &String.contains?(&1, "avg(value)")) -> :value
      true -> :count
    end
  end

  defp current_mode(_), do: :count

  defp format_metric(n, :value) when is_number(n) and n >= 1_000_000,
    do: "$#{Float.round(n / 1_000_000, 1)}M"

  defp format_metric(n, :value) when is_number(n) and n >= 1_000,
    do: "$#{Float.round(n / 1_000, 1)}K"

  defp format_metric(n, :value) when is_number(n), do: "$#{trunc(n)}"
  defp format_metric(n, :count) when is_number(n), do: Integer.to_string(trunc(n))
  defp format_metric(_, _), do: "—"
end
