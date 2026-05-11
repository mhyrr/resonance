defmodule ResonanceDemoWeb.WorkspaceLiveTest do
  use ResonanceDemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Company, Deal}

  test "renders the hand-written workspace", %{conn: conn} do
    seed_pipeline()

    {:ok, view, _html} = live(conn, ~p"/workspace")

    assert eventually(fn ->
             html = render(view)

             html =~ "Pipeline review" and
               html =~ "Pipeline value by stage" and
               html =~ "Pipeline value by quarter" and
               html =~ "Largest open deals" and
               html =~ "Pipeline value by owner"
           end)
  end

  test "reruns the saved workspace snapshot", %{conn: conn} do
    seed_pipeline()

    {:ok, view, _html} = live(conn, ~p"/workspace")

    assert eventually(fn -> render(view) =~ "Pipeline value by stage" end)

    render_click(view, "rerun_workspace")

    assert eventually(fn ->
             render(view) =~ ~r/>1</
           end)
  end

  defp seed_pipeline do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    company =
      Repo.insert!(%Company{
        name: "Acme Corp",
        industry: "Technology",
        size: "Enterprise",
        revenue: 50_000_000,
        region: "West",
        inserted_at: now,
        updated_at: now
      })

    [
      %{
        name: "Acme expansion",
        value: 500_000,
        stage: "negotiation",
        owner: "Alice",
        quarter: "2025-Q1"
      },
      %{
        name: "Globex renewal",
        value: 300_000,
        stage: "proposal",
        owner: "Bob",
        quarter: "2025-Q2"
      },
      %{
        name: "Initech rollout",
        value: 180_000,
        stage: "discovery",
        owner: "Carol",
        quarter: "2025-Q3"
      }
    ]
    |> Enum.each(fn attrs ->
      Repo.insert!(%Deal{
        name: attrs.name,
        value: attrs.value,
        stage: attrs.stage,
        close_date: ~D[2026-06-30],
        owner: attrs.owner,
        quarter: attrs.quarter,
        company_id: company.id,
        inserted_at: now,
        updated_at: now
      })
    end)
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(_fun, 0), do: false
end
