defmodule FinanceDemo.Finance.ResolverTest do
  use FinanceDemo.DataCase

  alias FinanceDemo.Finance.Resolver
  alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}
  alias Resonance.QueryIntent

  setup do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    account =
      Repo.insert!(%Account{
        name: "Checking",
        type: "checking",
        institution: "Chase",
        balance: 1000_00,
        inserted_at: now,
        updated_at: now
      })

    food =
      Repo.insert!(%Category{
        name: "Food",
        color: "#059669",
        parent_id: nil,
        inserted_at: now,
        updated_at: now
      })

    groceries =
      Repo.insert!(%Category{
        name: "Groceries",
        color: "#059669",
        parent_id: food.id,
        inserted_at: now,
        updated_at: now
      })

    transport =
      Repo.insert!(%Category{
        name: "Transportation",
        color: "#D97706",
        parent_id: nil,
        inserted_at: now,
        updated_at: now
      })

    for {amt, merchant, cat, date} <- [
          {-50_00, "Whole Foods", groceries, ~D[2026-03-01]},
          {-30_00, "Trader Joe's", groceries, ~D[2026-03-08]},
          {-25_00, "Shell", transport, ~D[2026-03-05]},
          {-60_00, "Whole Foods", groceries, ~D[2026-03-15]},
          {3200_00, "Employer", food, ~D[2026-03-01]}
        ] do
      Repo.insert!(%Transaction{
        amount: amt,
        date: date,
        description: "Purchase",
        merchant: merchant,
        type: if(amt > 0, do: "credit", else: "debit"),
        account_id: account.id,
        category_id: cat.id,
        inserted_at: now,
        updated_at: now
      })
    end

    Repo.insert!(%Budget{
      month: "2026-03",
      amount: 600_00,
      category_id: food.id,
      inserted_at: now,
      updated_at: now
    })

    %{account: account, food: food, groceries: groceries, transport: transport}
  end

  describe "validate/2" do
    test "accepts valid datasets" do
      for ds <- ~w(transactions categories accounts budgets) do
        intent = %QueryIntent{dataset: ds, measures: ["count(*)"]}
        assert :ok = Resolver.validate(intent, %{})
      end
    end

    test "rejects unknown datasets" do
      intent = %QueryIntent{dataset: "secrets", measures: ["count(*)"]}
      assert {:error, {:unknown_dataset, "secrets"}} = Resolver.validate(intent, %{})
    end
  end

  describe "resolve/2 — transactions" do
    test "groups by category" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["count(*)"],
        dimensions: ["category"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      labels = Enum.map(data, & &1.label)
      assert "Groceries" in labels
      assert "Transportation" in labels
    end

    test "groups by merchant with sum(amount)" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["sum(amount)"],
        dimensions: ["merchant"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      wf = Enum.find(data, &(&1.label == "Whole Foods"))
      assert wf.value == -110_00
    end

    test "groups by type" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["count(*)"],
        dimensions: ["type"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      types = Enum.map(data, & &1.label)
      assert "debit" in types
      assert "credit" in types
    end

    test "groups by month" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["sum(amount)"],
        dimensions: ["month"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      assert length(data) >= 1
      assert hd(data).period =~ ~r/\d{4}-\d{2}/
    end

    test "filters by type" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["count(*)"],
        dimensions: ["category"],
        filters: [%{field: "type", op: "=", value: "debit"}]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      # Should not include the credit transaction (salary)
      total = Enum.reduce(data, 0, fn row, acc -> acc + row.value end)
      assert total == 4
    end
  end

  describe "resolve/2 — accounts" do
    test "groups by type" do
      intent = %QueryIntent{
        dataset: "accounts",
        measures: ["sum(balance)"],
        dimensions: ["type"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      checking = Enum.find(data, &(&1.label == "checking"))
      assert checking.value == 1000_00
    end
  end

  describe "resolve/2 — budgets" do
    test "groups by category" do
      intent = %QueryIntent{
        dataset: "budgets",
        measures: ["sum(amount)"],
        dimensions: ["category"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      food_budget = Enum.find(data, &(&1.label == "Food"))
      assert food_budget.value == 600_00
    end
  end

  describe "describe/0" do
    test "returns non-empty description" do
      desc = Resolver.describe()
      assert is_binary(desc)
      assert String.contains?(desc, "transactions")
      assert String.contains?(desc, "categories")
      assert String.contains?(desc, "accounts")
      assert String.contains?(desc, "budgets")
    end
  end
end
