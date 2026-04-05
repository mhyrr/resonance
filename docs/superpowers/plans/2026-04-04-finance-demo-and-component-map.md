# Finance Demo & Pluggable Component Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pluggable component mapping system to the Resonance library, then build a second example app (personal finance dashboard with ECharts) that proves the semantic layer is fully decoupled from visualization.

**Architecture:** Primitives currently hardcode component modules in `present/2`. We add a `component_map` in context so consuming apps can swap entire visualization libraries. The finance demo uses ECharts instead of ApexCharts, with the same semantic primitives producing the same data shapes but rendering completely different visualizations (treemap, ECharts bar/line). The Live.Report component passes `components` through to primitives via context.

**Tech Stack:** Elixir/Phoenix LiveView, ECharts (Apache), SQLite, Ecto

---

## File Structure

### Library changes (existing files to modify)

- `lib/resonance/components.ex` — **CREATE**: Parent module with `resolve/2` for component lookup
- `lib/resonance/primitives/compare_over_time.ex` — Use `Components.resolve` instead of hardcoded modules
- `lib/resonance/primitives/rank_entities.ex` — Same
- `lib/resonance/primitives/show_distribution.ex` — Same
- `lib/resonance/primitives/segment_population.ex` — Same
- `lib/resonance/primitives/summarize_findings.ex` — Same
- `lib/resonance/components/bar_chart.ex` — Add `chart_dom_id/1`
- `lib/resonance/components/line_chart.ex` — Add `chart_dom_id/1`
- `lib/resonance/components/pie_chart.ex` — Add `chart_dom_id/1`
- `lib/resonance/live/report.ex` — Accept `components` assign, pass through context, use extensible `chart_dom_id`
- `test/resonance/components_test.exs` — **CREATE**: Tests for component resolution
- `mix.exs` — Update `test.all`/`build.all`/`setup` aliases

### Finance demo (new app, `example/finance_demo/`)

Created via `mix phx.new`, then customized:

- `lib/finance_demo/finance/account.ex` — Ecto schema
- `lib/finance_demo/finance/category.ex` — Ecto schema (self-referential for hierarchy)
- `lib/finance_demo/finance/transaction.ex` — Ecto schema
- `lib/finance_demo/finance/budget.ex` — Ecto schema
- `lib/finance_demo/finance/resolver.ex` — `Resonance.Resolver` implementation
- `lib/finance_demo/components/echarts_bar.ex` — ECharts bar component
- `lib/finance_demo/components/echarts_line.ex` — ECharts line component
- `lib/finance_demo/components/echarts_treemap.ex` — ECharts treemap component
- `lib/finance_demo_web/live/explore_live.ex` — Finance dashboard page
- `assets/js/echarts_hooks.js` — ECharts LiveView hooks
- `assets/js/app.js` — Modified to import ECharts hooks
- `priv/repo/migrations/20260404000001_create_finance_tables.exs` — Migration
- `priv/repo/seeds.exs` — 6 months of realistic personal finance data
- `config/runtime.exs` — Resonance LLM config
- `config/dev.exs` — Port 4001 (CRM uses 4000)
- `test/finance_demo/finance/resolver_test.exs` — Resolver tests
- `README.md` — Domain documentation

### READMEs

- `example/resonance_demo/README.md` — **CREATE**: CRM demo documentation
- `example/finance_demo/README.md` — **CREATE**: Finance demo documentation

---

## Task 1: Library — Component Resolution System

**Files:**
- Create: `lib/resonance/components.ex`
- Modify: `lib/resonance/primitives/compare_over_time.ex`
- Modify: `lib/resonance/primitives/rank_entities.ex`
- Modify: `lib/resonance/primitives/show_distribution.ex`
- Modify: `lib/resonance/primitives/segment_population.ex`
- Modify: `lib/resonance/primitives/summarize_findings.ex`
- Modify: `lib/resonance/live/report.ex`

- [ ] **Step 1: Create `lib/resonance/components.ex`**

```elixir
defmodule Resonance.Components do
  @moduledoc """
  Component resolution for pluggable presentation layers.

  Primitives call `resolve/2` to look up which component module to use.
  By default, the built-in ApexCharts-based components are returned.
  Consuming apps can override by passing a `:components` map in context.

  ## Usage

      # In your LiveView:
      <.live_component
        module={Resonance.Live.Report}
        id="report"
        resolver={MyResolver}
        components={%{
          bar_chart: MyApp.Components.EChartsBar,
          line_chart: MyApp.Components.EChartsLine,
          pie_chart: MyApp.Components.EChartsTreemap
        }}
      />

  Any key not overridden falls back to the built-in default.
  """

  @defaults %{
    line_chart: Resonance.Components.LineChart,
    bar_chart: Resonance.Components.BarChart,
    pie_chart: Resonance.Components.PieChart,
    data_table: Resonance.Components.DataTable,
    metric_grid: Resonance.Components.MetricGrid,
    metric_card: Resonance.Components.MetricCard,
    prose_section: Resonance.Components.ProseSection,
    error_display: Resonance.Components.ErrorDisplay
  }

  @doc """
  Resolve a component key to a module, checking context overrides first.
  """
  def resolve(context, key) when is_atom(key) do
    custom = get_in(context || %{}, [:components, key])
    custom || Map.fetch!(@defaults, key)
  end

  @doc """
  Return the full defaults map.
  """
  def defaults, do: @defaults
end
```

- [ ] **Step 2: Update `compare_over_time.ex` `present/2`**

Replace the existing `present/2` function (lines 78-100):

```elixir
@impl true
def present(data, context) do
  if multi_series?(data.data, data.intent) do
    Resonance.Renderable.ready(
      "compare_over_time",
      Resonance.Components.resolve(context, :line_chart),
      %{
        title: data.title,
        data: data.data,
        multi_series: true
      }
    )
  else
    Resonance.Renderable.ready(
      "compare_over_time",
      Resonance.Components.resolve(context, :bar_chart),
      %{
        title: data.title,
        data: data.data,
        orientation: "vertical"
      }
    )
  end
end
```

- [ ] **Step 3: Update `rank_entities.ex` `present/2`**

Replace the existing `present/2` function (lines 85-107):

```elixir
@impl true
def present(data, context) do
  if length(data.data) <= 10 do
    Resonance.Renderable.ready(
      "rank_entities",
      Resonance.Components.resolve(context, :bar_chart),
      %{
        title: data.title,
        data: data.data,
        orientation: "horizontal"
      }
    )
  else
    Resonance.Renderable.ready(
      "rank_entities",
      Resonance.Components.resolve(context, :data_table),
      %{
        title: data.title,
        data: data.data,
        sortable: true
      }
    )
  end
end
```

- [ ] **Step 4: Update `show_distribution.ex` `present/2`**

Replace the existing `present/2` function (lines 67-89):

```elixir
@impl true
def present(data, context) do
  if length(data.data) <= 8 do
    Resonance.Renderable.ready(
      "show_distribution",
      Resonance.Components.resolve(context, :pie_chart),
      %{
        title: data.title,
        data: data.data,
        donut: true,
        show_percentages: true
      }
    )
  else
    Resonance.Renderable.ready(
      "show_distribution",
      Resonance.Components.resolve(context, :bar_chart),
      %{
        title: data.title,
        data: data.data,
        orientation: "horizontal"
      }
    )
  end
end
```

- [ ] **Step 5: Update `segment_population.ex` `present/2`**

Replace the existing `present/2` function (lines 69-99):

```elixir
@impl true
def present(data, context) do
  if length(data.data) <= 6 do
    metrics =
      Enum.map(data.data, fn row ->
        %{
          label: row[:label] || row["label"] || "Segment",
          value: row[:value] || row["value"] || row[:count] || row["count"] || 0,
          format: detect_format(row)
        }
      end)

    Resonance.Renderable.ready(
      "segment_population",
      Resonance.Components.resolve(context, :metric_grid),
      %{
        title: data.title,
        metrics: metrics,
        columns: min(length(metrics), 3)
      }
    )
  else
    Resonance.Renderable.ready(
      "segment_population",
      Resonance.Components.resolve(context, :data_table),
      %{
        title: data.title,
        data: data.data,
        sortable: true
      }
    )
  end
end
```

- [ ] **Step 6: Update `summarize_findings.ex` `present/2`**

Replace the existing `present/2` function (lines 74-84):

```elixir
@impl true
def present(data, context) do
  Resonance.Renderable.ready(
    "summarize_findings",
    Resonance.Components.resolve(context, :prose_section),
    %{
      title: data.title,
      content: data.content,
      style: "summary"
    }
  )
end
```

- [ ] **Step 7: Update `Live.Report` to accept and pass `components`**

