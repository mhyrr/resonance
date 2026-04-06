# Resonance v3 (vision): The application as a vocabulary

> **Status: exploratory.** This is a thinking document, not a build plan. It
> records a direction we're interested in and the reasoning that got us there.
> Parts of it will probably be wrong. We commit to running a few small
> experiments before committing to any of it.

## The north star

Imagine a CRM with **zero pre-built pages**. A user opens the app, types or
speaks what they want to see, and the view materializes — composed in real
time from the developer's own component library, bound to real data, fully
interactive. The user asks for something else; a different view appears.
They want to create a new deal; a form is composed on the fly from the
developer's form components, bound to the developer's own create action.
They never see a page a developer pre-built, because no page was pre-built.

The developer didn't anticipate any of this. They built a design system
(cards, list rows, metric tiles, form fields, buttons — the normal
vocabulary of their app) and they wired up data access and mutations. That's
it. Every view the user asks for is composed at query time, from that
vocabulary, against that data.

## The guiding line

> **Resonance lets the user's question pick from the developer's design
> system.**

If this sentence is true, we're interesting. If it's false or we can't make
it true, we're a slow LLM router.

## Why now — the intelligence overhang

The models are already smart enough to do this. That's the bet. The gap
between "LLM that can compose a design system into a view" and "LLM in
production" is not a capability gap — it's a **context gap**. What the model
needs to do this well:

1. **The user's question**, in the user's own framing.
2. **A structured vocabulary** describing what the developer's design system
   contains: atoms, their props, their expected nesting, their role.
3. **A structured data layer** describing what's queryable and what isn't.
4. **An action layer** describing what mutations are available and with
   what shapes.
5. **A validator and feedback loop** so malformed compositions get rejected
   and retried instead of rendered as garbage.

All five of those are context-engineering problems, not intelligence
problems. The overhang is that we haven't built the plumbing yet — not that
the models can't see.

## The honest worry

The worry that's worth naming before going further:

> "A design system already lets a human developer build any view in 20
> minutes. Swapping in an LLM at runtime produces the same output with worse
> latency. We've moved labor, not enabled anything new."

The version of this that's just moving labor is real and we shouldn't
confuse it with the novel thing. "LLM substituted for developer, same
artifacts" is a productivity win at best and a slow dashboard tool at worst.
It is not v3.

## The version that might be novel

The shift that makes this something other than "non-deterministic developer"
is a shift in **when and from whom** views get constructed:

- **Today (developer at build-time):** views are shaped by the developer's
  imagined model of what users need. They're anchored to the data shape
  ("we have a deals table — let's build a deals dashboard"). Building is
  expensive, so the view set is small and fixed.
- **v3 (LLM at query-time):** views are shaped by the user's *actual*
  framing of their *actual* problem at the moment they're having it.
  They're anchored to the question, not the data. Building is effectively
  free, so the view set is unbounded and ephemeral.

The qualitative claim:

> Most of the views a user wants don't exist in any app, and never will,
> because no developer would prioritize building them. They live in one
> user's head for one moment. Resonance v3 materializes them.

Whether this claim is true is an empirical question. But if it's true, it's
*a different economic situation*, not a speed-up of the current one.

## The test that would validate this

Not a 30-minute usability session — that's the wrong time horizon for
"adaptive needs that compound over time." The right test:

