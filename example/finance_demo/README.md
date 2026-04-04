# Finance Demo — Resonance Example App

A personal finance dashboard powered by Resonance's semantic analysis layer. Ask questions about your spending in natural language and get interactive charts rendered by Apache ECharts.

## Why Personal Finance?

This demo exists to prove that Resonance's semantic layer is fully decoupled from visualization. While the CRM demo uses ApexCharts via the default presenter, this app uses a **custom ECharts presenter** — same primitives, same data contracts, completely different rendering.

| Dimension | CRM Demo | Finance Demo |
|-----------|----------|--------------|
| **Data shape** | Entity-centric (companies, deals) | Category-hierarchical (nested spending categories) |
| **User mindset** | "Who are my best accounts?" (open exploration) | "Am I on budget?" (goal-oriented) |
| **Time granularity** | Quarterly business reviews | Daily/weekly transactions |
| **Key metric** | Revenue (inflows) | Spending (outflows) |
| **Chart library** | ApexCharts (default presenter) | Apache ECharts (custom presenter) |
| **Standout viz** | Donut charts, multi-series lines | Treemaps for hierarchical categories |

## Visualization: Apache ECharts

The app implements `FinanceDemo.Presenters.ECharts` and passes it to `Resonance.Live.Report`:

```elixir
<.live_component
  module={Resonance.Live.Report}
  id="explore-report"
  resolver={FinanceDemo.Finance.Resolver}
  presenter={FinanceDemo.Presenters.ECharts}
/>
```

The presenter maps Result kinds to ECharts components:

| Primitive | CRM renders as | Finance renders as |
|-----------|---------------|-------------------|
| `show_distribution` | Donut chart (ApexCharts) | **Treemap** (ECharts) |
| `compare_over_time` | Line/bar (ApexCharts) | Line with area fill (ECharts) |
| `rank_entities` | Horizontal bar (ApexCharts) | Horizontal bar (ECharts) |
| `segment_population` | Metric grid | Metric grid (library default) |
| `summarize_findings` | Prose section | Prose section (library default) |

For kinds the ECharts presenter doesn't override (`:segmentation`, `:summary`), it delegates to `Resonance.Presenters.Default`.

### Treemap: The Standout

When you ask "where did my money go?", the `show_distribution` primitive returns spending by category. In the CRM demo, that's a donut chart. Here, it's a **treemap** — nested rectangles sized by spend amount. Parent categories contain their subcategories. It makes hierarchical spending immediately legible in a way a donut never could.

The treemap component accepts the same `[%{label, value}]` data format, plus an optional `parent` field for hierarchy. The JS hook builds the tree structure client-side.

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
- Belongs to category (top-level), one entry per category per month

## The Resolver

`FinanceDemo.Finance.Resolver` implements `Resonance.Resolver`:

### `describe/0`
Documents four datasets with queryable fields, measures, and dimensions. Notes the cents convention and debit/credit semantics. This goes into the LLM system prompt.

### `validate/2`
Whitelists `transactions`, `categories`, `accounts`, `budgets`.

### `resolve/2`
Translates QueryIntents into Ecto queries:

- **Transactions by category**: Joins categories table, groups by name. `sum(amount)`, `count(*)`.
- **Transactions by month**: SQLite `strftime('%Y-%m', date)` for grouping. Returns `period` for time-series.
- **Transactions by merchant**: Groups by merchant for "top merchants" queries.
- **Transactions by category + month**: Multi-series — one line per category over time.
- **Accounts by type**: Groups checking/savings/credit with balance sums.
- **Budgets by category or month**: For budget tracking.

Filters support `type` (debit/credit) and `merchant` on transactions; `month` on budgets.

## Running

```bash
cd example/finance_demo
mix setup
mix phx.server    # localhost:4001
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