In `lib/resonance/live/report.ex`, modify `update/2` to store the components assign (around line 40, after `assign_new(:current_user, ...)`):

Add this line:
```elixir
|> assign_new(:components, fn -> assigns[:components] end)
```

Then in `start_generation/2` (line 144), update the context to include components:

```elixir
context = %{
  resolver: socket.assigns.resolver,
  current_user: socket.assigns[:current_user],
  components: socket.assigns[:components]
}
```

Do the same in `refresh_data/1` (line 192):

```elixir
context = %{
  resolver: socket.assigns.resolver,
  current_user: socket.assigns[:current_user],
  components: socket.assigns[:components]
}
```

Also update the `assigns[:resolver]` passthrough at line 125 to also update components:

```elixir
socket =
  if assigns[:resolver], do: assign(socket, :resolver, assigns.resolver), else: socket

socket =
  if assigns[:components], do: assign(socket, :components, assigns.components), else: socket
```

- [ ] **Step 8: Run library tests**

Run: `cd /Users/mhyrr/work/resonance && mix test`
Expected: All 52 tests pass (no behavior change for default components)

- [ ] **Step 9: Commit**

```bash
git add lib/resonance/components.ex lib/resonance/primitives/ lib/resonance/live/report.ex
git commit -m "$(cat <<'EOF'
Add pluggable component_map for swappable presentation layers

Primitives now resolve components via Resonance.Components.resolve/2
instead of hardcoding modules. Consuming apps pass a :components map
to Live.Report to override any component (e.g., swap ApexCharts for
ECharts). Defaults are unchanged — no breaking change for existing apps.
EOF
)"
```

---

## Task 2: Library — Extensible Chart Updates

**Files:**
- Modify: `lib/resonance/components/bar_chart.ex`
- Modify: `lib/resonance/components/line_chart.ex`
- Modify: `lib/resonance/components/pie_chart.ex`
- Modify: `lib/resonance/live/report.ex`

- [ ] **Step 1: Add `chart_dom_id/1` to BarChart**

Add this function to `lib/resonance/components/bar_chart.ex` before the `render/1`:

```elixir
@doc false
def chart_dom_id(renderable_id), do: "resonance-bar-#{renderable_id}"
```

- [ ] **Step 2: Add `chart_dom_id/1` to LineChart**

Add to `lib/resonance/components/line_chart.ex`:

```elixir
@doc false
def chart_dom_id(renderable_id), do: "resonance-line-#{renderable_id}"
```

- [ ] **Step 3: Add `chart_dom_id/1` to PieChart**

Add to `lib/resonance/components/pie_chart.ex`:

```elixir
@doc false
def chart_dom_id(renderable_id), do: "resonance-pie-#{renderable_id}"
```

- [ ] **Step 4: Update `push_chart_update` and remove `chart_dom_id` in Live.Report**

Replace the `push_chart_update/2` and `chart_dom_id/1` private functions (lines 305-323) with:

```elixir
defp push_chart_update(socket, %Renderable{component: comp, id: id} = renderable) do
  if function_exported?(comp, :chart_dom_id, 1) do
    dom_id = comp.chart_dom_id(id)

    push_event(socket, "resonance:update-chart", %{
      id: dom_id,
      data: renderable.props[:data] || renderable.props["data"] || []
    })
  else
    socket
  end
end
```

Delete the old `chart_dom_id/1` function entirely.

- [ ] **Step 5: Run library tests**

Run: `cd /Users/mhyrr/work/resonance && mix test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/resonance/components/bar_chart.ex lib/resonance/components/line_chart.ex lib/resonance/components/pie_chart.ex lib/resonance/live/report.ex
git commit -m "$(cat <<'EOF'
Make chart update push extensible via chart_dom_id/1 callback

Chart components now declare their DOM id via chart_dom_id/1.
Live.Report uses function_exported? to check — custom chart
components just implement this callback to get live data updates.
EOF
)"
```

---

## Task 3: Library — Component Resolution Tests

**Files:**
- Create: `test/resonance/components_test.exs`

- [ ] **Step 1: Write tests**

```elixir
defmodule Resonance.ComponentsTest do
  use ExUnit.Case, async: true

  alias Resonance.Components

  describe "resolve/2" do
    test "returns default component when no overrides in context" do
      assert Components.resolve(%{}, :bar_chart) == Resonance.Components.BarChart
      assert Components.resolve(%{}, :line_chart) == Resonance.Components.LineChart
      assert Components.resolve(%{}, :pie_chart) == Resonance.Components.PieChart
      assert Components.resolve(%{}, :data_table) == Resonance.Components.DataTable
      assert Components.resolve(%{}, :metric_grid) == Resonance.Components.MetricGrid
      assert Components.resolve(%{}, :prose_section) == Resonance.Components.ProseSection
    end

    test "returns default when context is nil" do
      assert Components.resolve(nil, :bar_chart) == Resonance.Components.BarChart
    end

    test "returns custom component when overridden" do
      context = %{components: %{bar_chart: MyCustomBar}}
      assert Components.resolve(context, :bar_chart) == MyCustomBar
    end

    test "falls back to default for non-overridden keys" do
      context = %{components: %{bar_chart: MyCustomBar}}
      assert Components.resolve(context, :line_chart) == Resonance.Components.LineChart
    end

    test "raises on unknown component key" do
      assert_raise KeyError, fn ->
        Components.resolve(%{}, :nonexistent_chart)
      end
    end
  end

  describe "defaults/0" do
    test "returns all default component mappings" do
      defaults = Components.defaults()
      assert map_size(defaults) == 8
      assert defaults[:bar_chart] == Resonance.Components.BarChart
    end
  end
end
```

- [ ] **Step 2: Run the new test**

Run: `cd /Users/mhyrr/work/resonance && mix test test/resonance/components_test.exs`
Expected: All tests pass

- [ ] **Step 3: Run full test suite**

Run: `cd /Users/mhyrr/work/resonance && mix test`
Expected: 58+ tests pass (52 existing + 6 new)

- [ ] **Step 4: Commit**

```bash
git add test/resonance/components_test.exs
git commit -m "Add tests for pluggable component resolution"
```

---

## Task 4: CRM Demo — README

**Files:**
- Create: `example/resonance_demo/README.md`

- [ ] **Step 1: Write the CRM demo README**

```markdown
# CRM Demo — Resonance Example App

A sales CRM dashboard powered by Resonance's semantic analysis layer. Ask questions about your pipeline in natural language and get interactive charts and tables.

## Why CRM?

CRM data is universally understood in business contexts — deals, contacts, companies, activities. It exercises Resonance's core strengths:

- **Entity-centric queries** — "Who are our largest accounts?"
- **Pipeline analysis** — "Show me deals by stage"
- **Time comparisons** — "Q1 vs Q2 deal performance"
- **Multi-dimensional breakdowns** — "Revenue by stage and quarter"

## Visualization: ApexCharts

This demo uses [ApexCharts](https://apexcharts.com/) for all chart rendering. The semantic primitives select from:

| Primitive | Small data | Large data |
|-----------|-----------|------------|
| `compare_over_time` | Bar chart (vertical) | Line chart (multi-series) |
| `rank_entities` | Bar chart (horizontal) | Data table |
| `show_distribution` | Donut chart | Bar chart (horizontal) |
| `segment_population` | Metric grid | Data table |
| `summarize_findings` | Prose section | Prose section |

Charts use LiveView hooks (`phx-hook`) with `phx-update="ignore"` so ApexCharts manages its own DOM. Data updates flow via `push_event` for smooth in-place animation.

## Data Model

Four Ecto schemas backed by SQLite:

### Companies
- `name`, `industry`, `size` (Enterprise/Mid-Market/Small), `revenue`, `region` (West/East/South/Midwest)
- Has many contacts and deals

### Contacts
- `name`, `email`, `stage` (lead/qualified/opportunity/customer/churned), `title`
- Belongs to company, has many activities

### Deals
- `name`, `value` (integer cents), `stage` (prospecting/discovery/proposal/negotiation/closed_won/closed_lost)
- `close_date`, `owner` (Alice/Bob/Carol/Dave), `quarter` (e.g., 2025-Q1)
- Belongs to company

### Activities
- `type` (call/email/meeting/demo/follow_up), `date`, `outcome` (positive/neutral/negative/no_response)
- Belongs to contact

## The Resolver

`ResonanceDemo.CRM.Resolver` implements `Resonance.Resolver` with three callbacks:

### `describe/0`
Returns a string listing all datasets, their fields, valid measures, and dimensions. This becomes part of the LLM system prompt — it's how the model knows what data is available.

### `validate/2`
Checks that the requested dataset is in the allowed list (`companies`, `contacts`, `deals`, `activities`). This is the security boundary — prevents the LLM from requesting arbitrary tables.

### `resolve/2`
Translates a `Resonance.QueryIntent` into Ecto queries. Pattern-matches on dataset + dimensions to select the right query shape:

- **Deals**: Supports grouping by `stage`, `quarter`, `owner`, or `stage + quarter` (multi-series). Measures: `count(*)`, `sum(value)`, `avg(value)`.
- **Companies**: Grouping by `industry`, `region`, `size`. Measures: `count(*)`, `sum(revenue)`, `avg(revenue)`.
- **Contacts**: Grouping by `stage`. Measures: `count(*)`.
- **Activities**: Grouping by `type` or `outcome`. Measures: `count(*)`.

Filters are applied via pattern-matched `Enum.reduce` — each supported filter field has an explicit clause. Unsupported filters are logged and dropped (never error).

## Running

```bash
cd example/resonance_demo
mix setup
mix phx.server    # Runs on localhost:4000
```

Requires `ANTHROPIC_API_KEY` environment variable.

## Interactive Features

- **Prompt input** — Type any question about CRM data
- **Suggestion buttons** — Click pre-built queries to explore
- **Simulate New Deals** — Generates 5-12 random deals and refreshes the current report without re-calling the LLM (proves data refresh is decoupled from intent selection)
```

