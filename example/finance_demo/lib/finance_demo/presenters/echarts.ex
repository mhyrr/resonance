defmodule FinanceDemo.Presenters.ECharts do
  @moduledoc """
  ECharts presenter for the finance demo.

  Maps Resonance Results to ECharts-based components. Delegates
  segmentation and summary to the library's default presenter.
  """

  @behaviour Resonance.Presenter

  alias Resonance.{Renderable, Result}

  @impl true
  def present(%Result{kind: :comparison} = result, _context) do
    multi = multi_series?(result)

    Renderable.ready(
      "compare_over_time",
      FinanceDemo.Components.EChartsLine,
      %{
        title: result.title,
        data: result.data,
        multi_series: multi
      }
    )
  end

  def present(%Result{kind: :ranking} = result, _context) do
    if length(result.data) <= 10 do
      Renderable.ready(
        "rank_entities",
        FinanceDemo.Components.EChartsBar,
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
    # Treemap instead of pie — the whole point of this demo
    Renderable.ready(
      "show_distribution",
      FinanceDemo.Components.EChartsTreemap,
      %{
        title: result.title,
        data: result.data
      }
    )
  end

  # Delegate segmentation and summary to library defaults
  def present(result, context) do
    Resonance.Presenters.Default.present(result, context)
  end

  defp multi_series?(result) do
    dims = if result.intent, do: result.intent.dimensions || [], else: []
    length(dims) > 1 || length(result.data) > 12
  end
end
