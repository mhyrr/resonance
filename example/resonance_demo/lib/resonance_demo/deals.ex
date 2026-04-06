defmodule ResonanceDemo.Deals do
  @moduledoc """
  Application context for the deals dataset.

  This is the boundary the v2 widgets call from `handle_event/3`. The
  Resonance LLM-driven path goes through `ResonanceDemo.CRM.Resolver` (which
  also delegates here for some queries); the user-driven path skips Resonance
  entirely and calls these functions directly.

  Mutations broadcast on the `"deals"` PubSub topic so subscribed widgets
  can refresh themselves without any Resonance involvement.
  """

  import Ecto.Query
  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Company, Deal}

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)
  @owners ~w(Alice Bob Carol Dave)
  @quarters ~w(2025-Q1 2025-Q2 2025-Q3 2025-Q4 2026-Q1 2026-Q2)

  @pubsub ResonanceDemo.PubSub
  @topic "deals"

  @doc "PubSub topic deal-watching widgets should subscribe to."
  def topic, do: @topic
  def pubsub, do: @pubsub

  @doc """
  Returns the top deals by total value, optionally filtered by stage.

  Each row: `%{label: deal_name, value: deal_value, stage: stage}`.
  """
  def top_by_value(opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    stage = Keyword.get(opts, :stage)

    Deal
    |> maybe_where_stage(stage)
    |> order_by([d], desc: d.value)
    |> limit(^limit)
    |> select([d], %{label: d.name, value: d.value, stage: d.stage})
    |> Repo.all()
  end

  @doc """
  Returns deals grouped by stage with the chosen aggregate.

  `mode` is `:count` (default) or `:value`. Each row:
  `%{label: stage, value: aggregate}`.
  """
  def by_stage_distribution(opts \\ []) do
    mode = Keyword.get(opts, :mode, :count)
    quarter = Keyword.get(opts, :quarter)

    base =
      Deal
      |> maybe_where_quarter(quarter)
      |> group_by([d], d.stage)
      |> order_by([d], asc: d.stage)

    rows =
      case mode do
        :value ->
          base
          |> select([d], %{label: d.stage, value: sum(d.value)})
          |> Repo.all()

        _ ->
          base
          |> select([d], %{label: d.stage, value: count(d.id)})
          |> Repo.all()
      end

    Enum.map(rows, fn row -> Map.update!(row, :value, &(&1 || 0)) end)
  end

  @doc """
  Returns deals grouped by owner with sum(value) and count.

  Each row: `%{label: owner, value: total_value, count: deal_count}`.
  Optional quarter filter.
  """
  def by_owner(opts \\ []) do
    quarter = Keyword.get(opts, :quarter)

    Deal
    |> maybe_where_quarter(quarter)
    |> group_by([d], d.owner)
    |> order_by([d], asc: d.owner)
    |> select([d], %{label: d.owner, value: sum(d.value), count: count(d.id)})
    |> Repo.all()
    |> Enum.map(fn row -> Map.update!(row, :value, &(&1 || 0)) end)
  end

  @doc """
  Returns deals grouped by quarter with sum(value).

  Each row: `%{label: quarter, period: quarter, value: total_value}`.
  Optional stage filter.
  """
  def by_quarter(opts \\ []) do
    stage = Keyword.get(opts, :stage)

    rows =
      Deal
      |> maybe_where_stage(stage)
      |> group_by([d], d.quarter)
      |> order_by([d], asc: d.quarter)
      |> select([d], %{label: d.quarter, period: d.quarter, value: sum(d.value)})
      |> Repo.all()
      |> Enum.map(fn row -> Map.update!(row, :value, &(&1 || 0)) end)

    # Backfill missing quarters with 0 so the trend chart has a stable x-axis.
    by_q = Map.new(rows, &{&1.label, &1})

    Enum.map(@quarters, fn q ->
      Map.get(by_q, q, %{label: q, period: q, value: 0})
    end)
  end

  @doc """
  Inserts a small batch of randomized deals and broadcasts a `:deals_changed`
  message on the `"deals"` PubSub topic. Returns `{:ok, summary}` where
  summary is a human-readable string describing the change.
  """
  def simulate_batch do
    company_ids = Repo.all(from c in Company, select: c.id)
    count = Enum.random(5..12)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    deals =
      for _i <- 1..count do
        %{
          name: "New Deal ##{System.unique_integer([:positive, :monotonic])}",
          value: Enum.random(10..500) * 1000,
          stage: Enum.random(@stages),
          close_date: Date.add(Date.utc_today(), Enum.random(-90..180)),
          owner: Enum.random(@owners),
          quarter: Enum.random(@quarters),
          company_id: Enum.random(company_ids),
          inserted_at: now,
          updated_at: now
        }
      end

    {inserted, _} = Repo.insert_all(Deal, deals)
    total_value = deals |> Enum.map(& &1.value) |> Enum.sum()

    Phoenix.PubSub.broadcast(@pubsub, @topic, {:deals_changed, %{inserted: inserted}})

    {:ok, "Added #{inserted} deals worth $#{format_value(total_value)}"}
  end

  defp maybe_where_stage(query, nil), do: query
  defp maybe_where_stage(query, stage), do: where(query, [d], d.stage == ^stage)

  defp maybe_where_quarter(query, nil), do: query
  defp maybe_where_quarter(query, quarter), do: where(query, [d], d.quarter == ^quarter)

  defp format_value(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_value(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n), do: Integer.to_string(n)
end
