defmodule ResonanceDemo.Repo.Migrations.CreateCrmTables do
  use Ecto.Migration

  def change do
    create table(:companies) do
      add :name, :string, null: false
      add :industry, :string
      add :size, :string
      add :revenue, :integer
      add :region, :string

      timestamps()
    end

    create table(:contacts) do
      add :name, :string, null: false
      add :email, :string
      add :stage, :string
      add :title, :string
      add :company_id, references(:companies, on_delete: :nothing)

      timestamps()
    end

    create index(:contacts, [:company_id])
    create index(:contacts, [:stage])

    create table(:deals) do
      add :name, :string, null: false
      add :value, :integer
      add :stage, :string
      add :close_date, :date
      add :owner, :string
      add :quarter, :string
      add :company_id, references(:companies, on_delete: :nothing)

      timestamps()
    end

    create index(:deals, [:company_id])
    create index(:deals, [:stage])
    create index(:deals, [:quarter])

    create table(:activities) do
      add :type, :string
      add :date, :date
      add :outcome, :string
      add :notes, :string
      add :contact_id, references(:contacts, on_delete: :nothing)

      timestamps()
    end

    create index(:activities, [:contact_id])
    create index(:activities, [:type])
  end
end
