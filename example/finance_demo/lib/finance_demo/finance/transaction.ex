defmodule FinanceDemo.Finance.Transaction do
  use Ecto.Schema

  schema "transactions" do
    field :amount, :integer
    field :date, :date
    field :description, :string
    field :merchant, :string
    field :type, :string

    belongs_to :account, FinanceDemo.Finance.Account
    belongs_to :category, FinanceDemo.Finance.Category
    timestamps()
  end
end
