defmodule ResonanceDemo.CRM.Contact do
  use Ecto.Schema

  schema "contacts" do
    field :name, :string
    field :email, :string
    field :stage, :string
    field :title, :string

    belongs_to :company, ResonanceDemo.CRM.Company
    has_many :activities, ResonanceDemo.CRM.Activity

    timestamps()
  end
end
