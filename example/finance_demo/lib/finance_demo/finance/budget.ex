defmodule FinanceDemo.Finance.Budget do
  use Ecto.Schema

  schema "budgets" do
    field :month, :string
    field :amount, :integer

    belongs_to :category, FinanceDemo.Finance.Category
    timestamps()
  end
end
