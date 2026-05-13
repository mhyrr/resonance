defmodule ResonanceDemo.CRM.ResolverTest do
  use ResonanceDemo.DataCase, async: false

  alias Resonance.QueryIntent
  alias ResonanceDemo.CRM.{Company, Contact, Resolver}

  test "ranks contacts by name without ordering by a nonexistent value column" do
    company = insert_company!()
    insert_contact!(company, %{name: "Alex Buyer", email: "alex-1@example.com"})
    insert_contact!(company, %{name: "Alex Buyer", email: "alex-2@example.com"})
    insert_contact!(company, %{name: "Beth Buyer", email: "beth@example.com"})

    intent = %QueryIntent{
      dataset: "contacts",
      measures: ["count(*)"],
      dimensions: ["name"],
      sort: %{field: "count(*)", direction: :desc},
      limit: 10
    }

    assert {:ok, rows} = Resolver.resolve(intent, %{})
    assert [%{label: "Alex Buyer", value: 2} | _] = rows
    assert Enum.any?(rows, &(&1.label == "Beth Buyer" and &1.value == 1))
  end

  defp insert_company! do
    now = now()

    Repo.insert!(%Company{
      name: "Acme",
      industry: "Technology",
      size: "Enterprise",
      revenue: 10_000_000,
      region: "West",
      inserted_at: now,
      updated_at: now
    })
  end

  defp insert_contact!(company, attrs) do
    now = now()

    Repo.insert!(%Contact{
      name: attrs.name,
      email: attrs.email,
      stage: Map.get(attrs, :stage, "lead"),
      title: Map.get(attrs, :title, "VP Sales"),
      company_id: company.id,
      inserted_at: now,
      updated_at: now
    })
  end

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
