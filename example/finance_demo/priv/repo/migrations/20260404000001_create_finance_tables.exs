defmodule FinanceDemo.Repo.Migrations.CreateFinanceTables do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :institution, :string
      add :balance, :integer, default: 0
      timestamps()
    end

    create table(:categories) do
      add :name, :string, null: false
      add :color, :string
      add :parent_id, references(:categories, on_delete: :nothing)
      timestamps()
    end

    create index(:categories, [:parent_id])

    create table(:transactions) do
      add :amount, :integer, null: false
      add :date, :date, null: false
      add :description, :string
      add :merchant, :string
      add :type, :string, null: false
      add :account_id, references(:accounts, on_delete: :nothing), null: false
      add :category_id, references(:categories, on_delete: :nothing), null: false
      timestamps()
    end

    create index(:transactions, [:account_id])
    create index(:transactions, [:category_id])
    create index(:transactions, [:date])
    create index(:transactions, [:type])

    create table(:budgets) do
      add :month, :string, null: false
      add :amount, :integer, null: false
      add :category_id, references(:categories, on_delete: :nothing), null: false
      timestamps()
    end

    create index(:budgets, [:category_id])
    create unique_index(:budgets, [:category_id, :month])
  end
end
