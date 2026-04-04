# CRM Demo — Resonance Example App

A sales CRM dashboard powered by Resonance's semantic analysis layer. Ask questions about your pipeline in natural language and get interactive charts and tables.

## Why CRM?

CRM data is universally understood in business contexts — deals, contacts, companies, activities. It exercises Resonance's core strengths:

- **Entity-centric queries** — "Who are our largest accounts?"
- **Pipeline analysis** — "Show me deals by stage"
- **Time comparisons** — "Q1 vs Q2 deal performance"
- **Multi-dimensional breakdowns** — "Revenue by stage and quarter"

## Visualization: ApexCharts

This demo uses the library's default presenter (`Resonance.Presenters.Default`), which renders with [ApexCharts](https://apexcharts.com/). No `presenter` assign is passed to `Resonance.Live.Report` — it just works out of the box.

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
Checks that the requested dataset is in the allowed list (`companies`, `contacts`, `deals`, `activities`). This is the security boundary.

### `resolve/2`
Translates a `Resonance.QueryIntent` into Ecto queries. Pattern-matches on dataset + dimensions to select the right query shape:

- **Deals**: Grouping by `stage`, `quarter`, `owner`, or `stage + quarter` (multi-series). Measures: `count(*)`, `sum(value)`, `avg(value)`.
- **Companies**: Grouping by `industry`, `region`, `size`. Measures: `count(*)`, `sum(revenue)`, `avg(revenue)`.
- **Contacts**: Grouping by `stage`. Measures: `count(*)`.
- **Activities**: Grouping by `type` or `outcome`. Measures: `count(*)`.

Filters are applied via pattern-matched `Enum.reduce`. Unsupported filters are logged and dropped.

## Running

```bash
cd example/resonance_demo
mix setup
mix phx.server    # localhost:4000
```

Requires `ANTHROPIC_API_KEY` environment variable.

## Interactive Features

- **Prompt input** — Type any question about CRM data
- **Suggestion buttons** — Click pre-built queries to explore
- **Simulate New Deals** — Generates random deals and refreshes the current report without re-calling the LLM
