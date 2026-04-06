defmodule ResonanceDemoWeb.Presenters.Interactive do
  @moduledoc """
  CRM demo presenter that swaps in interactive widgets for the kinds we
  have v2 widgets for, and delegates everything else to
  `Resonance.Presenters.Default`.

  The presenter is the seam between "the LLM picked a query" and "the widget
  renders state." It unpacks the `Result.intent.filters` into clean,
  widget-friendly assigns (`active_stage`, `active_quarter`, etc.) so widgets
  never have to look at a `QueryIntent`.

  Routes (all gated on `dataset: "deals"` so non-deal queries fall back to
  the default chart components):

  | Result kind     | Widget                  | Refines via          |
  |-----------------|-------------------------|----------------------|
  | `:ranking`      | `FilterableLeaderboard` | stage filter         |
  | `:distribution` | `PipelineFunnel`        | measure (count/sum)  |
  | `:segmentation` | `OwnerScorecard`        | quarter filter       |
  | `:comparison`   | `TrendSparkline`        | stage filter         |
  """

  @behaviour Resonance.Presenter

  alias Resonance.{QueryIntent, Renderable, Result}

  alias ResonanceDemoWeb.Widgets.{
    FilterableLeaderboard,
    OwnerScorecard,
    PipelineFunnel,
    TrendSparkline
  }

  @impl true
  def present(
        %Result{kind: :ranking, intent: %QueryIntent{dataset: "deals"} = intent} = result,
        _context
      ) do
    Renderable.ready_live("rank_entities", FilterableLeaderboard, %{
      title: result.title,
      rows: result.data,
      active_stage: stage_from(intent)
    })
  end

  def present(
        %Result{kind: :distribution, intent: %QueryIntent{dataset: "deals"} = intent} = result,
        _context
      ) do
    Renderable.ready_live("show_distribution", PipelineFunnel, %{
      title: result.title,
      rows: result.data,
      mode: measure_mode(intent)
    })
  end

  def present(
        %Result{
          kind: :segmentation,
          intent: %QueryIntent{dataset: "deals", dimensions: ["owner"]} = intent
        } = result,
        _context
      ) do
    Renderable.ready_live("segment_population", OwnerScorecard, %{
      title: result.title,
      rows: result.data,
      active_quarter: quarter_from(intent)
    })
  end

  def present(
        %Result{
          kind: :comparison,
          intent: %QueryIntent{dataset: "deals", dimensions: ["quarter"]} = intent
        } = result,
        _context
      ) do
    Renderable.ready_live("compare_over_time", TrendSparkline, %{
      title: result.title,
      rows: result.data,
      active_stage: stage_from(intent)
    })
  end

  def present(%Result{} = result, context) do
    Resonance.Presenters.Default.present(result, context)
  end

  # --- Filter / measure unpackers ---

  defp stage_from(%QueryIntent{filters: filters}), do: filter_value(filters, "stage")
  defp quarter_from(%QueryIntent{filters: filters}), do: filter_value(filters, "quarter")

  defp filter_value(nil, _field), do: nil

  defp filter_value(filters, field) when is_list(filters) do
    case Enum.find(filters, fn f -> f.field == field end) do
      %{value: v} -> v
      _ -> nil
    end
  end

  defp filter_value(_, _), do: nil

  defp measure_mode(%QueryIntent{measures: measures}) when is_list(measures) do
    cond do
      Enum.any?(measures, &String.contains?(&1, "sum(value)")) -> :value
      Enum.any?(measures, &String.contains?(&1, "avg(value)")) -> :value
      true -> :count
    end
  end

  defp measure_mode(_), do: :count
end
