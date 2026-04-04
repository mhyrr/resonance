# Resonance

**Generative analysis surfaces for Phoenix LiveView.**

An Elixir library that lets users ask questions about application data and receive composed, app-native UI (reports, dashboards, contextual insights) built from semantic primitives and streamed in real-time via LiveView.

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

## Beyond the Fixed Dashboard

Software teams have always built UI the same way: study the users, guess what they need, build it in a lab, ship it, and hope. The result is dashboards and reports that are roughly 80% correct for roughly 80% of people. The other 20% file tickets, build spreadsheets, or learn to live without the view they actually needed.

That model is ending. When a language model can interpret a user's intent and map it to structured operations over real data, the economics change. Instead of a product team anticipating every possible view and pre-building it, the user states what they want and the system composes it on demand. The view that answers "which donors lapsed this quarter and why" doesn't need to exist as a page in your app. It can be generated from the question itself, against real data, in real time.

Nobody wants to have a conversation with their CRM. The output is a composed analytical surface (charts, tables, metrics, narrative) that looks and behaves like a page your team built. It just happens to be one nobody planned for.

### Why Not Go Straight to Widgets

Vercel's AI SDK takes the direct approach: the LLM picks React components via tool calls. Ask about weather, get a `<WeatherCard>`. Ask about stocks, get a `<StockChart>`. The model selects widgets.

This works for demos. It breaks down for data analysis, because it couples the model's understanding to your component library. The LLM needs to know the difference between a bar chart and a line chart, and when to use each. Change your charting library? Update your tool definitions. Add a mobile layout? Teach the model new components. The presentation layer becomes part of the prompt.

Resonance inserts a semantic layer between the LLM and the UI. The model doesn't pick a bar chart. It picks `rank_entities`, an analytical operation meaning "order these things by a metric." The library's `present/2` step inspects the resolved data and chooses the right component: a horizontal bar chart for 4 items, a sortable table for 40. Same intent, different data, different presentation, and the model never had to care.

You can swap chart libraries without touching the LLM integration. You can add device-specific rendering without rewriting tool schemas. You can change how "show distribution" looks without changing what it means. The model operates on stable analytical concepts; the UI is free to evolve independently.

### Why Elixir

Generative UI has a pipeline problem. A user's question becomes an LLM call, which becomes tool selections, which become data queries, which become resolved components, which become rendered HTML. In most architectures, this pipeline crosses multiple process boundaries: API calls, client hydration, state synchronization.

LiveView eliminates most of that. The LLM's tool call output, the data resolution, the component rendering, and the DOM update all happen in a single server process. There is no serialization boundary between "the model said to rank entities" and the HTML that renders the ranking. Components stream to the browser as WebSocket DOM diffs. Each primitive resolves independently and appears the moment it's ready. No client-side state management. No hydration step. No JavaScript framework rendering pipeline.

OTP adds the structural pieces that a generative system needs. Each primitive resolves inside a supervised task; if one fails, the others still render. The registry is a runtime-configurable process. The composition engine uses `Task.async_stream` with backpressure and timeouts. These are properties of the runtime, not features bolted onto a web framework.

In practice, Resonance's LiveView integration is a single LiveComponent with no required parent wiring. Drop it into any page. The component handles the LLM call, streams resolved primitives progressively, and pushes data updates to charts via events, all within LiveView's existing programming model. The consuming app writes a resolver and a `live_component` tag.

### Where This Goes

v0.1 is read-only: generated views of existing data. But the architecture is designed for what comes after.

The structured `QueryIntent` is already a validated, inspectable intermediate representation. It is a bounded AST with explicit datasets, measures, dimensions, and filters, not a raw string. The resolver is already a trust boundary with permission enforcement. The primitive system is already extensible at runtime. All of these extend naturally to write operations, interactive filters, saved views, and eventually full user-driven application surfaces.

The era of the product team as sole author of the UI is winding down. The replacement is composable, data-grounded, app-native surfaces that emerge from the intersection of user intent, application data, and structured analytical primitives. Resonance is the infrastructure for building that.

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

Each primitive picks its presentation component based on data shape. The same primitive renders differently depending on the data.

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

Components stream progressively as each primitive resolves. The LLM call is blocking (tool calls must be known before resolution), but resolution is parallel. Each primitive resolves independently and appears in the UI the instant it's ready. Layout re-orders on each arrival: metrics first, then charts, then tables, then prose.

### Data Refresh

The Report component stores tool calls from the LLM response. When underlying data changes, a `refresh` replays the same tool calls against fresh data: no LLM re-call, deterministic structure, sub-second update. Charts animate smoothly from old values to new via `push_event`.

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
# Batch: resolve all primitives, return when complete
{:ok, components} = Resonance.generate(prompt, %{
  resolver: MyApp.DataResolver,
  current_user: user
})

# Streaming: receive components as they resolve
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

The demo includes a "Simulate New Deals" button that inserts random data and refreshes the active report in-place. Good for seeing streaming and data refresh in action.

## Development

```bash
mix deps.get          # Install dependencies
mix test              # Run library tests (56 tests)
mix test.all          # Run library + demo app tests
mix build.all         # Compile everything
mix format            # Format code
```

## Why "Resonance"?

From the Thomistic concept *resonantia*, which describes what happens when a living knower's inquiry activates structured knowledge, producing insight neither party contained independently.

The LLM holds compressed patterns about data analysis and user intent. Your app holds the actual data and domain logic. Neither produces the right view alone. When the user's question passes through the LLM and activates the right primitives against real data, something emerges that was not in either system: a composed surface that answers a question nobody pre-built a report for.

## License

MIT
