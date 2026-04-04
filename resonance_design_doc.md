# Resonance — Design Document

**Generative analysis surfaces for Phoenix LiveView.**

An Elixir library that lets users ask questions about application data and receive composed, app-native UI — reports, dashboards, and contextual insights — built from semantic primitives and streamed in real-time via LiveView.

---

## The Idea in 30 Seconds

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

---

## Origin

This design was originally created for Matreas (a donor management platform for Catholic schools) in December 2025. The architecture adapts Vercel's AI SDK "Generative UI" pattern — where React Server Components are streamed based on LLM tool calls — for Phoenix LiveView's server-side rendering model.

The name comes from a Thomistic concept: *resonantia* — the activation of structured knowledge by a living knower's inquiry, producing something neither party contained independently. The LLM's weights are sedimented form. The user's question is the inquiry. The composed UI is what emerges in the space between.

---

## What This Enables

Most apps ship fixed dashboards that are 80% correct for most users.

Resonance enables the missing 20%: users can generate the view they need, inside the app, against real data, without the product team pre-building it.

This shows up as three product surfaces:

### 1. Explore / Ask Surface (Primary)
A user asks: "Who are our top accounts that haven't had activity this quarter?"

The app generates a report surface: metric grid (counts, totals), ranked table (top lapsed accounts), narrative summary.

This is not chat. It is a generated report page.

### 2. Contextual Insight Panels
Inside an existing page (company profile, deal view), a user asks: "Compare this company to similar accounts."

Resonance generates a context-aware analysis panel — right rail, bottom drawer, or "Insights" tab.

### 3. Saveable Generated Reports (v0.2)
A generated report can be saved, rerun, shared, and exported. Ephemeral prompts become durable product artifacts.

---

## Why LiveView Is a Natural Fit

LiveView isn't just "compatible" — it's structurally aligned:

- **Server-owned state** → model output and UI live in one process
- **WebSocket streaming** → progressive report composition via DOM diffs
- **Async primitives** (`assign_async`, `stream`) → natural partial rendering
- **OTP supervision** → failure isolation per component
- **No hydration boundary** → no mismatch between generated intent and UI state
- **Minimal JS** → chart hooks are the only JavaScript needed

This avoids the complexity seen in React-based generative UI systems (RSC streaming, hydration mismatches, client-side state synchronization).

---

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

The LLM should operate on **semantic primitives**, not UI components.

| Bad | Better |
|-----|--------|
| "render a bar chart" | "compare values across time periods" |
| "show a table" | "rank entities by metric" |
| "make a pie chart" | "show distribution across groups" |

This matters because it:
- Decouples intent from presentation
- Allows multiple render strategies per primitive
- Prevents UI brittleness
- Makes outputs more stable across contexts

### The Flow

```
User prompt
  → Resonance.generate(prompt, context)
  → Resonance calls configured LLM with tool schemas from Registry
  → LLM returns tool calls selecting semantic primitives
  → Each primitive validates params → builds QueryIntent → calls Resolver
  → Resolver (app-provided) returns data
  → Primitive picks UI component via present/2 based on data shape
  → Composer collects Renderables, streams to LiveView
  → Layout module orders components (metrics → charts → tables → prose)
  → LiveView renders components progressively
```

---

## Semantic Primitives

Five intent-first operations. Each maps to one or more presentation components depending on data shape.

| Primitive | Purpose | Maps To |
|-----------|---------|---------|
| `compare_over_time` | Trends across time periods | line_chart, bar_chart |
| `rank_entities` | Order entities by a metric | bar_chart (≤10), data_table (>10) |
| `show_distribution` | Proportions/composition | pie_chart (≤8), bar_chart (>8) |
| `summarize_findings` | Narrative analysis | prose_section |
| `segment_population` | Group breakdown | metric_grid (≤6), data_table (>6) |

### Primitive Behaviour

```elixir
defmodule Resonance.Primitive do
  @callback intent_schema() :: map()
  @callback resolve(params :: map(), context :: map()) :: {:ok, map()} | {:error, term()}
  @callback present(data :: map(), context :: map()) :: Resonance.Renderable.t()
end
```

The key shift from the original design: primitives are no longer tied directly to UI components. `present/2` introduces an explicit presentation mapping step that inspects data shape and picks the right component.

---

## Presentation Components

Seven UI building blocks that primitives map to:

| Component | Type | JS Required |
|-----------|------|-------------|
| `LineChart` | Time-series / trends | ApexCharts hook |
| `BarChart` | Categorical comparison | ApexCharts hook |
| `PieChart` | Proportions | ApexCharts hook |
| `DataTable` | Record-level data | None (server-rendered) |
| `MetricCard` | Single KPI with trend | None |
| `MetricGrid` | Multiple KPIs | None |
| `ProseSection` | Narrative text | None |

These are Phoenix function components. Each takes a `props` map and renders HEEx.

---

## The Resolver Contract

The resolver is the most important piece — where correctness, security, and product trust live.

### Structured Query Intent

The LLM produces a bounded query AST, not a string:

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

### Resolver Behaviour

