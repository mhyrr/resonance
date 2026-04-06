# Resonance v2: Interactive Reports — Design

## The thesis

Resonance v1 is a five-layer pipeline for generating **read-only** reports from
natural language: the LLM picks semantic primitives, a developer-provided
resolver fetches data, a presenter maps Results to components, and a LiveView
renders them. The boundaries are clean because data flows in one direction.

v2 makes those reports **interactive** without breaking the layering. The
insight that makes this tractable:

> Building interactive UI doesn't need a smarter LLM. It needs the developer to
> bring their own components — and Phoenix already has the right primitive for
> that. It's called `LiveComponent`.

The LLM stays in semantics-land. It picks primitives, exactly as it does today.
The developer brings a small library of LiveComponents that know how to render
Results *and* how to react to user gestures. The shared language between the
LLM's intent and the user's gestures is the same `QueryIntent` struct that
already exists.

That's the whole idea. Everything below is the smallest set of additions that
makes it real.

## What stays exactly the same

- `Resonance.Primitive` behaviour and all five built-in primitives.
- `Resonance.Resolver` behaviour, `describe/0`, `validate/2`, `resolve/2`.
- `Resonance.QueryIntent` — still the contract between LLM output and data fetching.
- `Resonance.Result` — still the normalized truth a primitive produces.
- `Resonance.Composer` — still parallelizes resolution and streams Renderables.
- `Resonance.Presenter` — still maps Results to components.
- The LLM tool-use flow, the system prompt, the registry.

If you only ever write read-only reports, nothing changes. v2 is purely additive.

## What's new (four things)

### 1. `Resonance.Widget` — a behaviour on top of LiveComponent

A widget is a Phoenix LiveComponent that implements the `Resonance.Widget`
behaviour. The behaviour is symmetric to `Resonance.Component` (which already
exists for the read-only path):

```elixir
defmodule MyApp.Widgets.FilterableLeaderboard do
  use Resonance.Widget   # gives you LiveComponent + the behaviour

  @impl true
  def accepts_results, do: [:ranked_list]

  @impl true
  def capabilities, do: [:refine]

  @impl true
  def example_renderable, do: # synthetic Renderable for the playground

  @impl Phoenix.LiveComponent
  def update(%{renderable: r} = assigns, socket), do: # standard LiveComponent
  def handle_event("filter", %{...}, socket), do: # standard LiveComponent
  def render(assigns), do: ~H"..."
end
```

The contract:

- **Required:** `accepts_results/0 :: [Result.kind()]` — which Result kinds this
  widget can render. Used by the Presenter dispatch table and the playground.
- **Optional:** `capabilities/0 :: [:refine | :mutate | :drilldown]` — declares
  what user gestures the widget supports. Default `[]`. (In v2 this is
  documentation; in v2.1 it can feed into the LLM's system prompt to bias toward
  explorable reports.)
- **Optional:** `example_renderable/0 :: Renderable.t()` — a synthetic
  Renderable used by the playground to render the widget without real data.
- **Required by LiveComponent (already):** `update/2` accepts a `:renderable`
  assign carrying the full `%Renderable{}` (which already includes the `Result`,
  the `QueryIntent`, and a stable id). The widget reads from it and may call
  `Resonance.refine/2` to produce a new one.

`use Resonance.Widget` is one line that pulls in `Phoenix.LiveComponent` and
declares `@behaviour Resonance.Widget`. Developers write widgets the way they
write any other LiveComponent — call their own contexts from `handle_event/3`,
manage local state in socket assigns. Resonance teaches one extra thing: "tell
us what Result kinds you accept."

The Presenter, instead of always returning a function-component module, may now
return a Widget module. The `Renderable` gains one field —
`render_via: :function | :live` — which the Presenter sets when it builds the
Renderable. That's the only struct change.

**Why a behaviour, not just a convention:** an earlier draft of this doc
proposed no behaviour, on YAGNI grounds — "the Presenter dispatch table is the
catalog." That was wrong, for three reasons:

1. The library's identity is contracts. Primitive, Resolver, Presenter, Result,
   QueryIntent, and now Component are all behaviours. A widget that's "a
   LiveComponent with a magic assign name" is the only anomaly.
