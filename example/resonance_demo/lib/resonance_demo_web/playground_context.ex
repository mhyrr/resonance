defmodule ResonanceDemoWeb.PlaygroundContext do
  @moduledoc """
  `on_mount` hook that wires the CRM resolver and a "Simulate New Deals"
  helper into the Resonance widget playground.

  When set, the playground prefers each widget's `live_renderable/1` over its
  synthetic example data and the simulate button inserts random deals to
  exercise the live refresh path.
  """

  import Phoenix.Component, only: [assign: 3]

  import Ecto.Query
  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Company, Deal}

  @stages ~w(prospecting discovery proposal negotiation closed_won closed_lost)
  @owners ~w(Alice Bob Carol Dave)
  @quarters ~w(2025-Q1 2025-Q2 2025-Q3 2025-Q4 2026-Q1 2026-Q2)

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:resonance_context, %{resolver: ResonanceDemo.CRM.Resolver})
     |> assign(:simulate_label, "Simulate New Deals")
     |> assign(:simulate_fn, &__MODULE__.simulate_new_deals/0)}
  end

  @doc """
  Inserts a small batch of randomized deals so the playground's live widgets
  visibly change after a refresh. Returns `{:ok, message}` for the playground
  to flash to the user.
  """
  def simulate_new_deals do
    company_ids = Repo.all(from c in Company, select: c.id)
    count = Enum.random(5..12)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    deals =
      for _i <- 1..count do
        %{
          name: "New Deal ##{System.unique_integer([:positive, :monotonic])}",
          value: Enum.random(10..500) * 1000,
          stage: Enum.random(@stages),
          close_date: Date.add(Date.utc_today(), Enum.random(-90..180)),
          owner: Enum.random(@owners),
          quarter: Enum.random(@quarters),
          company_id: Enum.random(company_ids),
          inserted_at: now,
          updated_at: now
        }
      end

    {inserted, _} = Repo.insert_all(Deal, deals)
    total_value = deals |> Enum.map(& &1.value) |> Enum.sum()

    {:ok, "Added #{inserted} deals worth $#{format_value(total_value)}"}
  end

  defp format_value(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_value(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_value(n), do: Integer.to_string(n)
end