```elixir
defmodule Resonance.Resolver do
  @callback resolve(intent :: Resonance.QueryIntent.t(), context :: map()) ::
              {:ok, list(map())} | {:error, term()}
  @callback validate(intent :: Resonance.QueryIntent.t(), context :: map()) ::
              :ok | {:error, term()}
  @optional_callbacks [validate: 2]
end
```

The resolver's job:
1. **Validate** — is this dataset allowed? Are these measures valid?
2. **Enforce permissions** — does this user have access?
3. **Translate** — turn the QueryIntent into Ecto queries
4. **Return normalized data** — list of maps with `:label` and `:value` keys

---

## LLM Integration

Resonance owns the LLM call. The developer configures provider and credentials once:

```elixir
# config/runtime.exs
config :resonance,
  provider: :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY"),
  model: "claude-sonnet-4-5"
```

Built-in providers for Anthropic and OpenAI. Custom providers implement `Resonance.LLM.Provider`:

```elixir
@callback chat(prompt :: String.t(), tools :: [map()], opts :: keyword()) ::
  {:ok, [Resonance.LLM.ToolCall.t()]} | {:error, term()}
```

The developer's code is just:
```elixir
{:ok, components} = Resonance.generate(prompt, %{
  resolver: MyApp.DataResolver,
  current_user: user
})
```

---

## Composition Engine

The Composer orchestrates the flow from tool calls to renderable components:

1. Receives normalized tool calls from the LLM
2. Looks up each primitive in the Registry
3. Resolves data in parallel via `Task.async_stream`
4. Calls `present/2` on each primitive to get Renderables
5. Layout module orders the results

Streaming variant sends `{:resonance, {:component_ready, renderable}}` messages as each primitive resolves, enabling progressive rendering.

---

## Layout Engine

Separates "what to show" (LLM) from "how to arrange it" (system).

Default ordering:
1. Metric cards and grids (KPIs first)
2. Charts (trends and distributions)
3. Tables (detail data)
4. Prose (narrative summary)

This increases consistency — the user sees KPIs at a glance, then supporting visualizations, then detail.

---

## What Ships in v0.1

- Semantic primitive system (5 primitives)
- Structured QueryIntent with validation
- Resolver behaviour with optional validation callback
- Composer with parallel resolution + streaming
- Layout ordering module
- 7 presentation components with HEEx templates
- JS hooks for charts (ApexCharts)
- LLM client with Anthropic and OpenAI providers
- Drop-in `Resonance.Live.Report` LiveComponent
- CRM example app (contacts, companies, deals, activities)
- Top-level `mix test.all` and `mix build.all` aliases

## What Ships Later

- Saved report system (persist, rerun, share, export)
- Query AST validation helpers for common Ecto patterns
- Layout engine with configurable rules
- Brand/theme injection (org colors into all components)
- Primitive composition (meta-primitives that arrange others)
- Custom primitive generator (`mix resonance.gen.primitive`)
- Image generation primitive (Gemini, DALL-E)
- Oban integration for background report generation
- PDF export
- LiveView component playground

---

## Project Structure

```
resonance/
├── lib/
│   └── resonance/
│       ├── resonance.ex            # Top-level API (generate/2, generate_stream/3)
│       ├── primitive.ex            # Semantic primitive behaviour
│       ├── resolver.ex             # Resolver behaviour
│       ├── query_intent.ex         # Structured query type + validation
│       ├── renderable.ex           # Renderable struct
│       ├── composer.ex             # Orchestration + streaming
│       ├── registry.ex             # Primitive registration
│       ├── layout.ex               # Component ordering
│       ├── llm/
│       │   ├── llm.ex             # Internal LLM client
│       │   ├── provider.ex        # Provider behaviour
│       │   ├── tool_call.ex       # Normalized tool call struct
│       │   └── providers/
│       │       ├── anthropic.ex
│       │       └── openai.ex
│       ├── primitives/
│       │   ├── compare_over_time.ex
│       │   ├── rank_entities.ex
│       │   ├── show_distribution.ex
│       │   ├── summarize_findings.ex
│       │   └── segment_population.ex
│       ├── components/
│       │   ├── line_chart.ex
│       │   ├── bar_chart.ex
│       │   ├── data_table.ex
│       │   ├── pie_chart.ex
│       │   ├── metric_card.ex
│       │   ├── metric_grid.ex
│       │   └── prose_section.ex
│       └── live/
│           └── report.ex           # Drop-in LiveComponent
├── assets/js/hooks/charts.js       # ApexCharts hooks
├── example/resonance_demo/         # CRM demo app
├── test/
├── mix.exs
├── README.md
└── LICENSE
```

---

## Prior Art

| Project | Language | What It Does | Gap |
|---------|----------|-------------|-----|
| Vercel AI SDK `streamUI` | TypeScript/React | Generative UI via RSC streaming | React-only, no Elixir |
| LangChain | Python | LLM orchestration + tool calling | No UI layer |
| instructor_ex | Elixir | Structured LLM outputs | Data extraction only, no UI |
| Jido | Elixir | Agent framework | Agent orchestration, no generative UI |

**Nobody in the Elixir ecosystem is doing generative UI.** Resonance is the first.

---

## Philosophy

Resonance is not about generating UI.

It is about letting users ask for views that were never built.

The model selects intent.
The application provides truth.
The system composes the result.

What emerges is not code — but a view.