- [ ] **Step 2: Commit**

```bash
git add example/resonance_demo/README.md
git commit -m "Add README for CRM demo explaining domain, resolver, and visualization"
```

---

## Task 5: Finance Demo — Scaffold Phoenix App

**Files:**
- Create: entire `example/finance_demo/` directory via `mix phx.new`
- Modify: generated `config/dev.exs` (port 4001)
- Modify: generated `config/runtime.exs` (Resonance config)
- Modify: generated `mix.exs` (add resonance dep)
- Modify: generated `assets/package.json` (add echarts)

- [ ] **Step 1: Generate Phoenix app**

```bash
cd /Users/mhyrr/work/resonance/example
mix phx.new finance_demo --database sqlite3 --no-mailer --no-dashboard
```

Answer `Y` to install dependencies.

- [ ] **Step 2: Update `mix.exs` — add resonance dependency**

In `example/finance_demo/mix.exs`, add to the `deps` function:

```elixir
{:resonance, path: "../.."},
{:tidewave, "~> 0.5", only: :dev}
```

Also add the compiler to the project function (same as CRM demo):
```elixir
compilers: [:phoenix_live_view] ++ Mix.compilers(),
```

- [ ] **Step 3: Update `config/dev.exs` — use port 4001**

Change the HTTP port from 4000 to 4001:

```elixir
http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4001")],
```

Also add Tidewave to the endpoint if dev.exs has a pattern for it (follow the resonance_demo pattern).

- [ ] **Step 4: Update `config/runtime.exs` — add Resonance LLM config**

Add before the `PHX_SERVER` check:

```elixir
# Resonance LLM configuration
config :resonance,
  provider: :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: System.get_env("RESONANCE_MODEL") || "claude-sonnet-4-5",
  max_tokens: 4096
```

- [ ] **Step 5: Add echarts to `assets/package.json`**

```json
{
  "dependencies": {
    "echarts": "^5.6.0"
  }
}
```

- [ ] **Step 6: Install deps and verify**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo
mix deps.get
cd assets && npm install && cd ..
mix compile
```

Expected: Compiles without errors

- [ ] **Step 7: Commit**

```bash
git add example/finance_demo/
git commit -m "Scaffold finance_demo Phoenix app with ECharts dependency"
```

---

## Task 6: Finance Demo — Schemas and Migration

**Files:**
- Create: `example/finance_demo/lib/finance_demo/finance/account.ex`
- Create: `example/finance_demo/lib/finance_demo/finance/category.ex`
- Create: `example/finance_demo/lib/finance_demo/finance/transaction.ex`
- Create: `example/finance_demo/lib/finance_demo/finance/budget.ex`
- Create: `example/finance_demo/priv/repo/migrations/20260404000001_create_finance_tables.exs`

- [ ] **Step 1: Create Account schema**

```elixir
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
```

- [ ] **Step 2: Create Category schema**

```elixir
defmodule FinanceDemo.Finance.Category do
  use Ecto.Schema

  schema "categories" do
    field :name, :string
    field :color, :string

    belongs_to :parent, FinanceDemo.Finance.Category
    has_many :children, FinanceDemo.Finance.Category, foreign_key: :parent_id
    has_many :transactions, FinanceDemo.Finance.Transaction
    has_many :budgets, FinanceDemo.Finance.Budget

    timestamps()
  end
end
```

- [ ] **Step 3: Create Transaction schema**

```elixir
defmodule FinanceDemo.Finance.Transaction do
  use Ecto.Schema

  schema "transactions" do
    field :amount, :integer
    field :date, :date
    field :description, :string
    field :merchant, :string
    field :type, :string

    belongs_to :account, FinanceDemo.Finance.Account
    belongs_to :category, FinanceDemo.Finance.Category

    timestamps()
  end
end
```

- [ ] **Step 4: Create Budget schema**

```elixir
defmodule FinanceDemo.Finance.Budget do
  use Ecto.Schema

  schema "budgets" do
    field :month, :string
    field :amount, :integer

    belongs_to :category, FinanceDemo.Finance.Category

    timestamps()
  end
end
```

- [ ] **Step 5: Create migration**

```elixir
defmodule FinanceDemo.Repo.Migrations.CreateFinanceTables do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string, null: false
      add :type, :string, null: false
      add :institution, :string
      add :balance, :integer, default: 0

      timestamps()
    end

    create table(:categories) do
      add :name, :string, null: false
      add :color, :string
      add :parent_id, references(:categories, on_delete: :nothing)

      timestamps()
    end

    create index(:categories, [:parent_id])

    create table(:transactions) do
      add :amount, :integer, null: false
      add :date, :date, null: false
      add :description, :string
      add :merchant, :string
      add :type, :string, null: false
      add :account_id, references(:accounts, on_delete: :nothing), null: false
      add :category_id, references(:categories, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:transactions, [:account_id])
    create index(:transactions, [:category_id])
    create index(:transactions, [:date])
    create index(:transactions, [:type])

    create table(:budgets) do
      add :month, :string, null: false
      add :amount, :integer, null: false
      add :category_id, references(:categories, on_delete: :nothing), null: false

      timestamps()
    end

    create index(:budgets, [:category_id])
    create unique_index(:budgets, [:category_id, :month])
  end
end
```

- [ ] **Step 6: Run migration**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo
mix ecto.create
mix ecto.migrate
```

Expected: Tables created successfully

- [ ] **Step 7: Commit**

```bash
git add example/finance_demo/lib/finance_demo/finance/ example/finance_demo/priv/repo/migrations/
git commit -m "Add finance schemas: accounts, categories, transactions, budgets"
```

---

## Task 7: Finance Demo — Seed Data

**Files:**
- Modify: `example/finance_demo/priv/repo/seeds.exs`

- [ ] **Step 1: Write realistic seed data**

The seed generates 6 months of personal finance transactions with hierarchical categories, monthly budgets, and 3 accounts. Spending patterns should be realistic (rent is consistent, groceries weekly, coffee daily, etc.).

