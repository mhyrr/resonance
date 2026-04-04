# Resonance

**Generative analysis surfaces for Phoenix LiveView.**

An Elixir library that lets users ask questions about application data and receive composed, app-native UI — reports, dashboards, and contextual insights — built from semantic primitives and streamed in real-time via LiveView.

## How It Works

```
User: "Show me deal pipeline by stage"
  ↓
LLM selects semantic primitives: [show_distribution, summarize_findings]
  ↓
Each primitive resolves data via your app's resolver
  ↓
System maps data to UI components (charts, tables, cards)
  ↓
LiveView streams components progressively as they resolve
```

The LLM does not generate UI. It selects semantic operations over your data. Resonance resolves those operations, maps them to components, and streams the result.

## Quick Start

Add to your `mix.exs`:

```elixir
def deps do
  [{:resonance, "~> 0.1"}]
end
```

Configure your LLM provider:

```elixir
# config/runtime.exs
config :resonance,
  provider: :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-sonnet-4-5"
```

Implement a resolver for your data:

```elixir
defmodule MyApp.DataResolver do
  @behaviour Resonance.Resolver

  @impl true
  def describe do
    """
    Datasets:
    - "deals" — measures: count(*), sum(value), avg(value)
      dimensions: stage, quarter, owner
    """
  end

  @impl true
  def resolve(%Resonance.QueryIntent{dataset: "deals"} = intent, context) do
    data =
      MyApp.Deals
      |> scope_to_user(context.current_user)
      |> apply_filters(intent.filters)
      |> group_by_dimensions(intent.dimensions)
      |> apply_measures(intent.measures)
      |> Repo.all()

    {:ok, data}
  end

  @impl true
  def validate(%Resonance.QueryIntent{dataset: dataset}, _context) do
    if dataset in ~w(deals contacts companies),
      do: :ok,
      else: {:error, :unknown_dataset}
  end
end
```

Drop the component into any LiveView:

```elixir
<.live_component
  module={Resonance.Live.Report}
  id="explore"
  resolver={MyApp.DataResolver}
  current_user={@current_user}
/>
```

## Architecture

### Five Layers

```
┌─────────────────────────────────────────────┐
│  1. SEMANTIC PRIMITIVES                     │
│     What the LLM can ask for                │
├─────────────────────────────────────────────┤
│  2. INTENT → DATA (RESOLVER)                │
│     App-specific data resolution            │
├─────────────────────────────────────────────┤
│  3. PRESENTATION MAPPING                    │
│     Semantic → UI components                │
├─────────────────────────────────────────────┤
│  4. COMPOSITION ENGINE                      │
│     Parallel resolution + streaming         │
├─────────────────────────────────────────────┤
│  5. PRODUCT SURFACE (LiveView)              │
│     Where users interact                    │
└─────────────────────────────────────────────┘
```

### The Core Insight

The LLM operates on **semantic primitives**, not UI components.

| Bad | Better |
|-----|--------|
| "render a bar chart" | "compare values across categories" |
| "show a table" | "rank entities by metric" |
| "make a pie chart" | "show distribution across groups" |

This decouples intent from presentation, allows multiple render strategies, and prevents UI brittleness.

### Semantic Primitives

| Primitive | Purpose | Maps To |
|-----------|---------|---------|
| `compare_over_time` | Trends across time periods | line_chart, bar_chart |
| `rank_entities` | Order by metric | bar_chart, data_table |
| `show_distribution` | Proportions/composition | pie_chart, bar_chart |
| `summarize_findings` | Narrative analysis | prose_section |
| `segment_population` | Group breakdown | metric_grid, data_table |

Each primitive picks its presentation component based on data shape — the same primitive renders differently depending on the data.

### The Resolver Contract

Your resolver receives a structured `QueryIntent`, not strings:

```elixir
%Resonance.QueryIntent{
  dataset: "deals",
  measures: ["sum(value)"],
  dimensions: ["stage", "quarter"],
  filters: [%{field: "quarter", op: ">=", value: "2025-Q1"}],
  sort: %{field: "value", direction: :desc},
  limit: 10
}
```

The resolver validates the intent, enforces permissions, translates to Ecto queries, and returns normalized data. This is where correctness and security live.

The `describe/0` callback tells the LLM what datasets, measures, and dimensions are available. Without it, the LLM is guessing.

### Streaming

Components stream progressively as each primitive resolves. The LLM call is blocking (tool calls must be known before resolution), but resolution is parallel — each primitive resolves independently and appears in the UI the instant it's ready. Layout re-orders on each arrival: metrics first, then charts, then tables, then prose.

### Data Refresh

The Report component stores tool calls from the LLM response. When underlying data changes, a `refresh` replays the same tool calls against fresh data — no LLM re-call, deterministic structure, sub-second update. Charts animate smoothly from old values to new via `push_event`.

```elixir
# From any parent LiveView
send_update(Resonance.Live.Report, id: "explore", refresh: true)
```

## Presentation Components

| Component | Type | JS Required |
|-----------|------|-------------|
| `LineChart` | Time-series / trends | ApexCharts |
| `BarChart` | Categorical comparison | ApexCharts |
| `PieChart` | Proportions | ApexCharts |
| `DataTable` | Record-level data | None |
| `MetricCard` | Single KPI with trend | None |
| `MetricGrid` | Multiple KPIs | None |
| `ProseSection` | Narrative text | None |

Chart components use JS hooks with `phx-update="ignore"` to protect the ApexCharts DOM. Data updates are pushed via LiveView events for smooth in-place animation.

## LLM Providers

Built-in support for Anthropic and OpenAI. Custom providers implement `Resonance.LLM.Provider`:

```elixir
defmodule MyApp.CustomProvider do
  @behaviour Resonance.LLM.Provider

  @impl true
  def chat(prompt, tools, opts) do
    {:ok, [%Resonance.LLM.ToolCall{name: "...", arguments: %{}}]}
  end
end
```

```elixir
config :resonance, provider: MyApp.CustomProvider
```

## Programmatic API

The drop-in LiveComponent handles the full lifecycle, but you can also call the API directly:

```elixir
# Batch — resolve all primitives, return when complete
{:ok, components} = Resonance.generate(prompt, %{
  resolver: MyApp.DataResolver,
  current_user: user
})

# Streaming — receive components as they resolve
Resonance.generate_stream(prompt, context, self())
# Receive {:resonance, {:component_ready, renderable}} for each
# Receive {:resonance, :done} when complete
```

## Example App

The `example/resonance_demo/` directory contains a CRM demo with companies, contacts, deals, and activities:

```bash
cd example/resonance_demo
mix setup
ANTHROPIC_API_KEY=your_key mix phx.server
# Visit http://localhost:4000/explore
```

The demo includes a "Simulate New Deals" button that inserts random data and refreshes the active report in-place — useful for seeing streaming and data refresh in action.

## Development

```bash
mix deps.get          # Install dependencies
mix test              # Run library tests (56 tests)
mix test.all          # Run library + demo app tests
mix build.all         # Compile everything
mix format            # Format code
```

## Why "Resonance"?

From the Thomistic concept *resonantia* — what happens when a living knower's inquiry activates structured knowledge, producing insight neither party contained independently.

The LLM holds compressed patterns about data analysis and user intent. Your app holds the actual data and domain logic. Neither produces the right view alone. When the user's question passes through the LLM and activates the right primitives against real data, something emerges that wasn't in either system — a composed surface that answers a question nobody pre-built a report for.

## License

MIT