2. The playground needs widget enumeration and per-widget metadata. Without a
   behaviour, the playground reinvents one internally.
3. Declared capabilities are exactly the structured developer-side context the
   LLM needs to bias toward explorability. Building it in v2 is nearly free and
   unblocks v2.1.

### 2. `Live.Report` renders both kinds and routes updates to the right place

The render loop in `Live.Report` learns to branch on `render_via`. In the
template, not in a private function:

```heex
<%= for c <- Layout.order(@components) do %>
  <%= case c.render_via do %>
    <% :function -> %><%= c.component.render(%{renderable: c}) %>
    <% :live -> %><.live_component module={c.component} id={c.id} renderable={c} />
  <% end %>
<% end %>
```

Updates follow one rule: **a Renderable update is delivered to its render
target.** For function components, that means updating the assigns list and
re-rendering (already how it works). For LiveComponents, that means
`Phoenix.LiveView.send_update(module, id: id, renderable: new_renderable)`. The
existing chart-hook `push_event` path stays for function-component charts as a
render-time optimization; LiveComponents own their own DOM and don't need it.

This is the only refactor to existing code. It's localized to `Live.Report`.

### 3. `Resonance.refine/2` — the one new public API

A widget that wants to re-resolve its primitive with a tweaked QueryIntent calls:

```elixir
@spec refine(Renderable.t(), (QueryIntent.t() -> QueryIntent.t())) ::
        {:ok, Renderable.t()} | {:error, term}
```

It takes the current Renderable and a function that mutates the intent. It runs
the same primitive's resolver again, runs the same Presenter, and returns a new
Renderable. The widget then `assign`s it locally, or — if it wants the rest of
the report to know — sends it back to `Live.Report`.

