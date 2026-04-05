defmodule FinanceDemo.Finance.Resolver do
  @moduledoc """
  Resonance resolver for the personal finance demo.

  Translates QueryIntents into Ecto queries against accounts,
  categories, transactions, and budgets.
  """

  @behaviour Resonance.Resolver

  require Logger
  import Ecto.Query
  alias FinanceDemo.Repo
  alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}

  @valid_datasets ~w(transactions categories accounts budgets)

  @impl true
  def describe do
    """
    Datasets:
    - "transactions" — fields: amount (integer cents, negative=debit, positive=credit), date, description, merchant, type (debit/credit), account_id, category_id
      measures: count(*), sum(amount), avg(amount)
      dimensions: category, account, month, merchant, type

    - "categories" — fields: name, color, parent_id (hierarchical — top-level categories have children)
      measures: count(*)
      dimensions: parent

    - "accounts" — fields: name, type (checking/savings/credit), institution, balance (integer cents)
      measures: count(*), sum(balance)
      dimensions: type, institution

    - "budgets" — fields: month (e.g. "2026-01"), amount (integer cents), category_id
      measures: sum(amount)
      dimensions: category, month

    Notes:
    - All monetary values are in cents. Divide by 100 for display.
    - Transactions with negative amounts are debits (spending). Positive are credits (income).
    - Categories are hierarchical: top-level (Housing, Food, etc.) with subcategories (Rent, Groceries, etc.)
    - When querying spending, use type="debit" filter and negate or use abs(amount).
    """
  end

  @impl true
  def validate(%Resonance.QueryIntent{dataset: dataset}, _context) do
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

  # --- Transactions ---

  defp query_for(%{dataset: "transactions", dimensions: ["category"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], c in Category, on: t.category_id == c.id)
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, c], c.name)

    {:ok, select_transaction_measure(q, intent.measures, :category)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["month"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> group_by([t], fragment("strftime('%Y-%m', ?)", t.date))
      |> order_by([t], asc: fragment("strftime('%Y-%m', ?)", t.date))

    q =
      case primary_measure(intent.measures) do
        :sum_amount ->
          select(q, [t], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            value: sum(t.amount)
          })

        _ ->
          select(q, [t], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            value: count(t.id)
          })
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["merchant"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> group_by([t], t.merchant)

    {:ok, select_transaction_measure(q, intent.measures, :merchant)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["account"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], a in Account, on: t.account_id == a.id)
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, a], a.name)

    q =
      case primary_measure(intent.measures) do
        :sum_amount ->
          select(q, [t, a], %{label: a.name, value: sum(t.amount)})

        _ ->
          select(q, [t, a], %{label: a.name, value: count(t.id)})
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["type"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> group_by([t], t.type)

    {:ok, select_transaction_measure(q, intent.measures, :type)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["category", "month"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], c in Category, on: t.category_id == c.id)
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, c], [c.name, fragment("strftime('%Y-%m', ?)", t.date)])

    q =
      case primary_measure(intent.measures) do
        :sum_amount ->
          select(q, [t, c], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            series: c.name,
            group: c.name,
            value: sum(t.amount)
          })

        _ ->
          select(q, [t, c], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            series: c.name,
            group: c.name,
            value: count(t.id)
          })
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "transactions"} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> select([t], %{label: t.merchant, value: t.amount})
      |> apply_sort_by_field(intent.sort, :amount)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Categories ---

  defp query_for(%{dataset: "categories", dimensions: ["parent"]} = intent) do
    q =
      Category
      |> where([c], not is_nil(c.parent_id))
      |> join(:inner, [c], p in Category, on: c.parent_id == p.id)
      |> group_by([c, p], p.name)
      |> select([c, p], %{label: p.name, value: count(c.id)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "categories"} = intent) do
    q =
      Category
      |> where([c], is_nil(c.parent_id))
      |> select([c], %{label: c.name, value: 1})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # --- Accounts ---

  defp query_for(%{dataset: "accounts", dimensions: ["type"]} = intent) do
    q =
      Account
      |> group_by([a], a.type)

    q =
      case primary_measure(intent.measures) do
        :sum_balance ->
          select(q, [a], %{label: a.type, value: sum(a.balance)})

        _ ->
          select(q, [a], %{label: a.type, value: count(a.id)})
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "accounts"} = intent) do
    q =
      Account
      |> select([a], %{label: a.name, value: a.balance})
      |> apply_sort_by_field(intent.sort, :balance)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Budgets ---

  defp query_for(%{dataset: "budgets", dimensions: ["category"]} = intent) do
    q =
      Budget
      |> join(:inner, [b], c in Category, on: b.category_id == c.id)
      |> apply_budget_filters(intent.filters)
      |> group_by([b, c], c.name)
      |> select([b, c], %{label: c.name, value: sum(b.amount)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "budgets", dimensions: ["month"]} = intent) do
    q =
      Budget
      |> apply_budget_filters(intent.filters)
      |> group_by([b], b.month)
      |> select([b], %{label: b.month, period: b.month, value: sum(b.amount)})
      |> order_by([b], asc: b.month)

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "budgets"} = intent) do
    q =
      Budget
      |> join(:inner, [b], c in Category, on: b.category_id == c.id)
      |> apply_budget_filters(intent.filters)
      |> select([b, c], %{label: c.name, value: b.amount})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # Fallback
  defp query_for(%{dataset: dataset}) do
    {:error, {:unsupported_query, dataset}}
  end

  # --- Helpers ---

  defp primary_measure(nil), do: :count
  defp primary_measure([]), do: :count

  defp primary_measure([first | _]) do
    cond do
      String.contains?(first, "sum(amount)") -> :sum_amount
      String.contains?(first, "avg(amount)") -> :avg_amount
      String.contains?(first, "sum(balance)") -> :sum_balance
      true -> :count
    end
  end

  defp select_transaction_measure(query, measures, label_field) do
    case {primary_measure(measures), label_field} do
      {:sum_amount, :category} ->
        select(query, [t, c], %{label: c.name, value: sum(t.amount)})

      {:sum_amount, :merchant} ->
        select(query, [t], %{label: t.merchant, value: sum(t.amount)})

      {:sum_amount, :type} ->
        select(query, [t], %{label: t.type, value: sum(t.amount)})

      {_, :category} ->
        select(query, [t, c], %{label: c.name, value: count(t.id)})

      {_, :merchant} ->
        select(query, [t], %{label: t.merchant, value: count(t.id)})

      {_, :type} ->
        select(query, [t], %{label: t.type, value: count(t.id)})
    end
  end

  defp apply_transaction_filters(query, nil), do: query
  defp apply_transaction_filters(query, []), do: query

  defp apply_transaction_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "type", op: "=", value: v}, q ->
        where(q, [t], t.type == ^v)

      %{field: "merchant", op: "=", value: v}, q ->
        where(q, [t], t.merchant == ^v)

      %{field: "category", op: "=", value: v}, q ->
        # Subquery avoids conflicting with dimension joins on categories
        cat_ids =
          from(c in Category,
            left_join: p in Category,
            on: c.parent_id == p.id,
            where: c.name == ^v or p.name == ^v,
            select: c.id
          )

        where(q, [t], t.category_id in subquery(cat_ids))

      filter, q ->
        log_unsupported_filter("transactions", filter)
        q
    end)
  end

  defp apply_budget_filters(query, nil), do: query
  defp apply_budget_filters(query, []), do: query

  defp apply_budget_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "month", op: "=", value: v}, q -> where(q, [b], b.month == ^v)
      filter, q -> log_unsupported_filter("budgets", filter); q
    end)
  end

  defp apply_query_modifiers(query, intent) do
    query
    |> apply_sort(intent.sort)
    |> apply_limit(intent.limit)
  end

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, %{direction: :desc}), do: order_by(query, [s], desc: :value)
  defp apply_sort(query, %{direction: :asc}), do: order_by(query, [s], asc: :value)
  defp apply_sort(query, _), do: query

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
