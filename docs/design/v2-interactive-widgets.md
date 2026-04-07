# Resonance v2: Interactive Reports — Design

## The thesis

Resonance v1 is a five-layer pipeline for generating **read-only** reports from
natural language: the LLM picks semantic primitives, a developer-provided
resolver fetches data, a presenter maps Results to components, and a LiveView
renders them. The boundaries are clean because data flows in one direction.

v2 makes those reports **interactive** without making Resonance any bigger. The
principle that makes this tractable:

> Resonance is a **composer**. Phoenix is the **runtime**. Resonance composes
> the page from the user's question; once the widget is mounted, Resonance is
> gone from the runtime path. Widgets are real Phoenix LiveComponents — they
> call your app contexts, manage local state, handle mutations, and react to
> PubSub the way every other LiveComponent does. The library composes;
> Phoenix runs.

That's the whole idea. The LLM stays in semantics-land. It picks primitives,
exactly as it does today. The presenter — which is the developer's seam — maps
Results to components and unpacks the LLM-resolved query into clean widget
props. The widget gets initial state, then it's a normal LiveComponent. The
shared language between the LLM's intent and the user's gestures is the same
data the resolver already returns.

Everything below is the smallest set of additions that makes it real.

## What stays exactly the same

- `Resonance.Primitive` behaviour and all five built-in primitives.
- `Resonance.Resolver` behaviour, `describe/0`, `validate/2`, `resolve/2`.
- `Resonance.QueryIntent` — still the contract between LLM output and data fetching.
- `Resonance.Result` — still the normalized truth a primitive produces.
- `Resonance.Composer` — still parallelizes resolution and streams Renderables.
- `Resonance.Presenter` — still maps Results to components.
- `Resonance.Component` — read-only function components (charts, tables, prose).
- The LLM tool-use flow, the system prompt, the registry.

If you only ever write read-only reports, nothing changes. v2 is purely additive.

## What's new (three things)

### 1. `Resonance.Widget` — a behaviour on top of LiveComponent

A widget is a Phoenix LiveComponent that implements the `Resonance.Widget`
behaviour. The behaviour is symmetric to `Resonance.Component` (which exists
for the read-only path):

```elixir
defmodule MyApp.Widgets.FilterableLeaderboard do
  use Resonance.Widget   # gives you LiveComponent + the behaviour

  alias MyApp.Deals

  @impl Resonance.Widget
  def accepts_results, do: [:ranking]

  @impl Resonance.Widget
  def capabilities, do: [:filter, :live_updates]

  @impl Resonance.Widget
  def example_renderable, do: # synthetic Renderable for the playground

  # Optional: only used by the playground when an on_mount hook provides
  # widget_assigns. Returns a Renderable built from real data via the
  # widget's own contexts.
  @impl Resonance.Widget
  def playground_renderable(widget_assigns) do
    rows = widget_assigns.deals_ctx.top_by_value(limit: 10)
    Resonance.Renderable.ready_live("rank_entities", __MODULE__, %{
      title: "Top deals", rows: rows
    })
  end

  # ===== Standard Phoenix.LiveComponent below — Resonance has nothing to teach you =====

  @impl Phoenix.LiveComponent
  def update(%{renderable: r} = assigns, socket) do
    {:ok,
     socket
     |> assign(:title, r.props.title)
     |> assign(:rows, r.props.rows)
     |> assign(:active_stage, r.props[:active_stage])
     |> assign(:current_user, assigns[:current_user])}
  end

  @impl Phoenix.LiveComponent
  def handle_event("filter_stage", %{"stage" => stage}, socket) do
    rows = Deals.top_by_value(stage: stage, user: socket.assigns.current_user)
    {:noreply, socket |> assign(:active_stage, stage) |> assign(:rows, rows)}
  end

  def render(assigns), do: ~H"..."
end
```

The contract:

- **Required:** `accepts_results/0 :: [Result.kind()]` — which Result kinds
  this widget can render. Drives Presenter dispatch and playground enumeration.
- **Optional:** `capabilities/0 :: [atom()]` — declares which user gestures
  the widget supports. Documentation only; the playground shows it.
- **Optional:** `example_renderable/0` — synthetic Renderable for the
  playground.
- **Optional:** `playground_renderable/1` — Renderable built from real data
  for the playground; receives the `widget_assigns` map.
- **From `Phoenix.LiveComponent`:** `update/2` accepts a `:renderable` assign
  carrying a `%Resonance.Renderable{}`. The widget reads `:props` for initial
  state. After that, everything is normal LiveComponent: `handle_event/3`
  calls your contexts, mutations broadcast on PubSub, the parent forwards
  messages via `send_update`.

`use Resonance.Widget` is one line that pulls in `Phoenix.LiveComponent` and
declares `@behaviour Resonance.Widget`. Developers write widgets the way they
write any other LiveComponent — call their own contexts from `handle_event/3`,
manage local state in socket assigns, handle mutations directly. Resonance
teaches one extra thing: "tell us what Result kinds you accept."

