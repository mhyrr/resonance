defmodule FinanceDemo.Finance.Category do
  use Ecto.Schema

  schema "categories" do
    field :name, :string
    field :color, :string

    belongs_to :parent, FinanceDemo.Finance.Category
    has_many :children, FinanceDemo.Finance.Category, foreign_key: :parent_id
    has_many :transactions, FinanceDemo.Finance.Transaction
    has_many :budgets, FinanceDemo.Finance.Budget
    timestamps()
  end
end