```elixir
alias FinanceDemo.Repo
alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}

# Clear existing data
Repo.delete_all(Transaction)
Repo.delete_all(Budget)
Repo.delete_all(Category)
Repo.delete_all(Account)

now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

# --- Accounts ---

checking = Repo.insert!(%Account{
  name: "Main Checking",
  type: "checking",
  institution: "Chase",
  balance: 4_250_00,
  inserted_at: now, updated_at: now
})

savings = Repo.insert!(%Account{
  name: "Emergency Fund",
  type: "savings",
  institution: "Marcus",
  balance: 12_000_00,
  inserted_at: now, updated_at: now
})

credit = Repo.insert!(%Account{
  name: "Rewards Card",
  type: "credit",
  institution: "Amex",
  balance: -1_830_00,
  inserted_at: now, updated_at: now
})

accounts = [checking, savings, credit]

# --- Categories (2-level hierarchy) ---

make_parent = fn name, color ->
  Repo.insert!(%Category{
    name: name, color: color, parent_id: nil,
    inserted_at: now, updated_at: now
  })
end

make_child = fn name, parent ->
  Repo.insert!(%Category{
    name: name, color: parent.color, parent_id: parent.id,
    inserted_at: now, updated_at: now
  })
end

# Parents
housing = make_parent.("Housing", "#4F46E5")
food = make_parent.("Food", "#059669")
transport = make_parent.("Transportation", "#D97706")
entertainment = make_parent.("Entertainment", "#DC2626")
utilities = make_parent.("Utilities", "#7C3AED")
health = make_parent.("Health", "#0891B2")
shopping = make_parent.("Shopping", "#E11D48")
income = make_parent.("Income", "#16A34A")

# Children
rent = make_child.("Rent", housing)
home_insurance = make_child.("Home Insurance", housing)
groceries = make_child.("Groceries", food)
restaurants = make_child.("Restaurants", food)
coffee = make_child.("Coffee", food)
gas = make_child.("Gas", transport)
car_insurance = make_child.("Car Insurance", transport)
parking = make_child.("Parking", transport)
streaming = make_child.("Streaming", entertainment)
dining_out = make_child.("Dining Out", entertainment)
events = make_child.("Events & Tickets", entertainment)
electric = make_child.("Electric", utilities)
internet = make_child.("Internet", utilities)
phone = make_child.("Phone", utilities)
gym = make_child.("Gym", health)
pharmacy = make_child.("Pharmacy", health)
clothing = make_child.("Clothing", shopping)
electronics = make_child.("Electronics", shopping)
salary = make_child.("Salary", income)
freelance = make_child.("Freelance", income)

# --- Budgets (monthly, for top-level categories) ---

months = for m <- -5..0 do
  date = Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: m)
  "#{date.year}-#{String.pad_leading(Integer.to_string(date.month), 2, "0")}"
end

budget_amounts = %{
  housing => 1_800_00,
  food => 600_00,
  transport => 300_00,
  entertainment => 200_00,
  utilities => 250_00,
  health => 100_00,
  shopping => 150_00
}

for {cat, amount} <- budget_amounts, month <- months do
  Repo.insert!(%Budget{
    category_id: cat.id, month: month, amount: amount,
    inserted_at: now, updated_at: now
  })
end

# --- Transactions ---

# Helper to generate transactions
gen_txn = fn attrs ->
  Repo.insert!(%Transaction{
    amount: attrs.amount,
    date: attrs.date,
    description: attrs.description,
    merchant: attrs.merchant,
    type: attrs.type,
    account_id: attrs.account_id,
    category_id: attrs.category_id,
    inserted_at: now,
    updated_at: now
  })
end

# Generate 6 months of data
today = Date.utc_today()
start_date = Date.shift(today, month: -5) |> Date.beginning_of_month()
total_days = Date.diff(today, start_date)

# Recurring monthly (rent, insurance, subscriptions)
for month_offset <- 0..5 do
  month_start = Date.shift(start_date, month: month_offset)

  # Rent — 1st of month
  gen_txn.(%{amount: -1_650_00, date: month_start, description: "Monthly rent",
    merchant: "Landlord", type: "debit", account_id: checking.id, category_id: rent.id})

  # Home insurance — 15th
  gen_txn.(%{amount: -95_00, date: Date.shift(month_start, day: 14),
    description: "Home insurance premium", merchant: "State Farm",
    type: "debit", account_id: checking.id, category_id: home_insurance.id})

  # Car insurance — 5th
  gen_txn.(%{amount: -125_00, date: Date.shift(month_start, day: 4),
    description: "Auto insurance", merchant: "GEICO",
    type: "debit", account_id: checking.id, category_id: car_insurance.id})

  # Streaming — 10th
  gen_txn.(%{amount: -15_99, date: Date.shift(month_start, day: 9),
    description: "Netflix", merchant: "Netflix",
    type: "debit", account_id: credit.id, category_id: streaming.id})
  gen_txn.(%{amount: -10_99, date: Date.shift(month_start, day: 9),
    description: "Spotify", merchant: "Spotify",
    type: "debit", account_id: credit.id, category_id: streaming.id})

  # Internet — 20th
  gen_txn.(%{amount: -75_00, date: Date.shift(month_start, day: 19),
    description: "Internet service", merchant: "Comcast",
    type: "debit", account_id: checking.id, category_id: internet.id})

  # Phone — 22nd
  gen_txn.(%{amount: -85_00, date: Date.shift(month_start, day: 21),
    description: "Phone plan", merchant: "T-Mobile",
    type: "debit", account_id: checking.id, category_id: phone.id})

  # Electric — varies
  gen_txn.(%{amount: -(Enum.random(80..150) * 100), date: Date.shift(month_start, day: 17),
    description: "Electric bill", merchant: "ConEd",
    type: "debit", account_id: checking.id, category_id: electric.id})

  # Gym — 1st
  gen_txn.(%{amount: -50_00, date: month_start,
    description: "Gym membership", merchant: "Planet Fitness",
    type: "debit", account_id: credit.id, category_id: gym.id})

  # Salary — 1st and 15th
  gen_txn.(%{amount: 3_200_00, date: month_start,
    description: "Paycheck", merchant: "Employer",
    type: "credit", account_id: checking.id, category_id: salary.id})
  gen_txn.(%{amount: 3_200_00, date: Date.shift(month_start, day: 14),
    description: "Paycheck", merchant: "Employer",
    type: "credit", account_id: checking.id, category_id: salary.id})
end

# Variable spending (groceries, restaurants, coffee, gas, etc.)
merchants = %{
  groceries => [{"Whole Foods", 45..120}, {"Trader Joe's", 30..80}, {"Costco", 80..200}],
  restaurants => [{"Chipotle", 12..18}, {"Thai Palace", 25..45}, {"Pizza Place", 15..30}],
  coffee => [{"Starbucks", 5..8}, {"Blue Bottle", 6..9}, {"Local Cafe", 4..7}],
  gas => [{"Shell", 35..65}, {"BP", 30..55}],
  dining_out => [{"Olive Garden", 40..80}, {"Sushi Bar", 50..90}],
  parking => [{"ParkMobile", 8..20}, {"City Garage", 15..30}],
  pharmacy => [{"CVS", 10..40}, {"Walgreens", 8..35}],
  clothing => [{"Uniqlo", 30..80}, {"Target", 20..60}],
  electronics => [{"Amazon", 20..150}, {"Best Buy", 50..300}]
}

# Frequency per week for each category
frequencies = %{
  groceries => 2, restaurants => 2, coffee => 4, gas => 1,
  dining_out => 1, parking => 2, pharmacy => 0.3,
  clothing => 0.2, electronics => 0.1
}

weeks = div(total_days, 7)

for {category, merchant_list} <- merchants,
    _week <- 1..weeks,
    _freq <- 1..max(1, round((frequencies[category] || 0.5) * 1)),
    :rand.uniform() < (frequencies[category] || 0.5) do
  {merchant_name, range} = Enum.random(merchant_list)
  amount = Enum.random(range) * 100
  day_offset = Enum.random(0..total_days)
  date = Date.shift(start_date, day: min(day_offset, total_days))

  # Use credit card for small purchases, checking for large
  account = if amount < 50_00, do: credit, else: Enum.random([checking, credit])

  gen_txn.(%{
    amount: -amount, date: date,
    description: "#{merchant_name} purchase",
    merchant: merchant_name,
    type: "debit",
    account_id: account.id, category_id: category.id
  })
end

# Occasional freelance income
for _i <- 1..Enum.random(2..5) do
  gen_txn.(%{
    amount: Enum.random(500..2000) * 100,
    date: Date.shift(start_date, day: Enum.random(0..total_days)),
    description: "Freelance project payment",
    merchant: "Client",
    type: "credit",
    account_id: checking.id,
    category_id: freelance.id
  })
end

# Occasional events
for _i <- 1..Enum.random(3..8) do
  gen_txn.(%{
    amount: -(Enum.random(25..150) * 100),
    date: Date.shift(start_date, day: Enum.random(0..total_days)),
    description: Enum.random(["Concert tickets", "Movie night", "Comedy show", "Sports game"]),
    merchant: Enum.random(["Ticketmaster", "AMC", "StubHub", "Eventbrite"]),
    type: "debit",
    account_id: credit.id,
    category_id: events.id
  })
end

txn_count = Repo.aggregate(Transaction, :count, :id)
cat_count = Repo.aggregate(Category, :count, :id)
IO.puts("Seeded: #{length(accounts)} accounts, #{cat_count} categories, #{txn_count} transactions, #{length(months)} months of budgets")
```

