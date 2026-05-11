defmodule ResonanceDemo.CRM.Resolver do
  @moduledoc """
  Resonance resolver for the CRM demo.

  Translates QueryIntents into Ecto queries against the CRM schema.
  This is where correctness, security, and data access live.
  """

  @behaviour Resonance.Resolver

  require Logger
  import Ecto.Query
  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Company, Contact, Deal, Activity}

  @valid_datasets ~w(companies contacts deals activities)

  @capabilities %{
    description: "CRM demo data for companies, contacts, deals, and activities.",
    datasets: [
      %{
        name: "companies",
        description:
          "Accounts with industry, size, revenue, and region attributes.",
        fields: ~w(name industry size revenue region),
        measures: ["count(*)", "sum(revenue)", "avg(revenue)"],
        dimensions: ~w(name industry region size),
        filters: [
          %{field: "industry", ops: ["="]},
          %{field: "region", ops: ["="]},
          %{field: "size", ops: ["="]}
        ],
        query_shapes: [
          %{dimensions: [], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
          %{dimensions: ["name"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
          %{dimensions: ["industry"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
          %{dimensions: ["region"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]},
          %{dimensions: ["size"], measures: ["count(*)", "sum(revenue)", "avg(revenue)"]}
        ]
      },
      %{
        name: "contacts",
        description: "People in the CRM pipeline.",
        fields: ~w(name email stage title company_id),
        measures: ["count(*)"],
        dimensions: ~w(name stage),
        filters: [
          %{field: "stage", ops: ["="]}
        ],
        query_shapes: [
          %{dimensions: [], measures: ["count(*)"]},
          %{dimensions: ["name"], measures: ["count(*)"]},
          %{dimensions: ["stage"], measures: ["count(*)"]}
        ]
      },
      %{
        name: "deals",
        description:
          "Sales opportunities with value, stage, close quarter, owner, and company.",
        fields: ~w(name value stage close_date owner quarter company_id),
        measures: ["count(*)", "sum(value)", "avg(value)"],
        dimensions: ~w(name stage quarter owner),
        filters: [
          %{field: "stage", ops: ["="], values: ~w(prospecting discovery proposal negotiation closed_won closed_lost)},
          %{field: "quarter", ops: ["="]},
          %{field: "owner", ops: ["="], values: ~w(Alice Bob Carol Dave)}
        ],
        query_shapes: [
          %{dimensions: [], measures: ["count(*)", "sum(value)", "avg(value)"]},
          %{dimensions: ["name"], measures: ["count(*)", "sum(value)", "avg(value)"]},
          %{dimensions: ["stage"], measures: ["count(*)", "sum(value)", "avg(value)"]},
          %{dimensions: ["quarter"], measures: ["count(*)", "sum(value)", "avg(value)"]},
          %{dimensions: ["owner"], measures: ["count(*)", "sum(value)", "avg(value)"]},
          %{dimensions: ["stage", "quarter"], measures: ["count(*)", "sum(value)", "avg(value)"]}
        ]
      },
      %{
        name: "activities",
        description: "Sales activities linked to contacts.",
        fields: ~w(type date outcome contact_id),
        measures: ["count(*)"],
        dimensions: ~w(type outcome),
        filters: [
          %{field: "type", ops: ["="], values: ~w(call email meeting demo follow_up)},
          %{field: "outcome", ops: ["="], values: ~w(positive neutral negative no_response)}
        ],
        query_shapes: [
          %{dimensions: [], measures: ["count(*)"]},
          %{dimensions: ["type"], measures: ["count(*)"]},
          %{dimensions: ["outcome"], measures: ["count(*)"]}
        ]
      }
    ],
    notes: [
      "Deal stages are prospecting, discovery, proposal, negotiation, closed_won, and closed_lost.",
      "Owners are Alice, Bob, Carol, and Dave.",
      "Use quarter strings such as 2025-Q1 for quarter filters."
    ]
  }

  @impl true
  def describe do
    @capabilities
  end

  @impl true
  def validate(%Resonance.QueryIntent{} = intent, _context) do
    with :ok <- validate_dataset(intent.dataset) do
      Resonance.Resolver.validate_intent(intent, @capabilities)
    end
  end

  defp validate_dataset(dataset) do
    if dataset in @valid_datasets,
      do: :ok,
      else: {:error, {:unknown_dataset, dataset}}
  end

  @impl true
  def resolve(%Resonance.QueryIntent{} = intent, _context) do
    case query_for(intent) do
      {:ok, query} ->
        {:ok, Repo.all(query)}

      {:error, _} = err ->
        err
    end
  rescue
    e -> {:error, {:query_failed, Exception.message(e)}}
  end

  # --- Deals ---

  defp query_for(%{dataset: "deals", dimensions: ["stage"]} = intent) do
    q =
      Deal
      |> apply_deal_filters(intent.filters)
      |> group_by([d], d.stage)

    {:ok, select_deal_measure(q, :stage, intent.measures)}
  end

  defp query_for(%{dataset: "deals", dimensions: ["quarter"]} = intent) do
    q =
      Deal
      |> apply_deal_filters(intent.filters)
      |> group_by([d], d.quarter)
      |> order_by([d], asc: d.quarter)

    {:ok, select_deal_measure(q, :quarter, intent.measures, period: true)}
  end

  defp query_for(%{dataset: "deals", dimensions: ["owner"]} = intent) do
    q =
      Deal
      |> apply_deal_filters(intent.filters)
      |> group_by([d], d.owner)

    {:ok, select_deal_measure(q, :owner, intent.measures)}
  end

  defp query_for(%{dataset: "deals", dimensions: ["stage", "quarter"]} = intent) do
    q =
      Deal
      |> apply_deal_filters(intent.filters)
      |> group_by([d], [d.stage, d.quarter])

    q =
      case primary_measure(intent.measures) do
        :sum_value ->
          select(q, [d], %{
            label: d.quarter,
            period: d.quarter,
            group: d.stage,
            series: d.stage,
            value: sum(d.value)
          })

        _ ->
          select(q, [d], %{
            label: d.quarter,
            period: d.quarter,
            group: d.stage,
            series: d.stage,
            value: count(d.id)
          })
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "deals"} = intent) do
    q =
      Deal
      |> apply_deal_filters(intent.filters)
      |> select([d], %{label: d.name, value: d.value})
      |> apply_sort_by_field(intent.sort, :value)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Companies ---

  defp query_for(%{dataset: "companies", dimensions: ["industry"]} = intent) do
    q =
      Company
      |> apply_company_filters(intent.filters)
      |> group_by([c], c.industry)

    {:ok, select_company_measure(q, :industry, intent.measures)}
  end

  defp query_for(%{dataset: "companies", dimensions: ["region"]} = intent) do
    q =
      Company
      |> apply_company_filters(intent.filters)
      |> group_by([c], c.region)

    {:ok, select_company_measure(q, :region, intent.measures)}
  end

  defp query_for(%{dataset: "companies", dimensions: ["size"]} = intent) do
    q =
      Company
      |> apply_company_filters(intent.filters)
      |> group_by([c], c.size)

    {:ok, select_company_measure(q, :size, intent.measures)}
  end

  defp query_for(%{dataset: "companies"} = intent) do
    q =
      Company
      |> apply_company_filters(intent.filters)
      |> select([c], %{label: c.name, value: c.revenue})
      |> apply_sort_by_field(intent.sort, :revenue)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Contacts ---

  defp query_for(%{dataset: "contacts", dimensions: ["stage"]} = intent) do
    q =
      Contact
      |> apply_contact_filters(intent.filters)
      |> group_by([c], c.stage)
      |> select([c], %{label: c.stage, value: count(c.id)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "contacts"} = intent) do
    q =
      Contact
      |> apply_contact_filters(intent.filters)
      |> select([c], %{label: c.name, value: 1})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # --- Activities ---

  defp query_for(%{dataset: "activities", dimensions: ["type"]} = intent) do
    q =
      Activity
      |> apply_activity_filters(intent.filters)
      |> group_by([a], a.type)
      |> select([a], %{label: a.type, value: count(a.id)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "activities", dimensions: ["outcome"]} = intent) do
    q =
      Activity
      |> apply_activity_filters(intent.filters)
      |> group_by([a], a.outcome)
      |> select([a], %{label: a.outcome, value: count(a.id)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "activities"} = intent) do
    q =
      Activity
      |> apply_activity_filters(intent.filters)
      |> select([a], %{label: a.type, value: 1})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # Fallback
  defp query_for(%{dataset: dataset}) do
    {:error, {:unsupported_query, dataset}}
  end

  # --- Measure helpers ---

  defp primary_measure(nil), do: :count
  defp primary_measure([]), do: :count

  defp primary_measure([first | _]) do
    cond do
      String.contains?(first, "sum(value)") -> :sum_value
      String.contains?(first, "sum(revenue)") -> :sum_revenue
      String.contains?(first, "avg(value)") -> :avg_value
      String.contains?(first, "avg(revenue)") -> :avg_revenue
      String.contains?(first, "max(value)") -> :max_value
      true -> :count
    end
  end

  defp select_deal_measure(query, label_field, measures, opts \\ []) do
    period = Keyword.get(opts, :period, false)

    case primary_measure(measures) do
      :sum_value when period ->
        select(query, [d], %{
          label: field(d, ^label_field),
          period: field(d, ^label_field),
          value: sum(d.value)
        })

      :sum_value ->
        select(query, [d], %{label: field(d, ^label_field), value: sum(d.value)})

      :avg_value when period ->
        select(query, [d], %{
          label: field(d, ^label_field),
          period: field(d, ^label_field),
          value: avg(d.value)
        })

      :avg_value ->
        select(query, [d], %{label: field(d, ^label_field), value: avg(d.value)})

      _ when period ->
        select(query, [d], %{
          label: field(d, ^label_field),
          period: field(d, ^label_field),
          value: count(d.id)
        })

      _ ->
        select(query, [d], %{label: field(d, ^label_field), value: count(d.id)})
    end
  end

  defp select_company_measure(query, label_field, measures) do
    case primary_measure(measures) do
      :sum_revenue ->
        select(query, [c], %{label: field(c, ^label_field), value: sum(c.revenue)})

      :avg_revenue ->
        select(query, [c], %{label: field(c, ^label_field), value: avg(c.revenue)})

      _ ->
        select(query, [c], %{label: field(c, ^label_field), value: count(c.id)})
    end
  end

  # --- Filter helpers ---

  defp apply_deal_filters(query, nil), do: query
  defp apply_deal_filters(query, []), do: query

  defp apply_deal_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "stage", op: "=", value: v}, q -> where(q, [d], d.stage == ^v)
      %{field: "quarter", op: "=", value: v}, q -> where(q, [d], d.quarter == ^v)
      %{field: "owner", op: "=", value: v}, q -> where(q, [d], d.owner == ^v)
      filter, q -> log_unsupported_filter("deals", filter); q
    end)
  end

  defp apply_company_filters(query, nil), do: query
  defp apply_company_filters(query, []), do: query

  defp apply_company_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "industry", op: "=", value: v}, q -> where(q, [c], c.industry == ^v)
      %{field: "region", op: "=", value: v}, q -> where(q, [c], c.region == ^v)
      %{field: "size", op: "=", value: v}, q -> where(q, [c], c.size == ^v)
      filter, q -> log_unsupported_filter("companies", filter); q
    end)
  end

  defp apply_contact_filters(query, nil), do: query
  defp apply_contact_filters(query, []), do: query

  defp apply_contact_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "stage", op: "=", value: v}, q -> where(q, [c], c.stage == ^v)
      filter, q -> log_unsupported_filter("contacts", filter); q
    end)
  end

  defp apply_activity_filters(query, nil), do: query
  defp apply_activity_filters(query, []), do: query

  defp apply_activity_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "type", op: "=", value: v}, q -> where(q, [a], a.type == ^v)
      %{field: "outcome", op: "=", value: v}, q -> where(q, [a], a.outcome == ^v)
      filter, q -> log_unsupported_filter("activities", filter); q
    end)
  end

  # --- Query modifiers ---

  defp apply_query_modifiers(query, intent) do
    query
    |> apply_sort(intent.sort)
    |> apply_limit(intent.limit)
  end

  # For grouped queries where :value is a computed aggregate
  defp apply_sort(query, nil), do: query
  defp apply_sort(query, %{direction: :desc}), do: order_by(query, [s], desc: :value)
  defp apply_sort(query, %{direction: :asc}), do: order_by(query, [s], asc: :value)
  defp apply_sort(query, _), do: query

  # For ungrouped queries where we need to sort by the actual column
  defp apply_sort_by_field(query, nil, _field), do: query
  defp apply_sort_by_field(query, %{direction: :desc}, field), do: order_by(query, [s], desc: ^field)
  defp apply_sort_by_field(query, %{direction: :asc}, field), do: order_by(query, [s], asc: ^field)
  defp apply_sort_by_field(query, _, _field), do: query

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  defp log_unsupported_filter(dataset, %{field: f, op: op, value: v}) do
    Logger.warning("[Resonance] #{dataset}: dropped unsupported filter #{f} #{op} #{inspect(v)}")
  end

  defp log_unsupported_filter(dataset, filter) do
    Logger.warning("[Resonance] #{dataset}: dropped unrecognized filter #{inspect(filter)}")
  end
end
