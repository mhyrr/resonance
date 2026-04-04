defmodule FinanceDemo.Finance.Account do
  use Ecto.Schema

  schema "accounts" do
    field :name, :string
    field :type, :string
    field :institution, :string
    field :balance, :integer

    has_many :transactions, FinanceDemo.Finance.Transaction
    timestamps()
  end
end