- [ ] **Step 2: Run seeds**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo
mix run priv/repo/seeds.exs
```

Expected: Output like "Seeded: 3 accounts, 20 categories, 350+ transactions, 6 months of budgets"

- [ ] **Step 3: Commit**

```bash
git add example/finance_demo/priv/repo/seeds.exs
git commit -m "Add realistic 6-month personal finance seed data"
```

---

## Task 8: Finance Demo — Resolver

**Files:**
- Create: `example/finance_demo/lib/finance_demo/finance/resolver.ex`

- [ ] **Step 1: Write the finance resolver**

```elixir
defmodule FinanceDemo.Finance.Resolver do
  @moduledoc """
  Resonance resolver for the personal finance demo.

  Translates QueryIntents into Ecto queries against accounts,
  categories, transactions, and budgets.
  """

  @behaviour Resonance.Resolver

  require Logger
  import Ecto.Query
  alias FinanceDemo.Repo
  alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}

  @valid_datasets ~w(transactions categories accounts budgets)

  @impl true
  def describe do
    """
    Datasets:
    - "transactions" — fields: amount (integer cents, negative=debit, positive=credit), date, description, merchant, type (debit/credit), account_id, category_id
      measures: count(*), sum(amount), avg(amount)
      dimensions: category, account, month, merchant, type

    - "categories" — fields: name, color, parent_id (hierarchical — top-level categories have children)
      measures: count(*)
      dimensions: parent

    - "accounts" — fields: name, type (checking/savings/credit), institution, balance (integer cents)
      measures: count(*), sum(balance)
      dimensions: type, institution

    - "budgets" — fields: month (e.g. "2026-01"), amount (integer cents), category_id
      measures: sum(amount)
      dimensions: category, month

    Notes:
    - All monetary values are in cents. Divide by 100 for display.
    - Transactions with negative amounts are debits (spending). Positive are credits (income).
    - Categories are hierarchical: top-level (Housing, Food, etc.) with subcategories (Rent, Groceries, etc.)
    - When querying spending, use type="debit" filter and negate or use abs(amount).
    """
  end

  @impl true
  def validate(%Resonance.QueryIntent{dataset: dataset}, _context) do
    if dataset in @valid_datasets,
      do: :ok,
      else: {:error, {:unknown_dataset, dataset}}
  end

  @impl true
  def resolve(%Resonance.QueryIntent{} = intent, _context) do
    case query_for(intent) do
      {:ok, query} ->
        {:ok, Repo.all(query)}

      {:error, _} = err ->
        err
    end
  rescue
    e -> {:error, {:query_failed, Exception.message(e)}}
  end

  # --- Transactions ---

  defp query_for(%{dataset: "transactions", dimensions: ["category"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], c in Category, on: t.category_id == c.id)
      |> maybe_join_parent()
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, c, ...], c.name)

    {:ok, select_transaction_measure(q, intent.measures, :category)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["month"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> select([t], %{
        label: fragment("strftime('%Y-%m', ?)", t.date),
        period: fragment("strftime('%Y-%m', ?)", t.date),
        value: ^select_agg_expr(intent.measures)
      })
      |> group_by([t], fragment("strftime('%Y-%m', ?)", t.date))
      |> order_by([t], asc: fragment("strftime('%Y-%m', ?)", t.date))

    {:ok, q}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["merchant"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> group_by([t], t.merchant)

    {:ok, select_transaction_measure(q, intent.measures, :merchant)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["account"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], a in Account, on: t.account_id == a.id)
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, a], a.name)

    q =
      case primary_measure(intent.measures) do
        :sum_amount ->
          select(q, [t, a], %{label: a.name, value: sum(t.amount)})

        _ ->
          select(q, [t, a], %{label: a.name, value: count(t.id)})
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "transactions", dimensions: ["type"]} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> group_by([t], t.type)

    {:ok, select_transaction_measure(q, intent.measures, :type)}
  end

  # Transactions with category + month (multi-series)
  defp query_for(%{dataset: "transactions", dimensions: ["category", "month"]} = intent) do
    q =
      Transaction
      |> join(:inner, [t], c in Category, on: t.category_id == c.id)
      |> apply_transaction_filters(intent.filters)
      |> group_by([t, c], [c.name, fragment("strftime('%Y-%m', ?)", t.date)])

    q =
      case primary_measure(intent.measures) do
        :sum_amount ->
          select(q, [t, c], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            series: c.name,
            group: c.name,
            value: sum(t.amount)
          })

        _ ->
          select(q, [t, c], %{
            label: fragment("strftime('%Y-%m', ?)", t.date),
            period: fragment("strftime('%Y-%m', ?)", t.date),
            series: c.name,
            group: c.name,
            value: count(t.id)
          })
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "transactions"} = intent) do
    q =
      Transaction
      |> apply_transaction_filters(intent.filters)
      |> select([t], %{label: t.merchant, value: t.amount})
      |> apply_sort_by_field(intent.sort, :amount)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Categories ---

  defp query_for(%{dataset: "categories", dimensions: ["parent"]} = intent) do
    q =
      Category
      |> where([c], not is_nil(c.parent_id))
      |> join(:inner, [c], p in Category, on: c.parent_id == p.id)
      |> group_by([c, p], p.name)
      |> select([c, p], %{label: p.name, value: count(c.id)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "categories"} = intent) do
    q =
      Category
      |> where([c], is_nil(c.parent_id))
      |> select([c], %{label: c.name, value: 1})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # --- Accounts ---

  defp query_for(%{dataset: "accounts", dimensions: ["type"]} = intent) do
    q =
      Account
      |> group_by([a], a.type)

    q =
      case primary_measure(intent.measures) do
        :sum_balance ->
          select(q, [a], %{label: a.type, value: sum(a.balance)})

        _ ->
          select(q, [a], %{label: a.type, value: count(a.id)})
      end

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "accounts"} = intent) do
    q =
      Account
      |> select([a], %{label: a.name, value: a.balance})
      |> apply_sort_by_field(intent.sort, :balance)
      |> apply_limit(intent.limit)

    {:ok, q}
  end

  # --- Budgets ---

  defp query_for(%{dataset: "budgets", dimensions: ["category"]} = intent) do
    q =
      Budget
      |> join(:inner, [b], c in Category, on: b.category_id == c.id)
      |> apply_budget_filters(intent.filters)
      |> group_by([b, c], c.name)
      |> select([b, c], %{label: c.name, value: sum(b.amount)})

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "budgets", dimensions: ["month"]} = intent) do
    q =
      Budget
      |> apply_budget_filters(intent.filters)
      |> group_by([b], b.month)
      |> select([b], %{label: b.month, period: b.month, value: sum(b.amount)})
      |> order_by([b], asc: b.month)

    {:ok, apply_query_modifiers(q, intent)}
  end

  defp query_for(%{dataset: "budgets"} = intent) do
    q =
      Budget
      |> join(:inner, [b], c in Category, on: b.category_id == c.id)
      |> apply_budget_filters(intent.filters)
      |> select([b, c], %{label: c.name, value: b.amount})

    {:ok, apply_query_modifiers(q, intent)}
  end

  # Fallback
  defp query_for(%{dataset: dataset}) do
    {:error, {:unsupported_query, dataset}}
  end

  # --- Helpers ---

  defp primary_measure(nil), do: :count
  defp primary_measure([]), do: :count

  defp primary_measure([first | _]) do
    cond do
      String.contains?(first, "sum(amount)") -> :sum_amount
      String.contains?(first, "avg(amount)") -> :avg_amount
      String.contains?(first, "sum(balance)") -> :sum_balance
      true -> :count
    end
  end

  defp select_agg_expr(measures) do
    case primary_measure(measures) do
      :sum_amount -> dynamic([t], sum(t.amount))
      :avg_amount -> dynamic([t], avg(t.amount))
      _ -> dynamic([t], count(t.id))
    end
  end

  defp select_transaction_measure(query, measures, label_field) do
    label_atom = label_field

    q =
      case primary_measure(measures) do
        :sum_amount when label_atom == :category ->
          select(query, [t, c, ...], %{label: c.name, value: sum(t.amount)})

        :sum_amount when label_atom == :merchant ->
          select(query, [t], %{label: t.merchant, value: sum(t.amount)})

        :sum_amount when label_atom == :type ->
          select(query, [t], %{label: t.type, value: sum(t.amount)})

        :avg_amount when label_atom == :category ->
          select(query, [t, c, ...], %{label: c.name, value: avg(t.amount)})

        _ when label_atom == :category ->
          select(query, [t, c, ...], %{label: c.name, value: count(t.id)})

        _ when label_atom == :merchant ->
          select(query, [t], %{label: t.merchant, value: count(t.id)})

        _ ->
          select(query, [t], %{label: t.type, value: count(t.id)})
      end

    apply_query_modifiers(q, %{sort: nil, limit: nil})
  end

  defp maybe_join_parent(query) do
    # Join parent category for hierarchical data — adds parent_name to result
    join(query, :left, [t, c], p in Category, on: c.parent_id == p.id)
  end

  defp apply_transaction_filters(query, nil), do: query
  defp apply_transaction_filters(query, []), do: query

  defp apply_transaction_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "type", op: "=", value: v}, q -> where(q, [t], t.type == ^v)
      %{field: "merchant", op: "=", value: v}, q -> where(q, [t], t.merchant == ^v)
      %{field: "account", op: "=", value: v}, q ->
        q |> join(:inner, [t], a in Account, on: t.account_id == a.id, as: :filter_account)
          |> where([filter_account: a], a.name == ^v)
      filter, q -> log_unsupported_filter("transactions", filter); q
    end)
  end

  defp apply_budget_filters(query, nil), do: query
  defp apply_budget_filters(query, []), do: query

  defp apply_budget_filters(query, filters) do
    Enum.reduce(filters, query, fn
      %{field: "month", op: "=", value: v}, q -> where(q, [b], b.month == ^v)
      filter, q -> log_unsupported_filter("budgets", filter); q
    end)
  end

  defp apply_query_modifiers(query, intent) do
    query
    |> apply_sort(intent.sort)
    |> apply_limit(intent.limit)
  end

  defp apply_sort(query, nil), do: query
  defp apply_sort(query, %{direction: :desc}), do: order_by(query, [s], desc: :value)
  defp apply_sort(query, %{direction: :asc}), do: order_by(query, [s], asc: :value)
  defp apply_sort(query, _), do: query

  defp apply_sort_by_field(query, nil, _field), do: query
  defp apply_sort_by_field(query, %{direction: :desc}, field), do: order_by(query, [s], desc: ^field)
  defp apply_sort_by_field(query, %{direction: :asc}, field), do: order_by(query, [s], asc: ^field)
  defp apply_sort_by_field(query, _, _field), do: query

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  defp log_unsupported_filter(dataset, %{field: f, op: op, value: v}) do
    Logger.warning("[Resonance] #{dataset}: dropped unsupported filter #{f} #{op} #{inspect(v)}")
  end

  defp log_unsupported_filter(dataset, filter) do
    Logger.warning("[Resonance] #{dataset}: dropped unrecognized filter #{inspect(filter)}")
  end
