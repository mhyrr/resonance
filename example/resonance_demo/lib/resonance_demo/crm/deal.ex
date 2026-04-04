defmodule ResonanceDemo.CRM.Deal do
  use Ecto.Schema

  schema "deals" do
    field :name, :string
    field :value, :integer
    field :stage, :string
    field :close_date, :date
    field :owner, :string
    field :quarter, :string

    belongs_to :company, ResonanceDemo.CRM.Company

    timestamps()
  end
end
