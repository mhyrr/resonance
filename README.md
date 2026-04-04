# Resonance

**Generative analysis surfaces for Phoenix LiveView.**

An Elixir library that lets users ask questions about application data and receive composed, app-native UI — reports, dashboards, and contextual insights — built from semantic primitives and streamed in real-time via LiveView.

## Why "Resonance"?

In Thomistic philosophy, *resonantia* describes what happens when a living knower's inquiry activates structured knowledge, producing insight that neither party contained independently.

That's what this library does. The LLM holds compressed patterns about data visualization and user intent. Your app holds the actual data and domain logic. Neither can produce the right dashboard alone. But when the user's question passes through the LLM and activates the right primitives against real data, something emerges that wasn't in either system — a composed view that answers a question nobody pre-built a report for.

The LLM is the string. The user is the plectrum. The UI is the music.

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
LiveView streams a composed report
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
  def resolve(%Resonance.QueryIntent{dataset: "deals"} = intent, context) do
    data =
      MyApp.Deals
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

Drop the component into your LiveView:

```elixir
<.live_component
  module={Resonance.Live.Report}
  id="explore"
  resolver={MyApp.DataResolver}
  current_user={@current_user}
/>
```

Or call the API directly:

```elixir
{:ok, components} = Resonance.generate("Show me deal pipeline by stage", %{
  resolver: MyApp.DataResolver,
  current_user: user
})
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
│     Orchestration + streaming               │
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

The resolver's job: validate the intent, enforce permissions, translate to queries, return normalized data. This is where correctness and security live.

## LLM Providers

Built-in support for Anthropic and OpenAI. Add custom providers by implementing the `Resonance.LLM.Provider` behaviour:

```elixir
defmodule MyApp.CustomProvider do
  @behaviour Resonance.LLM.Provider

  @impl true
  def chat(prompt, tools, opts) do
    # Format tools, make the API call, return normalized tool calls
    {:ok, [%Resonance.LLM.ToolCall{name: "...", arguments: %{}}]}
  end
end
```

```elixir
config :resonance, provider: MyApp.CustomProvider
```

## Example App

The `example/resonance_demo/` directory contains a full CRM demo app with:

- Companies, contacts, deals, and activities
- A resolver that translates QueryIntents to Ecto queries
- An explore page for prompt-driven report generation

```bash
cd example/resonance_demo
mix setup
ANTHROPIC_API_KEY=your_key mix phx.server
# Visit http://localhost:4000/explore
```

## Development

```bash
mix deps.get          # Install dependencies
mix test              # Run library tests
mix test.all          # Run library + demo app tests
mix build.all         # Compile everything
mix format            # Format code
```

## License

MIT