Why a function instead of a new intent value: it forces the widget to start from
the existing intent (so the LLM's original constraints are preserved), and it
makes refinement composable.

**Authorization for v2:** `refine/2` calls the resolver's existing `validate/2`.
That's the same trust boundary the read-only path uses. If a developer needs
stricter rules for user-driven refinements than for LLM-generated ones, they can
branch inside `validate/2` on a `from: :user | :llm` flag in the context. We
don't add a new callback in v2. If two real apps need it, we add one in v2.1.

### 4. Cross-component updates use what Phoenix already gives you

If a widget wants to update a sibling Renderable in the same report, it uses
`Phoenix.LiveView.send_update/2` directly. The Renderable's `id` is stable and
known. There is no Resonance-specific pub/sub.

This handles the "filter widget refreshes the chart next to it" case without any
new infrastructure. The widget that owns the filter knows the id of the widget
that owns the chart (it's in the report; it can be passed as an assign or looked
up from `Live.Report`'s component list). It calls `send_update`, the receiving
widget's `update/2` runs `refine/2` on its own renderable, done.

## What v2 explicitly does *not* include

Naming these because a previous round of design had us inventing solutions for
them, and v2 is better off without those solutions until a real app forces the
issue.

- **No `Resonance.Scope` struct.** Widgets that need context get it the way
  every LiveComponent gets it: as assigns from the parent. `Live.Report` already
  threads `:resolver`, `:current_user`, etc.; widgets receive what they need
  through normal assigns.
- **No `Resonance.invoke/3` for cross-primitive calls.** If a widget needs a
  different primitive, v2 says "regenerate the report" (which already exists).
  Cross-primitive drilldown without regeneration is a later problem.
- **No `Resonance.commit/4` and no mutation invalidation.** v2 widgets *can*
  mutate — they just call the developer's app contexts from `handle_event/3`
  like any LiveComponent. What v2 doesn't do is automatically invalidate other
  Renderables in the report. If a widget creates a deal and the chart next to
  it needs to refresh, the widget calls `send_update` on the chart explicitly.
  Manual, but honest, and removes the need for any dataset-dependency tracking
  in v2.
- **No LLM capability tags in the system prompt.** The LLM stays fully unaware
  of interactivity in v2. If a Presenter has no interactive widget for a Result
  kind, it falls back to the read-only one. No silent degradation, because
  there's no expectation to degrade *from*. (This becomes a problem when
  developers want the LLM to bias toward "explorable" reports. Later.)
- **No two-tier `validate_intent` / `authorize_refinement`.** One validate call.
  One trust boundary.

Each of these omissions has a real use case behind it. None of them are needed
for the first version of an app to ship an interactive report. We add them when
an actual app fails without them, not before.

## The five layers, restated for v2

| Layer | Read-only (v1) | Interactive (v2) |
|---|---|---|
| **1. Primitive** | LLM picks one; produces a Result. | Identical. |
| **2. Resolver** | Validates intent, fetches data. | Identical. Now also called by `refine/2` on user gestures, with the same `validate/2`. |
| **3. Presenter** | Maps Result kind to a function component. | May map to a LiveComponent instead. Sets `render_via` on the Renderable. |
| **4. Composer** | Parallel resolve + stream Renderables. | Identical. `refine/2` reuses `resolve_one`. |
| **5. LiveView surface** | Renders function components, streams updates via `push_event` for charts. | Renders both kinds. Streams updates to LiveComponents via `send_update`. Function-component path unchanged. |

The cleanliness of the original five-layer model is preserved. v2 adds **one
behaviour** (`Resonance.Widget`), **one struct field** (`render_via`), **one
function** (`refine/2`), and **one render-loop branch**. Everything else is
"developers write LiveComponents, like they always have."

## What you can build with this

Concretely, v2 supports:

1. **Filterable charts.** The widget owns filter state in assigns; on filter
   change it calls `refine/2` to re-resolve its own Renderable with extra
   `QueryIntent` filters; it re-renders.
2. **Drilldown within a primitive.** Same as above with different filters —
   clicking a bar adds a `where` clause.
3. **Forms that mutate app state.** The widget calls `MyApp.Deals.create_deal/2`
   from `handle_event/3` directly. If it wants the rest of the report to react,
   it calls `send_update` on the siblings it knows about.
4. **Editable reports.** A "save this view" button reads
   `assigns.renderable.props.intent` and persists it. A "load view" widget
   hydrates a new Renderable from a stored intent.
5. **Mixed read-only and interactive widgets in the same report.** The Presenter
   chooses per-Result.

It does *not* support, in v2:

- Automatic invalidation of unrelated Renderables after a mutation.
- LLM-aware drilldown that switches primitives.
- A widget marketplace with portable capability metadata.
- User-driven authorization rules distinct from LLM-driven ones.

Those are real things. They're for a later version.

## The thing that makes this feel different from a dashboard

The entire interactive surface is built out of Phoenix primitives the developer
already knows, wired into a report whose structure was chosen by an LLM from a
developer-described semantic vocabulary. The LLM picked *what the report is
about*. The developer's widgets decide *what the user can do with it*. Both
sides converge on the same `QueryIntent`.

That's the paradigm. v2 is the smallest possible expression of it: one struct
field, one function, one render branch, and a paragraph of documentation that
says "your widget is a LiveComponent that takes a `:renderable` assign."

## v2 build order

1. Add `Resonance.Widget` behaviour. One required callback (`accepts_results/0`),
   two optional (`capabilities/0`, `example_renderable/0`). `use Resonance.Widget`
   pulls in `Phoenix.LiveComponent` and the behaviour.
2. Add `render_via` to `%Renderable{}`. Default `:function`. No behaviour change
   for existing code.
3. Refactor `Live.Report.render/1` to branch on `render_via` in the template.
   Verify the read-only test suite still passes.
4. Implement `Resonance.refine/2` as a thin wrapper over `Composer.resolve_one`.
5. Build the playground LiveView. Enumerates Widget-implementing modules,
   renders each against `example_renderable/0`, displays declared capabilities.
   Mounted at `/resonance/playground` in the CRM demo. This is the v2 demo
   surface.
6. Build one real interactive widget in `example/resonance_demo`: a filterable
   deals leaderboard. Use only `refine/2` and `send_update`. If something feels
   missing while building it, *that's* the v2 gap — fix it then, not now.
7. Document the convention: "a Resonance widget is a `use Resonance.Widget`
   LiveComponent. Implement `accepts_results/0`. Call `Resonance.refine/2` to
   re-resolve. Call your own contexts from `handle_event/3`."

The discipline for v2 is: nothing goes in the library that the example app
doesn't need. Every additional concept earns its place by failing without it.
