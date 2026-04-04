defmodule Resonance.Layout do
  @moduledoc """
  Basic layout rules for ordering composed components.

  Separates "what to show" (LLM) from "how to arrange it" (system).
  Increases consistency across generated reports.

  Default order:
  1. Metric cards and grids (KPIs first)
  2. Charts (trends and distributions)
  3. Tables (detail data)
  4. Prose (narrative summary)
  """

  alias Resonance.Renderable

  @type_order %{
    "segment_population" => 1,
    "show_distribution" => 2,
    "compare_over_time" => 3,
    "rank_entities" => 4,
    "summarize_findings" => 5
  }

  @component_order %{
    Resonance.Components.MetricGrid => 1,
    Resonance.Components.MetricCard => 1,
    Resonance.Components.PieChart => 2,
    Resonance.Components.BarChart => 3,
    Resonance.Components.LineChart => 3,
    Resonance.Components.DataTable => 4,
    Resonance.Components.ProseSection => 5,
    Resonance.Components.ErrorDisplay => 6
  }

  @doc """
  Sort renderables into a consistent layout order.
  """
  @spec order([Renderable.t()]) :: [Renderable.t()]
  def order(renderables) do
    Enum.sort_by(renderables, fn r ->
      {
        Map.get(@component_order, r.component, 99),
        Map.get(@type_order, r.type, 99)
      }
    end)
  end
end
