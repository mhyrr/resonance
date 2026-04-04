defmodule ResonanceDemo.CRM.Activity do
  use Ecto.Schema

  schema "activities" do
    field :type, :string
    field :date, :date
    field :outcome, :string
    field :notes, :string

    belongs_to :contact, ResonanceDemo.CRM.Contact

    timestamps()
  end
end
