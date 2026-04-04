alias ResonanceDemo.Repo
alias ResonanceDemo.CRM.{Company, Contact, Deal, Activity}

# Clear existing data
Repo.delete_all(Activity)
Repo.delete_all(Deal)
Repo.delete_all(Contact)
Repo.delete_all(Company)

# Companies
companies =
  [
    %{
      name: "Acme Corp",
      industry: "Technology",
      size: "Enterprise",
      revenue: 50_000_000,
      region: "West"
    },
    %{
      name: "GlobalTech",
      industry: "Technology",
      size: "Mid-Market",
      revenue: 12_000_000,
      region: "East"
    },
    %{
      name: "Pinnacle Health",
      industry: "Healthcare",
      size: "Enterprise",
      revenue: 85_000_000,
      region: "South"
    },
    %{
      name: "Stellar Manufacturing",
      industry: "Manufacturing",
      size: "Mid-Market",
      revenue: 25_000_000,
      region: "Midwest"
    },
    %{
      name: "Bright Education",
      industry: "Education",
      size: "Small",
      revenue: 3_000_000,
      region: "West"
    },
    %{
      name: "Summit Financial",
      industry: "Finance",
      size: "Enterprise",
      revenue: 120_000_000,
      region: "East"
    },
    %{
      name: "Verde Agriculture",
      industry: "Agriculture",
      size: "Mid-Market",
      revenue: 18_000_000,
      region: "Midwest"
    },
    %{
      name: "Nexus Logistics",
      industry: "Logistics",
      size: "Mid-Market",
      revenue: 22_000_000,
      region: "South"
    },
    %{
      name: "Horizon Media",
      industry: "Media",
      size: "Small",
      revenue: 5_000_000,
      region: "West"
    },
    %{
      name: "Atlas Construction",
      industry: "Construction",
      size: "Enterprise",
      revenue: 95_000_000,
      region: "East"
    },
    %{
      name: "Pacific Retail",
      industry: "Retail",
      size: "Mid-Market",
      revenue: 15_000_000,
      region: "West"
    },
    %{
      name: "Northern Energy",
      industry: "Energy",
      size: "Enterprise",
      revenue: 200_000_000,
      region: "Midwest"
    }
  ]
  |> Enum.map(fn attrs ->
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert!(
      %Company{}
      |> Map.merge(attrs)
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)
    )
  end)

# Contacts
stages = ["lead", "qualified", "opportunity", "customer", "churned"]
titles = ["CEO", "CTO", "VP Sales", "Director of Engineering", "Product Manager", "CFO"]

contacts =
  companies
  |> Enum.flat_map(fn company ->
    count = Enum.random(2..5)

    for i <- 1..count do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Repo.insert!(%Contact{
        name: "Contact #{company.id}-#{i}",
        email: "contact#{company.id}_#{i}@example.com",
        stage: Enum.random(stages),
        title: Enum.random(titles),
        company_id: company.id,
        inserted_at: now,
        updated_at: now
      })
    end
  end)

# Deals
deal_stages = ["prospecting", "discovery", "proposal", "negotiation", "closed_won", "closed_lost"]
owners = ["Alice", "Bob", "Carol", "Dave"]
quarters = ["2025-Q1", "2025-Q2", "2025-Q3", "2025-Q4", "2026-Q1"]

_deals =
  companies
  |> Enum.flat_map(fn company ->
    count = Enum.random(1..4)

    for i <- 1..count do
      stage = Enum.random(deal_stages)
      quarter = Enum.random(quarters)
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      Repo.insert!(%Deal{
        name: "Deal #{company.name} ##{i}",
        value: Enum.random(10..500) * 1000,
        stage: stage,
        close_date: Date.add(Date.utc_today(), Enum.random(-180..180)),
        owner: Enum.random(owners),
        quarter: quarter,
        company_id: company.id,
        inserted_at: now,
        updated_at: now
      })
    end
  end)

# Activities
activity_types = ["call", "email", "meeting", "demo", "follow_up"]
outcomes = ["positive", "neutral", "negative", "no_response"]

contacts
|> Enum.each(fn contact ->
  count = Enum.random(3..10)

  for _i <- 1..count do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert!(%Activity{
      type: Enum.random(activity_types),
      date: Date.add(Date.utc_today(), Enum.random(-365..0)),
      outcome: Enum.random(outcomes),
      notes: "Activity note",
      contact_id: contact.id,
      inserted_at: now,
      updated_at: now
    })
  end
end)

IO.puts("Seeded: #{length(companies)} companies, #{length(contacts)} contacts")