end
```

- [ ] **Step 2: Verify compilation**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo && mix compile
```

Expected: Compiles without errors

- [ ] **Step 3: Commit**

```bash
git add example/finance_demo/lib/finance_demo/finance/resolver.ex
git commit -m "Add finance resolver — transactions, categories, accounts, budgets"
```

---

## Task 9: Finance Demo — ECharts JS Hooks

**Files:**
- Create: `example/finance_demo/assets/js/echarts_hooks.js`
- Modify: `example/finance_demo/assets/js/app.js`

- [ ] **Step 1: Create ECharts hooks**

```javascript
/**
 * ECharts hooks for Phoenix LiveView.
 *
 * Drop-in replacement for ApexCharts hooks, using the same data contract
 * (data-chart-data JSON, resonance:update-chart events) but rendering
 * with Apache ECharts for different visualization styles.
 */

import * as echarts from "echarts";

function parseData(el) {
  try {
    return JSON.parse(el.dataset.chartData || "[]");
  } catch {
    return [];
  }
}

function initChart(el) {
  const existing = echarts.getInstanceByDom(el);
  if (existing) existing.dispose();
  return echarts.init(el);
}

export const EChartsLineChart = {
  mounted() {
    const data = parseData(this.el);
    const multiSeries = this.el.dataset.multiSeries === "true";
    this.chart = initChart(this.el);
    this.chart.setOption(buildLineOption(data, multiSeries));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        const multiSeries = this.el.dataset.multiSeries === "true";
        this.chart.setOption(buildLineOption(data, multiSeries), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

export const EChartsBarChart = {
  mounted() {
    const data = parseData(this.el);
    const horizontal = this.el.dataset.orientation === "horizontal";
    this.chart = initChart(this.el);
    this.chart.setOption(buildBarOption(data, horizontal));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        const horizontal = this.el.dataset.orientation === "horizontal";
        this.chart.setOption(buildBarOption(data, horizontal), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

export const EChartsTreemap = {
  mounted() {
    const data = parseData(this.el);
    this.chart = initChart(this.el);
    this.chart.setOption(buildTreemapOption(data));

    this.handleEvent("resonance:update-chart", ({ id, data }) => {
      if (id === this.el.id) {
        this.chart.setOption(buildTreemapOption(data), true);
      }
    });

    this._resizeHandler = () => this.chart.resize();
    window.addEventListener("resize", this._resizeHandler);
  },

  destroyed() {
    window.removeEventListener("resize", this._resizeHandler);
    if (this.chart) this.chart.dispose();
  },
};

// --- Option builders ---

function buildLineOption(data, multiSeries) {
  if (multiSeries) {
    const groups = {};
    const categories = [];
    for (const d of data) {
      const key = d.series || d.group || "default";
      const cat = d.period || d.label;
      if (!groups[key]) groups[key] = {};
      groups[key][cat] = d.value;
      if (!categories.includes(cat)) categories.push(cat);
    }

    const series = Object.entries(groups).map(([name, vals]) => ({
      name,
      type: "line",
      smooth: true,
      data: categories.map((c) => vals[c] || 0),
    }));

    return {
      tooltip: { trigger: "axis" },
      legend: { data: Object.keys(groups) },
      xAxis: { type: "category", data: categories },
      yAxis: { type: "value" },
      series,
      animation: true,
      animationDuration: 500,
    };
  }

  return {
    tooltip: { trigger: "axis" },
    xAxis: {
      type: "category",
      data: data.map((d) => d.period || d.label),
    },
    yAxis: { type: "value" },
    series: [
      {
        type: "line",
        smooth: true,
        data: data.map((d) => d.value),
        areaStyle: { opacity: 0.15 },
      },
    ],
    animation: true,
    animationDuration: 500,
  };
}

function buildBarOption(data, horizontal) {
  const labels = data.map((d) => d.label || d.period);
  const values = data.map((d) => Math.abs(d.value));

  const categoryAxis = { type: "category", data: labels };
  const valueAxis = { type: "value" };

  return {
    tooltip: { trigger: "axis" },
    xAxis: horizontal ? valueAxis : categoryAxis,
    yAxis: horizontal ? categoryAxis : valueAxis,
    series: [
      {
        type: "bar",
        data: values,
        itemStyle: {
          borderRadius: horizontal ? [0, 4, 4, 0] : [4, 4, 0, 0],
        },
      },
    ],
    animation: true,
    animationDuration: 500,
  };
}

function buildTreemapOption(data) {
  // Build hierarchy from flat data with parent field
  // If no parent field, treat as flat treemap
  const hasParent = data.some((d) => d.parent);

  let treeData;
  if (hasParent) {
    const parentMap = {};
    for (const d of data) {
      const parent = d.parent || "Other";
      if (!parentMap[parent]) parentMap[parent] = { name: parent, children: [] };
      parentMap[parent].children.push({
        name: d.label,
        value: Math.abs(d.value),
      });
    }
    treeData = Object.values(parentMap);
  } else {
    treeData = data.map((d) => ({
      name: d.label,
      value: Math.abs(d.value),
    }));
  }

  return {
    tooltip: {
      formatter: function (info) {
        const val = (info.value / 100).toLocaleString("en-US", {
          style: "currency",
          currency: "USD",
        });
        return `${info.name}: ${val}`;
      },
    },
    series: [
      {
        type: "treemap",
        data: treeData,
        leafDepth: 1,
        levels: [
          {
            itemStyle: { borderWidth: 2, borderColor: "#fff", gapWidth: 2 },
          },
          {
            itemStyle: { borderWidth: 1, borderColor: "#e5e7eb", gapWidth: 1 },
            upperLabel: { show: true, height: 20 },
          },
        ],
        label: {
          show: true,
          formatter: "{b}",
        },
      },
    ],
    animation: true,
    animationDuration: 500,
  };
}

export const EChartsPromptInput = {
  mounted() {
    this.handleEvent("resonance:set-prompt", ({ prompt }) => {
      this.el.value = prompt;
    });
  },
};

export const EChartsHooks = {
  EChartsLineChart,
  EChartsBarChart,
  EChartsTreemap,
  EChartsPromptInput,
};
```

- [ ] **Step 2: Update `app.js` to import ECharts hooks**

Replace the hooks section of `example/finance_demo/assets/js/app.js`. Find where `hooks` is defined in the `LiveSocket` constructor and update to:

```javascript
import {EChartsHooks} from "./echarts_hooks"

// In the LiveSocket constructor, merge EChartsHooks:
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...EChartsHooks},
})
```

