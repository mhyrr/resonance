defmodule ResonanceDemoWeb.Presenters.Interactive do
  @moduledoc """
  CRM demo presenter that swaps in interactive widgets for the kinds we have
  v2 widgets for, and delegates everything else to `Resonance.Presenters.Default`.

  Routes (all gated on `dataset: "deals"` so non-deal queries fall back to the
  default chart components):

  | Result kind     | Widget                  | Refines via          |
  |-----------------|-------------------------|----------------------|
  | `:ranking`      | `FilterableLeaderboard` | stage filter         |
  | `:distribution` | `PipelineFunnel`        | measures (count/sum) |
  | `:segmentation` | `OwnerScorecard`        | quarter filter       |
  | `:comparison`   | `TrendSparkline`        | stage filter         |

  This is exactly the dispatch table the v2 doc describes — one Presenter per
  app, one clause per (kind, dataset) pair you want to make interactive.
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
        %Result{kind: :ranking, intent: %QueryIntent{dataset: "deals"}} = result,
        _context
      ) do
    Renderable.ready_live(
      "rank_entities",
      FilterableLeaderboard,
      %{title: result.title, data: result.data}
    )
  end

  def present(
        %Result{kind: :distribution, intent: %QueryIntent{dataset: "deals"}} = result,
        _context
      ) do
    Renderable.ready_live(
      "show_distribution",
      PipelineFunnel,
      %{title: result.title, data: result.data}
    )
  end

  def present(
        %Result{kind: :segmentation, intent: %QueryIntent{dataset: "deals", dimensions: ["owner"]}} =
          result,
        _context
      ) do
    Renderable.ready_live(
      "segment_population",
      OwnerScorecard,
      %{title: result.title, data: result.data}
    )
  end

  def present(
        %Result{
          kind: :comparison,
          intent: %QueryIntent{dataset: "deals", dimensions: ["quarter"]}
        } = result,
        _context
      ) do
    Renderable.ready_live(
      "compare_over_time",
      TrendSparkline,
      %{title: result.title, data: result.data}
    )
  end

  def present(%Result{} = result, context) do
    Resonance.Presenters.Default.present(result, context)
  end
end
