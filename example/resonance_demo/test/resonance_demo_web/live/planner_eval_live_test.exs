defmodule ResonanceDemoWeb.PlannerEvalLiveTest do
  use ResonanceDemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ResonanceDemo.Repo
  alias ResonanceDemo.CRM.{Activity, Company, Contact, Deal}

  test "renders the CRM planner eval surface", %{conn: conn} do
    attach_workspace_telemetry()
    seed_crm()

    {:ok, view, html} = live(conn, ~p"/planner-eval")

    assert_receive {:workspace_resolved, %{status: :ok}}, 5000

    assert html =~ "CRM planner proof"
    assert html =~ "12/12"
    assert html =~ "Run 1"
    assert html =~ "Show me pipeline health by stage and owner."
    assert html =~ "forecast vampires"
    assert html =~ "Board packet is tomorrow."
    assert html =~ "Compiled workspace preview"
    assert html =~ "Validation guardrail"
    assert html =~ "unsupported_measure"

    html =
      view
      |> element("button[phx-value-id='alice_focus']")
      |> render_click()

    assert html =~ "What should Alice focus on this week?"
    assert html =~ "Alice focus deals"
    assert html =~ "deal_focus_list"

    html = render_click(view, "run_eval")

    assert html =~ "Run 2"
  end

  defp seed_crm do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    enterprise =
      Repo.insert!(%Company{
        name: "Acme Corp",
        industry: "Technology",
        size: "Enterprise",
        revenue: 50_000_000,
        region: "West",
        inserted_at: now,
        updated_at: now
      })

    midmarket =
      Repo.insert!(%Company{
        name: "Globex",
        industry: "Manufacturing",
        size: "Midmarket",
        revenue: 12_000_000,
        region: "East",
        inserted_at: now,
        updated_at: now
      })

    contact =
      Repo.insert!(%Contact{
        name: "Morgan Lee",
        email: "morgan@example.com",
        stage: "lead",
        title: "VP Sales",
        company_id: enterprise.id,
        inserted_at: now,
        updated_at: now
      })

    Repo.insert!(%Activity{
      type: "email",
      date: Date.utc_today(),
      outcome: "no_response",
      notes: "Follow-up pending",
      contact_id: contact.id,
      inserted_at: now,
      updated_at: now
    })

    [
      %{
        name: "Acme expansion",
        value: 500_000,
        stage: "negotiation",
        owner: "Alice",
        quarter: "2025-Q1",
        company_id: enterprise.id
      },
      %{
        name: "Globex renewal",
        value: 300_000,
        stage: "proposal",
        owner: "Bob",
        quarter: "2025-Q2",
        company_id: midmarket.id
      },
      %{
        name: "Initech rollout",
        value: 180_000,
        stage: "closed_lost",
        owner: "Carol",
        quarter: "2025-Q3",
        company_id: enterprise.id
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
        company_id: attrs.company_id,
        inserted_at: now,
        updated_at: now
      })
    end)
  end

  defp attach_workspace_telemetry do
    handler_id = "planner-eval-live-test-#{System.unique_integer([:positive])}"
    parent = self()

    :telemetry.attach(
      handler_id,
      [:resonance, :workspace, :resolve, :stop],
      fn _event, _measurements, metadata, pid ->
        send(pid, {:workspace_resolved, metadata})
      end,
      parent
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