Remove any ApexCharts import or `window.ApexCharts` line if the generator included them (it shouldn't since this is a fresh app).

- [ ] **Step 3: Verify assets build**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo
cd assets && npx esbuild js/app.js --bundle --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* && cd ..
```

Expected: Builds without errors

- [ ] **Step 4: Commit**

```bash
git add example/finance_demo/assets/js/echarts_hooks.js example/finance_demo/assets/js/app.js
git commit -m "Add ECharts LiveView hooks — line, bar, treemap with live updates"
```

---

## Task 10: Finance Demo — ECharts Components (Elixir)

**Files:**
- Create: `example/finance_demo/lib/finance_demo/components/echarts_bar.ex`
- Create: `example/finance_demo/lib/finance_demo/components/echarts_line.ex`
- Create: `example/finance_demo/lib/finance_demo/components/echarts_treemap.ex`

- [ ] **Step 1: Create EChartsBar component**

```elixir
defmodule FinanceDemo.Components.EChartsBar do
  @moduledoc """
  Bar chart component using Apache ECharts.
  """

  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-bar-#{renderable_id}"

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-bar-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-bar-#{@renderable_id}"}
        phx-hook="EChartsBarChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props.data)}
        data-orientation={@props[:orientation] || "vertical"}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 350px;"
      />
    </div>
    """
  end
end
```

- [ ] **Step 2: Create EChartsLine component**

```elixir
defmodule FinanceDemo.Components.EChartsLine do
  @moduledoc """
  Line chart component using Apache ECharts.
  """

  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-line-#{renderable_id}"

  def render(assigns) do
    assigns = assign_new(assigns, :multi_series, fn -> false end)

    ~H"""
    <div class="resonance-component resonance-line-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-line-#{@renderable_id}"}
        phx-hook="EChartsLineChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props.data)}
        data-multi-series={to_string(@props[:multi_series] || false)}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 350px;"
      />
    </div>
    """
  end
end
```

- [ ] **Step 3: Create EChartsTreemap component**

```elixir
defmodule FinanceDemo.Components.EChartsTreemap do
  @moduledoc """
  Treemap component using Apache ECharts.

  Replaces pie/donut charts for hierarchical category data.
  Accepts the same props as PieChart (data with label/value)
  plus optional parent field for nested layout.
  """

  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-treemap-#{renderable_id}"

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-treemap">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-treemap-#{@renderable_id}"}
        phx-hook="EChartsTreemap"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props[:data] || [])}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 400px;"
      />
    </div>
    """
  end
end
```

- [ ] **Step 4: Verify compilation**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo && mix compile
```

Expected: Compiles without errors

- [ ] **Step 5: Commit**

```bash
git add example/finance_demo/lib/finance_demo/components/
git commit -m "Add ECharts Phoenix components — bar, line, treemap"
```

---

## Task 11: Finance Demo — LiveView Page

**Files:**
- Modify: `example/finance_demo/lib/finance_demo_web/router.ex` (add `/explore` route)
- Create: `example/finance_demo/lib/finance_demo_web/live/explore_live.ex`

- [ ] **Step 1: Add route**

In `example/finance_demo/lib/finance_demo_web/router.ex`, add to the browser scope:

```elixir
live "/explore", ExploreLive
```

- [ ] **Step 2: Create ExploreLive**

```elixir
defmodule FinanceDemoWeb.ExploreLive do
  use FinanceDemoWeb, :live_view

  @suggestions [
    "Where did my money go last month?",
    "Show my spending by category",
    "What are my top 10 merchants by total spend?",
    "Compare my monthly spending trend over the last 6 months",
    "Break down my food spending — groceries vs restaurants vs coffee",
    "How much am I spending on transportation?",
    "Give me a full spending summary with trends and top categories"
  ]

  @component_map %{
    bar_chart: FinanceDemo.Components.EChartsBar,
    line_chart: FinanceDemo.Components.EChartsLine,
    pie_chart: FinanceDemo.Components.EChartsTreemap
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, suggestions: @suggestions, prompt: "")}
  end

  @impl true
  def handle_event("try_query", %{"prompt" => prompt}, socket) do
    send_update(Resonance.Live.Report, id: "explore-report", set_prompt: prompt)
    {:noreply, assign(socket, prompt: prompt)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto py-8 px-4">
      <div class="mb-8">
        <h1 class="text-2xl font-bold mb-2">Spending Explorer</h1>
        <p class="text-gray-600">Ask anything about your personal finances.</p>
      </div>

      <.live_component
        module={Resonance.Live.Report}
        id="explore-report"
        resolver={FinanceDemo.Finance.Resolver}
        components={@component_map}
      />

      <div class="mt-12 text-center text-gray-400">
        <p class="text-sm mb-3">Try one of these:</p>
        <div class="flex flex-wrap justify-center gap-2">
          <button
            :for={suggestion <- @suggestions}
            phx-click="try_query"
            phx-value-prompt={suggestion}
            class="text-sm px-3 py-1.5 rounded-full border border-gray-200 text-gray-500 hover:border-blue-300 hover:text-blue-600 transition-colors cursor-pointer"
          >
            {suggestion}
          </button>
        </div>
      </div>
    </div>
    """
  end
end
```

Note: the `@component_map` is the key — it swaps pie_chart for EChartsTreemap. Bar and line use ECharts too. Everything else (DataTable, MetricGrid, ProseSection) falls through to the library defaults.

- [ ] **Step 3: Verify compilation and page renders**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo && mix compile
```

Expected: Compiles without errors. Don't start the server — Greg manages that.

- [ ] **Step 4: Commit**

```bash
git add example/finance_demo/lib/finance_demo_web/router.ex example/finance_demo/lib/finance_demo_web/live/explore_live.ex
git commit -m "Add finance dashboard LiveView with ECharts component mapping"
```

---

## Task 12: Finance Demo — README

**Files:**
- Create: `example/finance_demo/README.md`

- [ ] **Step 1: Write the finance demo README**

```markdown
# Finance Demo — Resonance Example App

A personal finance dashboard powered by Resonance's semantic analysis layer. Ask questions about your spending in natural language and get interactive charts powered by Apache ECharts.

## Why Personal Finance?

This demo exists to prove that Resonance's semantic layer is fully decoupled from visualization. While the CRM demo uses ApexCharts, this app uses ECharts — same semantic primitives, same data contracts, completely different rendering.

The domain is intentionally different from CRM:

| Dimension | CRM Demo | Finance Demo |
|-----------|----------|--------------|
| **Data shape** | Entity-centric (companies, deals) | Category-hierarchical (spending categories with parent/child) |
| **User mindset** | "Who are my best accounts?" (open exploration) | "Am I on budget?" (goal-oriented) |
| **Time granularity** | Quarterly business reviews | Daily/weekly transactions |
| **Key metric** | Revenue (inflows) | Spending (outflows) |
| **Chart library** | ApexCharts | Apache ECharts |
| **Unique viz** | Donut charts, multi-series lines | Treemaps, area fills |

## Visualization: Apache ECharts

The component mapping swaps three chart types while keeping DataTable, MetricGrid, and ProseSection from the library defaults:

```elixir
@component_map %{
  bar_chart: FinanceDemo.Components.EChartsBar,
  line_chart: FinanceDemo.Components.EChartsLine,
  pie_chart: FinanceDemo.Components.EChartsTreemap
}
```

This is passed to `Resonance.Live.Report` via the `components` assign. Primitives call `Resonance.Components.resolve(context, :pie_chart)` and get `EChartsTreemap` instead of the default `PieChart`. No primitive code changes needed.

| Primitive | CRM renders as | Finance renders as |
|-----------|---------------|-------------------|
| `show_distribution` (few categories) | Donut chart (ApexCharts) | Treemap (ECharts) |
| `show_distribution` (many categories) | Horizontal bar (ApexCharts) | Horizontal bar (ECharts) |
| `compare_over_time` | Line/bar (ApexCharts) | Line with area fill (ECharts) |
| `rank_entities` | Horizontal bar (ApexCharts) | Horizontal bar (ECharts) |
| `segment_population` | Metric grid | Metric grid (library default) |
| `summarize_findings` | Prose section | Prose section (library default) |

### Treemap: The Killer Feature

The treemap is the standout visualization. When you ask "where did my money go?", the `show_distribution` primitive returns spending by category. In the CRM demo, that's a donut chart. Here, it's a **treemap** — nested rectangles sized by spend amount, with parent categories containing their subcategories. It makes hierarchical spending instantly legible.

The treemap component accepts the same `[%{label, value}]` data format as the pie chart, plus an optional `parent` field for hierarchy. The JS hook builds the tree structure client-side.

## Data Model

Four Ecto schemas backed by SQLite:

### Accounts
- `name`, `type` (checking/savings/credit), `institution`, `balance` (integer cents)
- Examples: "Main Checking" at Chase, "Rewards Card" at Amex

### Categories (hierarchical)
- `name`, `color`, `parent_id` (self-referential)
- Top-level: Housing, Food, Transportation, Entertainment, Utilities, Health, Shopping, Income
- Children: Housing > Rent, Food > Groceries, Food > Restaurants, Transportation > Gas, etc.