The Presenter, instead of always returning a function-component module, may
now return a Widget module via `Renderable.ready_live/3`. The `Renderable`
gains one field — `render_via: :function | :live` — which the constructor
sets. That's the only struct change.

**Why a behaviour, not just a convention:**

1. The library's identity is contracts. Primitive, Resolver, Presenter,
   Result, QueryIntent, and Component are all behaviours. A widget that's
   "a LiveComponent with a magic assign name" would be the only anomaly.
2. The playground needs widget enumeration and per-widget metadata. Without
   a behaviour, the playground reinvents one internally.
3. Declared capabilities are exactly the structured developer-side context
   the LLM could one day use to bias toward explorability. Building it in
   v2 is nearly free and unblocks v2.1.

### 2. `Live.Report` renders both kinds

The render loop in `Live.Report` learns to branch on `render_via`. In the
template, not in a private function:

```heex
<%= for c <- Layout.order(@components) do %>
  <%= if c.render_via == :live and c.status == :ready do %>
    <.live_component
      module={c.component}
      id={c.id}
      renderable={c}
      {@widget_assigns}
    />
  <% else %>
    {render_component(c)}
  <% end %>
<% end %>
```

Two notes:

- The function-component path is unchanged from v1.
- `<.live_component>` is mounted with the renderable plus a `widget_assigns`
  map the parent LiveView passes to `Live.Report`. That map is how widgets
  get app handles (current_user, app contexts, anything else they need).
  Resonance doesn't prescribe what's in it.

This is the only refactor to existing code. It's localized to `Live.Report`.

### 3. The Presenter does more work

In v1 the presenter was thin: pick a component, pass props through. In v2
the presenter is the seam where the LLM-resolved `Result` becomes
widget-friendly assigns. It's where "the QueryIntent had a stage filter,
extract it into `:active_stage`" happens.

```elixir
def present(%Result{kind: :ranking, intent: %QueryIntent{dataset: "deals"} = intent} = result, _ctx) do
  Renderable.ready_live("rank_entities", FilterableLeaderboard, %{
    title: result.title,
    rows: result.data,
    active_stage: stage_filter_value(intent.filters)
  })
end

defp stage_filter_value(filters) when is_list(filters),
  do: Enum.find_value(filters, &(&1.field == "stage" && &1.value))
defp stage_filter_value(_), do: nil
```

The widget never has to look at a `QueryIntent`. It receives `:active_stage`
as an atom in its props. The presenter is the developer-controlled translation
layer between truth and presentation; v2 leans into that role.

## Live updates from data changes

Because widgets are real LiveComponents, you handle live updates the way
Phoenix already does it: subscribe to a `Phoenix.PubSub` topic in the
**parent LiveView**, and on receiving a message call
`Phoenix.LiveView.send_update/2` to push a refreshed `:renderable` (or fresh
assigns) into the widget. LiveComponents share their parent process and
can't subscribe to PubSub directly — but the parent owning the subscription
is the standard Phoenix pattern, so this is the same code you'd write
without Resonance in the picture.

For the playground specifically: the on_mount hook can provide `:pubsub`
and `:subscribe_topics`. The playground subscribes on mount and re-resolves
the currently-selected widget on any message. This is how the demo's
"Simulate New Deals" button auto-refreshes the playground.

## Mutations work the same way

A widget that creates a deal calls `MyApp.Deals.create_deal/2` from
`handle_event/3`. On success it broadcasts on a PubSub topic. Any other
widget (or LiveView) listening on that topic refreshes itself. There is no
Resonance API for mutations because there doesn't need to be — Phoenix
already has one.

## What v2 explicitly does *not* include

Naming these because previous design rounds had us inventing solutions for
them, and v2 is better off without those solutions until a real app forces
the issue.

- **No `Resonance.refine/3`.** Earlier drafts of v2 routed user gestures back
  through Resonance and the resolver. The simpler model is: widgets call
  your own contexts directly. Trust boundaries are enforced in your context
  code (the same place you enforce them for non-Resonance Phoenix code).
- **No `Resonance.Scope` struct.** Widgets that need context get it the way
  every LiveComponent gets it: as assigns from the parent. `Live.Report`
  threads `widget_assigns` to every mounted widget; the parent decides
  what's in it.
- **No `Resonance.invoke/3` for cross-primitive calls.** If a widget needs a
  different primitive, v2 says "regenerate the report" (which already
  exists). Cross-primitive drilldown without regeneration is a later problem.
- **No `Resonance.commit/4` and no mutation invalidation.** Widgets mutate
  by calling app contexts directly. Other widgets refresh by subscribing to
  PubSub. No dataset-dependency tracking in v2.
- **No LLM capability tags in the system prompt.** The LLM stays fully
  unaware of interactivity in v2. If a Presenter has no interactive widget
  for a Result kind, it falls back to the read-only one. (This becomes a
  problem when developers want the LLM to bias toward "explorable" reports.
  Later.)
