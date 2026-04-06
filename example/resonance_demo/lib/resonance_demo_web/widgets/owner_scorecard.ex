defmodule ResonanceDemoWeb.Widgets.OwnerScorecard do
  @moduledoc """
  Interactive sales-rep scorecard.

  Renders a `:segmentation` Result (deals grouped by owner) as a row of
  per-rep cards and lets the user scope the data to a specific quarter
  without an LLM round-trip.

  The interaction is a `Resonance.refine/3` call that adds (or removes) a
  `quarter = ...` filter on the existing `QueryIntent` — same dataset, same
  dimensions, just narrowed.
  """

  use Resonance.Widget

  @quarters ~w(2025-Q1 2025-Q2 2025-Q3 2025-Q4 2026-Q1 2026-Q2)

  @impl Resonance.Widget
  def accepts_results, do: [:segmentation]

  @impl Resonance.Widget
  def capabilities, do: [:refine]

  @impl Resonance.Widget
  def live_renderable(context) do
    intent = %Resonance.QueryIntent{
      dataset: "deals",
      measures: ["sum(value)"],
      dimensions: ["owner"]
    }

    case Resonance.Primitive.resolve_with_intent(
           :segmentation,
           intent,
           "Reps by pipeline value",
           context
         ) do
      {:ok, %Resonance.Result{} = result} ->
        {:ok,
         %Resonance.Renderable{
           id: "live-owner-scorecard",
           type: "segment_population",
           component: __MODULE__,
           props: %{title: result.title, data: result.data},
           status: :ready,
           render_via: :live,
           primitive: "segment_population",
           result: result
         }}

      {:error, _} = error ->
        error
    end
  end

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
      primitive: "segment_population",
      props: %{title: "Reps by pipeline value (example)", data: rows},
      result: %Resonance.Result{
        kind: :segmentation,
        title: "Reps by pipeline value (example)",
        data: rows,
        intent: %Resonance.QueryIntent{
          dataset: "deals",
          measures: ["sum(value)"],
          dimensions: ["owner"],
          filters: nil
        }
      }
    }
  end

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, quarters: @quarters, refine_error: nil, active_quarter: nil)}
  end

  @impl Phoenix.LiveComponent
  def update(%{renderable: renderable} = assigns, socket) do
    {:ok,
     socket
     |> assign(:renderable, renderable)
     |> assign(:resolver, assigns[:resolver])
     |> assign(:current_user, assigns[:current_user])
     |> assign(:presenter, assigns[:presenter])
     |> assign_active_quarter_from_intent(renderable)}
  end

  defp assign_active_quarter_from_intent(socket, %Resonance.Renderable{
         result: %Resonance.Result{intent: %Resonance.QueryIntent{filters: filters}}
       }) do
    quarter =
      case filters do
        list when is_list(list) ->
          case Enum.find(list, fn f -> f.field == "quarter" end) do
            %{value: q} -> q
            _ -> nil
          end

        _ ->
          nil
      end

    assign(socket, :active_quarter, quarter)
  end

  defp assign_active_quarter_from_intent(socket, _), do: assign(socket, :active_quarter, nil)

  @impl Phoenix.LiveComponent
  def handle_event("set_quarter", %{"quarter" => quarter}, socket) do
    refine_with(socket, fn intent ->
      filters = drop_quarter(intent.filters) ++ [%{field: "quarter", op: "=", value: quarter}]
      %{intent | filters: filters}
    end)
  end

  def handle_event("clear_quarter", _params, socket) do
    refine_with(socket, fn intent ->
      case drop_quarter(intent.filters) do
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
           |> assign_active_quarter_from_intent(refined)}

        {:error, reason} ->
          {:noreply, assign(socket, :refine_error, format_error(reason))}
      end
    end
  end

  defp drop_quarter(nil), do: []
  defp drop_quarter(filters), do: Enum.reject(filters, fn f -> f.field == "quarter" end)

  defp format_error({:invalid_field, field, msg}), do: "Invalid #{field}: #{msg}"
  defp format_error({:unsupported_query, dataset}), do: "Cannot scope #{dataset}."
  defp format_error(other), do: "Refine failed: #{inspect(other)}"

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :rows, rows(assigns.renderable))

    ~H"""
    <div class="resonance-component resonance-widget owner-scorecard rounded-xl border border-gray-200 bg-white p-5 shadow-sm">
      <div class="flex items-baseline justify-between mb-4">
        <h3 class="text-base font-semibold text-gray-900">{@renderable.props[:title] || "Reps"}</h3>
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

      <div :if={@refine_error} class="mb-3 px-3 py-2 rounded-md bg-amber-50 border border-amber-200 text-xs text-amber-800">
        {@refine_error}
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

  defp rows(%Resonance.Renderable{props: props}) do
    props[:data] || props["data"] || []
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