### Transactions
- `amount` (integer cents, negative = debit, positive = credit)
- `date`, `description`, `merchant`, `type` (debit/credit)
- Belongs to account and category

### Budgets
- `month` (e.g., "2026-01"), `amount` (integer cents)
- Belongs to category (top-level)
- One entry per category per month

## The Resolver

`FinanceDemo.Finance.Resolver` implements `Resonance.Resolver` with three callbacks:

### `describe/0`
Documents four datasets with all queryable fields, measures, and dimensions. Includes a note about cents-based amounts and the debit/credit convention. This goes into the LLM system prompt.

### `validate/2`
Whitelists `transactions`, `categories`, `accounts`, `budgets`. Rejects unknown datasets.

### `resolve/2`
Translates QueryIntents into Ecto queries. Key patterns:

- **Transactions by category**: Joins to categories table, groups by category name. Supports `sum(amount)`, `avg(amount)`, `count(*)`.
- **Transactions by month**: Uses SQLite `strftime('%Y-%m', date)` for month grouping. Returns `period` field for time-series rendering.
- **Transactions by merchant**: Groups by merchant name for "top merchants" queries.
- **Transactions by category + month**: Multi-series — one line per category over time.
- **Categories by parent**: Joins self-referentially for hierarchical views.
- **Accounts by type**: Groups checking/savings/credit with balance sums.
- **Budgets by category or month**: For budget vs. actual comparisons.

Filters support `type` (debit/credit), `merchant`, and `account` on transactions; `month` on budgets.

## Running

```bash
cd example/finance_demo
mix setup
mix phx.server    # Runs on localhost:4001
```

Requires `ANTHROPIC_API_KEY` environment variable.

## Sample Queries

- "Where did my money go last month?"
- "Show my spending by category"
- "What are my top 10 merchants by total spend?"
- "Compare my monthly spending trend over the last 6 months"
- "Break down my food spending — groceries vs restaurants vs coffee"
- "How much am I spending on transportation?"
- "Give me a full spending summary with trends and top categories"
```

- [ ] **Step 2: Commit**

```bash
git add example/finance_demo/README.md
git commit -m "Add README for finance demo explaining domain, ECharts, and resolver"
```

---

## Task 13: Integration — Top-Level Mix Aliases

**Files:**
- Modify: `mix.exs` (root)

- [ ] **Step 1: Update aliases in root `mix.exs`**

Replace the aliases function (lines 44-50):

```elixir
defp aliases do
  [
    "test.all": [
      "test",
      "cmd --cd example/resonance_demo mix test",
      "cmd --cd example/finance_demo mix test"
    ],
    "build.all": [
      "compile",
      "cmd --cd example/resonance_demo mix compile",
      "cmd --cd example/finance_demo mix compile"
    ],
    setup: [
      "deps.get",
      "cmd --cd example/resonance_demo mix setup",
      "cmd --cd example/finance_demo mix setup"
    ]
  ]
end
```

- [ ] **Step 2: Verify build.all**

```bash
cd /Users/mhyrr/work/resonance && mix build.all
```

Expected: All three projects compile without errors

- [ ] **Step 3: Commit**

```bash
git add mix.exs
git commit -m "Add finance_demo to top-level mix aliases (test.all, build.all, setup)"
```

---

## Task 14: Finance Demo — Resolver Tests

**Files:**
- Create: `example/finance_demo/test/finance_demo/finance/resolver_test.exs`

- [ ] **Step 1: Write resolver tests**

```elixir
defmodule FinanceDemo.Finance.ResolverTest do
  use FinanceDemo.DataCase

  alias FinanceDemo.Finance.Resolver
  alias FinanceDemo.Finance.{Account, Category, Transaction, Budget}
  alias Resonance.QueryIntent

  setup do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    account = Repo.insert!(%Account{
      name: "Checking", type: "checking", institution: "Chase", balance: 1000_00,
      inserted_at: now, updated_at: now
    })

    food = Repo.insert!(%Category{
      name: "Food", color: "#059669", parent_id: nil,
      inserted_at: now, updated_at: now
    })

    groceries = Repo.insert!(%Category{
      name: "Groceries", color: "#059669", parent_id: food.id,
      inserted_at: now, updated_at: now
    })

    transport = Repo.insert!(%Category{
      name: "Transportation", color: "#D97706", parent_id: nil,
      inserted_at: now, updated_at: now
    })

    for {amt, merchant, cat, date} <- [
      {-50_00, "Whole Foods", groceries, ~D[2026-03-01]},
      {-30_00, "Trader Joe's", groceries, ~D[2026-03-08]},
      {-25_00, "Shell", transport, ~D[2026-03-05]},
      {-60_00, "Whole Foods", groceries, ~D[2026-03-15]},
      {3200_00, "Employer", food, ~D[2026-03-01]}
    ] do
      Repo.insert!(%Transaction{
        amount: amt, date: date, description: "Purchase",
        merchant: merchant, type: if(amt > 0, do: "credit", else: "debit"),
        account_id: account.id, category_id: cat.id,
        inserted_at: now, updated_at: now
      })
    end

    Repo.insert!(%Budget{
      month: "2026-03", amount: 600_00, category_id: food.id,
      inserted_at: now, updated_at: now
    })

    %{account: account, food: food, groceries: groceries, transport: transport}
  end

  describe "validate/2" do
    test "accepts valid datasets" do
      for ds <- ~w(transactions categories accounts budgets) do
        intent = %QueryIntent{dataset: ds, measures: ["count(*)"]}
        assert :ok = Resolver.validate(intent, %{})
      end
    end

    test "rejects unknown datasets" do
      intent = %QueryIntent{dataset: "secrets", measures: ["count(*)"]}
      assert {:error, {:unknown_dataset, "secrets"}} = Resolver.validate(intent, %{})
    end
  end

  describe "resolve/2 — transactions" do
    test "groups by category" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["count(*)"],
        dimensions: ["category"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      labels = Enum.map(data, & &1.label)
      assert "Groceries" in labels
      assert "Transportation" in labels
    end

    test "groups by merchant with sum(amount)" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["sum(amount)"],
        dimensions: ["merchant"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      wf = Enum.find(data, &(&1.label == "Whole Foods"))
      assert wf.value == -110_00
    end

    test "groups by type" do
      intent = %QueryIntent{
        dataset: "transactions",
        measures: ["count(*)"],
        dimensions: ["type"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      types = Enum.map(data, & &1.label)
      assert "debit" in types
      assert "credit" in types
    end
  end

  describe "resolve/2 — accounts" do
    test "groups by type" do
      intent = %QueryIntent{
        dataset: "accounts",
        measures: ["sum(balance)"],
        dimensions: ["type"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      checking = Enum.find(data, &(&1.label == "checking"))
      assert checking.value == 1000_00
    end
  end

  describe "resolve/2 — budgets" do
    test "groups by category" do
      intent = %QueryIntent{
        dataset: "budgets",
        measures: ["sum(amount)"],
        dimensions: ["category"]
      }

      {:ok, data} = Resolver.resolve(intent, %{})
      food_budget = Enum.find(data, &(&1.label == "Food"))
      assert food_budget.value == 600_00
    end
  end

  describe "describe/0" do
    test "returns non-empty description" do
      desc = Resolver.describe()
      assert is_binary(desc)
      assert String.contains?(desc, "transactions")
      assert String.contains?(desc, "categories")
      assert String.contains?(desc, "accounts")
      assert String.contains?(desc, "budgets")
    end
  end
end
```

- [ ] **Step 2: Run the tests**

```bash
cd /Users/mhyrr/work/resonance/example/finance_demo && mix test test/finance_demo/finance/resolver_test.exs
```

Expected: All tests pass

- [ ] **Step 3: Run full test suite**

```bash
cd /Users/mhyrr/work/resonance && mix test.all
```

Expected: Library tests + CRM demo tests + finance demo tests all pass

- [ ] **Step 4: Commit**

```bash
git add example/finance_demo/test/finance_demo/finance/resolver_test.exs
git commit -m "Add resolver tests for finance demo"
```

---

## Verification Checklist

After all tasks:

- [ ] `mix test` — Library tests pass (52+ existing + 6 new component tests)
- [ ] `cd example/resonance_demo && mix test` — CRM demo tests pass
- [ ] `cd example/finance_demo && mix test` — Finance demo tests pass
- [ ] `mix build.all` — Everything compiles
- [ ] CRM demo still works unchanged (no component_map passed = defaults)
- [ ] Finance demo compiles and has ECharts components wired up
- [ ] Both example apps have READMEs
- [ ] `example/resonance_demo/README.md` documents domain, resolver, and ApexCharts
- [ ] `example/finance_demo/README.md` documents domain, resolver, ECharts, and the component_map swap
