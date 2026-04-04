defmodule ResonanceDemo.CRM.Company do
  use Ecto.Schema

  schema "companies" do
    field :name, :string
    field :industry, :string
    field :size, :string
    field :revenue, :integer
    field :region, :string

    has_many :contacts, ResonanceDemo.CRM.Contact
    has_many :deals, ResonanceDemo.CRM.Deal

    timestamps()
  end
end