- **No widgets reading `Renderable.result` at runtime.** The Renderable
  carries the underlying `Result` as a paper trail — it's there for
  developer introspection (read it from IEx while debugging a custom
  resolver) but the widget contract is "receive `:renderable`, work with
  `:props`." Reading `:result` from a widget is going off contract.

Each of these omissions has a real use case behind it. None of them are
needed for the first version of an app to ship an interactive report. We
add them when an actual app fails without them, not before.

## The five layers, restated for v2

| Layer | Read-only (v1) | Interactive (v2) |
|---|---|---|
| **1. Primitive** | LLM picks one; produces a Result. | Identical. |
| **2. Resolver** | Validates intent, fetches data. | Identical. |
| **3. Presenter** | Maps Result kind to a function component. | Maps to a function component **or** a LiveComponent (`ready` vs `ready_live`). Also unpacks the `Result.intent` into clean widget props. |
| **4. Composer** | Parallel resolve + stream Renderables. | Identical. Stamps the source `Result` onto each Renderable for developer introspection. |
| **5. LiveView surface** | Renders function components. | Renders both kinds. Mounts widgets via `<.live_component>` with a `widget_assigns` map merged from the parent. **Once mounted, widgets are normal LiveComponents** — Resonance is no longer in the path. |

The cleanliness of the original five-layer model is preserved. v2 adds **one
behaviour** (`Resonance.Widget`), **one struct field** (`render_via`), **one
constructor** (`Renderable.ready_live/3`), and **one render-loop branch**.
Everything else is "developers write LiveComponents, the way they always
have."

## What you can build with this

Concretely, v2 supports:

1. **Filterable charts.** The widget owns filter state in assigns; on filter
   change it calls your own context (e.g. `Deals.top_by_value(stage: stage)`)
   and updates `:rows`. No LLM round-trip.
2. **Drilldown within a primitive.** Same as above with a different filter
   shape — clicking a bar adds a `where` clause via your context.
3. **Forms that mutate app state.** The widget calls
   `MyApp.Deals.create_deal/2` from `handle_event/3` directly. On success it
   broadcasts on a PubSub topic. The parent LiveView receives the broadcast
   and forwards a refreshed Renderable to any widget that needs it via
   `send_update/2`.
4. **Editable reports.** A "save this view" button reads
   `assigns.renderable.props` and persists it. A "load view" widget hydrates
   a new Renderable from a stored payload.
5. **Mixed read-only and interactive widgets in the same report.** The
   Presenter chooses per-Result.

It does *not* support, in v2:

- Automatic invalidation of unrelated Renderables after a mutation (without
  PubSub plumbing in the parent).
- LLM-aware drilldown that switches primitives.
- A widget marketplace with portable capability metadata.
- User-driven authorization rules distinct from LLM-driven ones (your
  contexts enforce both, the same way they would without Resonance).

Those are real things. They're for a later version.

## The thing that makes this feel different from a dashboard

The entire interactive surface is built out of Phoenix primitives the
developer already knows, wired into a report whose structure was chosen by
an LLM from a developer-described semantic vocabulary. The LLM picked *what
the report is about*. The developer's widgets — which are just
LiveComponents — decide *what the user can do with it*. Both sides operate
on the same data.

That's the paradigm. v2 is the smallest possible expression of it: one
behaviour, one struct field, one constructor, one render branch, and a
paragraph of documentation that says "your widget is a LiveComponent with
one extra callback."

## v2 build order

1. Add `Resonance.Widget` behaviour. One required callback
   (`accepts_results/0`), three optional (`capabilities/0`,
   `example_renderable/0`, `playground_renderable/1`). `use Resonance.Widget`
   pulls in `Phoenix.LiveComponent` and the behaviour.
2. Add `render_via` to `%Renderable{}`. Default `:function`. Add
   `Renderable.ready_live/3`. No behaviour change for existing code.
3. Refactor `Live.Report.render/1` to branch on `render_via` in the template
   and merge `widget_assigns` into the live_component dispatch. Verify the
   read-only test suite still passes.
4. Build the playground LiveView. Enumerates Widget-implementing modules,
   renders each against `example_renderable/0` (or `playground_renderable/1`
   when an `on_mount` hook provides `widget_assigns`), displays declared
   capabilities. Mounted at `/resonance/playground` in the CRM demo.
5. Build interactive widgets in `example/resonance_demo` (one per primary
   Result kind: `:ranking`, `:distribution`, `:segmentation`, `:comparison`).
   Each calls `ResonanceDemo.Deals` directly from `handle_event/3`. The
   playground's `on_mount` hook subscribes to PubSub so simulate updates
   the rendered widget.
6. Document the convention: "a Resonance widget is a `use Resonance.Widget`
   LiveComponent. Implement `accepts_results/0`. Use Phoenix the way you
   always have. The library composes; Phoenix runs."

The discipline for v2 is: nothing goes in the library that the example app
doesn't need. Every additional concept earns its place by failing without
it.