> **Give a working professional — a sales manager, a researcher, an ops
> lead — access to a v3-powered version of an app they already use, for at
> least a month. Watch how their usage evolves. Count:**
>
> - Views they generate that no developer would have pre-built.
> - Views they return to in subsequent sessions (i.e. they're not one-offs).
> - Views they share with teammates by copying the question.
> - Mutations they perform through composed forms rather than through
>   pre-built CRUD screens.
> - The rate at which their questions become more sophisticated as they
>   learn what the system can do.

If "adaptive needs compound over time" — if the user grows into ways of
asking that a fixed app would have stifled — the thesis holds. If they
quickly converge on a small set of views equivalent to what a developer
would have built, the thesis is warmed-over routing and we should say so.

Over a month, even moderate compounding produces a view set no human
developer would have shipped. Over a year, it's a different product.

## The minimum novel surface

If we take the thesis seriously, Resonance needs three contracts beyond
what v1 and v2 already provide. Each is the *smallest* version that could
work:

### 1. `Resonance.UIKit` — the vocabulary contract

The developer declares which of their function components the LLM is
allowed to compose with, plus a description of each. This is the machine-
readable manifest of an app's UI atoms.

```elixir
defmodule MyApp.ResonanceKit do
  use Resonance.UIKit

  expose :card,         MyAppWeb.CoreComponents, :card
  expose :list_row,     MyAppWeb.CoreComponents, :list_row
  expose :metric_tile,  MyAppWeb.CoreComponents, :metric
  expose :form_field,   MyAppWeb.CoreComponents, :form_field
  expose :deal_card,    MyAppWeb.DealComponents, :deal_card
  # ...

  @impl true
  def describe do
    """
    Atoms:
    - card: container with optional title, header_action, body slot, footer slot
      props: %{title: string, body: children}
    - list_row: a row in a vertical list
      props: %{title: string, subtitle: string, trailing_value: string, on_click: action_id}
    - metric_tile: large number with label
      props: %{label: string, value: number | string, format: "currency" | "number" | "percent"}
    - form_field: input field bound to a form
      props: %{name: string, type: "text" | "number" | "date" | "select" | "currency", label: string}
    ...
    """
  end
end
```

`describe/0` is the thing the LLM sees. It's prose-plus-structure for now;
we may tighten to a schema once we understand what shape the LLM composes
well against.

### 2. `Resonance.Actions` — the mutation contract

Parallel to the resolver (which describes queries), a manifest of "things
the user can do." Each action has a name, a parameter schema, a description,
and a handler.

```elixir
defmodule MyApp.ResonanceActions do
  use Resonance.Actions

  @impl true
  def describe do
    """
    Actions:
    - create_deal(name, value, stage, owner): creates a new deal
    - log_call(contact_id, notes, date): logs a call against a contact
    - mark_deal_won(deal_id): marks a deal as closed_won
    """
  end

  @impl true
  def perform("create_deal", %{"name" => n, "value" => v, "stage" => s, "owner" => o}, ctx) do
    MyApp.Deals.create_deal(%{name: n, value: v, stage: s, owner: o, user: ctx.current_user})
  end

  def perform("log_call", params, ctx), do: MyApp.Activities.log_call(params, ctx)
  def perform("mark_deal_won", %{"deal_id" => id}, ctx), do: MyApp.Deals.mark_won(id, ctx)
end
```

The trust boundary is the same as the resolver's: the developer-controlled
`perform/3` decides what's allowed. The LLM can *request* any action, but
only `perform/3` decides whether it runs.

### 3. Compose primitives

New semantic primitives that produce *structural* outputs rather than
tabular data:

- `compose_view(tree)` — emits a nested tree of atom invocations that
  produces a read-only composition.
- `compose_form(schema, submit_action)` — emits a form tree bound to a
  registered action.

Their `resolve/2` doesn't call the resolver. It builds a Renderable whose
`:props` contain the tree. A new function component — `Resonance.Render.Tree`
— walks the tree and dispatches to the developer's `UIKit.render/2` per
node.

### What we're NOT building

- ❌ **LLM emitting HEEx as a string.** Security nightmare. Contract-break.
  We never accept raw HEEx from the LLM — only structured JSON trees that
  get walked and rendered by our code.
- ❌ **A Resonance-shipped component library.** Resonance does not bring
  widgets. The whole point is the developer brings the vocabulary.
- ❌ **A generic widget marketplace.** Not our problem. If the developer
  wants to share their UIKit across projects, that's a their-problem.
- ❌ **Multi-step wizard runtime.** Once a composed form is mounted, it's
  a normal Phoenix LiveView surface — state management is Phoenix's job.
  v3 is composition, not stateful runtime semantics beyond what Phoenix
  already handles.
- ❌ **LLM tuning / fine-tuning.** We don't train. The context-engineering
  bet is that current off-the-shelf models are enough.

## How this coexists with v1 and v2

v3 is **additive, not a replacement**.

- **v1** (read-only function components via presenter dispatch) stays.
  Useful when the developer wants specific charts/tables and doesn't want
  the LLM composing them.
- **v2** (interactive widgets, `Resonance.Widget` LiveComponents) stays.
  Useful when the developer has a polished, high-fidelity interactive
  surface they want the LLM to hand users wholesale.
- **v3** is for the case where the developer wants the LLM to compose from
  primitives rather than pick a pre-built thing.

A presenter can mix all three. For a `:ranking` result, a presenter might:
- Route to `FilterableLeaderboard` (v2 widget) if the dataset is "deals."
- Route to a generic `Resonance.Components.BarChart` (v1) if the dataset is
  anything else.
- Route to `compose_view(...)` (v3) if the user's question asked for
  something that doesn't fit either.

All three coexist on one page.

## Hard problems we don't yet know how to solve

These are the real unknowns. None is a dealbreaker; all need investigation.

1. **Atom alphabet design.** Too few atoms and the LLM can't compose
   anything interesting. Too many and it gets overwhelmed and produces
   inconsistent outputs. The right size for a first UIKit is probably ~15
   to ~25. Finding the right *shape* (how atomic is atomic?) is harder than
   finding the right count.

2. **Composition validity.** The LLM will produce malformed trees. We need
   a validator that rejects them with specific error messages the LLM can
   use to retry (this is where TK-057, the tool-use feedback loop, becomes
   load-bearing).

3. **Visual consistency.** Composed views need to feel coherent, not like
   a bag of components glued together. This depends partly on the atom set
   (well-designed atoms compose coherently; poorly-designed ones don't) and
   partly on LLM guidance in the system prompt.

4. **Latency.** Composing a view shouldn't take 5 seconds. The LLM call is
   the dominant cost. Streaming compositions (render as the tree arrives)
   and caching common compositions are both plausible mitigations.

5. **Accessibility.** A composed view is only as accessible as the atoms
   it's built from. This pushes accessibility responsibility to the
   developer, which is correct but not automatic. We should document
   expectations for what a "good" UIKit atom looks like accessibility-wise.

6. **Cost.** Tokens aren't free. Composing 20 views a day per user at
   current model prices is $0.X per user per day. Viable for some pricing
   models, not for others. Needs measurement.

7. **Trust boundary for LLM-composed mutations.** The LLM picking an action
   is the same trust shape as the LLM picking a primitive — developer's
   `perform/3` is the boundary. But forms composed on the fly may have
   fields the LLM shouldn't be able to pre-fill. Needs a clean contract
   for "this field is user-editable only."

8. **Navigation and persistence.** If a user asks for a view and returns
   three days later, does the same view re-compose? Deterministically?
   This opens questions about view identity, caching, and whether
   compositions should be persistable as first-class artifacts.

## Experiments to run before building

These are cheap and they'll tell us most of what we need to know before
committing real engineering.

1. **The "can it compose?" prototype.** 30 minutes. Hand-craft a small
   UIKit description (10 atoms). Ask Claude or GPT-4 to produce a JSON
   composition tree for "show me my top reps this week with a sparkline
   next to each." Evaluate: is the tree well-formed? Is it using the atoms
   sensibly? Does the nesting make sense? If yes, the core thesis has legs.
   If no, the alphabet design or the prompting needs work before any code.

2. **The "scale test."** Same thing but with a 30-atom realistic kit.
   Does the model still compose coherently, or does the larger surface
   make it thrash?

3. **The "five questions" test.** Ask the model to compose five
   meaningfully different views from the same UIKit ("top reps", "activity
   heatmap", "deals stuck in discovery", "contact funnel", "a form to log
   a call"). Evaluate diversity and correctness.

4. **Cost and latency baseline.** Measure tokens and wall-clock for
   realistic composition requests. Put a number on the cost.

5. **The longitudinal proxy.** Generate 500 synthetic user questions
   covering a breadth of CRM intents. Feed them through a prototype
   composer. Measure: how many compositions are coherent, how many fail,
   how many need a retry, how many the user would find useful.

None of these require building v3 proper. They require an hour or two of
prototyping outside the main Resonance codebase. The outputs tell us whether
to file real tickets.

## If the experiments work

This becomes a roadmap, not a vision:

- **v0.4** — `Resonance.UIKit` behaviour, `expose` macro, `describe/0`
  pipeline, LLM system prompt builder
- **v0.5** — `compose_view` primitive, tree renderer, integration with the
  existing presenter dispatch
- **v0.6** — `Resonance.Actions` behaviour, `compose_form` primitive,
  bound mutation handlers
- **v0.7** — feedback loop validator, retry semantics, telemetry
- **v0.8** — production hardening: caching, cost controls, accessibility
  guardrails

Each of those is a substantive sprint. None is a research project if the
experiments succeed.

## If the experiments don't work

The work already done (v1, v2) is still useful on its own terms — chart
and widget routing is valuable even if composition never ships. The v3
thinking becomes an archived vision document and we revisit when models
get another generation better or when we find a better architecture.

We wouldn't wasted a sprint building something we had to tear out, because
we didn't build anything. That's the point of running the prototypes first.

## What we commit to now

1. **This document**, committed to the repo so future sessions and future
   Greg can find it.
2. **Nothing else.** No tickets for v3 proper. No code. No branches.
3. **One cheap next step:** when the v0.2 polish work is done, spend an
   hour on experiment #1 (the "can it compose?" prototype). Come back with
   a real answer.

The vision is recorded. The experiments are defined. The commitment is to
run the cheap test before doing anything more.

---

**Appendix: what Resonance is *not* doing with this vision**

To keep the north star honest, here's a list of things this direction
explicitly *isn't* about:

- **Not a code generator.** v0, Bolt, Cursor, Lovable — these produce
  static code at build time. A developer commits the output. Different
  product.
- **Not a dashboard builder.** Grafana, Retool, Looker — these let a
  *human* pick from a vendor's fixed widget library to assemble a
  dashboard. Here the user's question picks from the developer's own
  design system at runtime.
- **Not a chat interface.** ChatGPT, Claude.ai — these produce text or
  inline charts. They don't compose interactive forms bound to your app's
  mutations. They don't live inside your product.
- **Not a headless UI library.** Radix, Aria — these need a developer to
  assemble atoms into pages. Here the assembly is the LLM's job at
  runtime.
- **Not a low-code platform.** Bubble, Webflow — these are no-code for
  humans. Here the human writes the app normally; the LLM is the one
  composing at the edges.

What it *is* trying to be: the runtime layer that makes a Phoenix
developer's existing design system and data layer addressable by a user's
natural-language question, at query time, with real interactivity and real
mutations.

Whether that's a real product is the question the experiments will
answer.
