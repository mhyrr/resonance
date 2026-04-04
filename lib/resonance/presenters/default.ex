defmodule Resonance.Presenters.Default do
  @moduledoc """
  Default presenter using the library's built-in components.

  Maps each Result kind to an appropriate component based on data shape:

  | Kind | Small data | Large data |
  |------|-----------|------------|
  | `:comparison` | BarChart (vertical) | LineChart (multi-series) |
  | `:ranking` | BarChart (horizontal) | DataTable |
  | `:distribution` | PieChart (donut) | BarChart (horizontal) |
  | `:segmentation` | MetricGrid | DataTable |
  | `:summary` | ProseSection | ProseSection |

  Apps that want different visualization can implement their own
  `Resonance.Presenter` and pass it to `Resonance.Live.Report`.
  """

  @behaviour Resonance.Presenter

  alias Resonance.{Renderable, Result}

  @impl true
  def present(%Result{kind: :comparison} = result, _context) do
    if multi_series?(result) do
      Renderable.ready(
        "compare_over_time",
        Resonance.Components.LineChart,
        %{
          title: result.title,
          data: result.data,
          multi_series: true
        }
      )
    else
      Renderable.ready(
        "compare_over_time",
        Resonance.Components.BarChart,
        %{
          title: result.title,
          data: result.data,
          orientation: "vertical"
        }
      )
    end
  end

  def present(%Result{kind: :ranking} = result, _context) do
    if length(result.data) <= 10 do
      Renderable.ready(
        "rank_entities",
        Resonance.Components.BarChart,
        %{
          title: result.title,
          data: result.data,
          orientation: "horizontal"
        }
      )
    else
      Renderable.ready(
        "rank_entities",
        Resonance.Components.DataTable,
        %{
          title: result.title,
          data: result.data,
          sortable: true
        }
      )
    end
  end

  def present(%Result{kind: :distribution} = result, _context) do
    if length(result.data) <= 8 do
      Renderable.ready(
        "show_distribution",
        Resonance.Components.PieChart,
        %{
          title: result.title,
          data: result.data,
          donut: true,
          show_percentages: true
        }
      )
    else
      Renderable.ready(
        "show_distribution",
        Resonance.Components.BarChart,
        %{
          title: result.title,
          data: result.data,
          orientation: "horizontal"
        }
      )
    end
  end

  def present(%Result{kind: :segmentation} = result, _context) do
    if length(result.data) <= 6 do
      metrics =
        Enum.map(result.data, fn row ->
          %{
            label: row[:label] || row["label"] || "Segment",
            value: row[:value] || row["value"] || row[:count] || row["count"] || 0,
            format: detect_format(row)
          }
        end)

      Renderable.ready(
        "segment_population",
        Resonance.Components.MetricGrid,
        %{
          title: result.title,
          metrics: metrics,
          columns: min(length(metrics), 3)
        }
      )
    else
      Renderable.ready(
        "segment_population",
        Resonance.Components.DataTable,
        %{
          title: result.title,
          data: result.data,
          sortable: true
        }
      )
    end
  end

  def present(%Result{kind: :summary} = result, _context) do
    Renderable.ready(
      "summarize_findings",
      Resonance.Components.ProseSection,
      %{
        title: result.title,
        content: result.metadata[:content] || "",
        style: "summary"
      }
    )
  end

  # Fallback for unknown kinds
  def present(%Result{} = result, _context) do
    Renderable.ready(
      to_string(result.kind),
      Resonance.Components.DataTable,
      %{
        title: result.title,
        data: result.data,
        sortable: true
      }
    )
  end

  defp multi_series?(result) do
    dims = if result.intent, do: result.intent.dimensions || [], else: []
    length(dims) > 1 || length(result.data) > 12
  end

  defp detect_format(row) do
    value = row[:value] || row["value"] || 0

    cond do
      is_float(value) and value < 1 -> "percent"
      is_number(value) and value > 1000 -> "currency"
      true -> "number"
    end
  end
end
