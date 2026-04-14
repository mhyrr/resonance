# Resonance v3 (vision): Adaptive Workspaces

> **Status: exploratory.** This is a thinking document, not a build plan. It
> records a direction we want to pressure-test. Parts of it will be wrong. We
> are explicitly not committing to implementation until a few cheap experiments
> tell us whether the core thesis survives contact with reality.

## The north star

Imagine a CRM with **zero pre-built pages**.

A user opens the app, types or speaks what they want to see, and a workspace
materializes in real time. It is bound to real data. It is interactive. It is
composed from the developer's own product vocabulary. The user asks for
something else; a different workspace appears. They want to create a new deal;
the system composes the right action surface for that too, using the
developer's own rules and handlers.

No one page was pre-built for that moment. The developer did not have to
anticipate the exact view. They built a system of capabilities, presentation
patterns, and product primitives. Resonance turned the user's intent into a
working surface.

That is the north star.

## The line we want to make true

> **Resonance lets a user's intent project a workspace from the application's
> capabilities.**

If that sentence becomes true, Resonance is interesting. If it does not, we are
still in the world of "LLM routes you to a prettier dashboard."

## Why this document replaces the earlier framing

An earlier v3 framing described the application as a **vocabulary** and leaned
heavily on the idea that the LLM would compose from the developer's design
system directly.

That framing was directionally right, but too renderer-centric.

It makes the leap from v2 sound like this:

- v2: the model picks semantic results, the app renders them
- v3: the model picks UI atoms, the app renders them

That is too abrupt, and probably not the right abstraction boundary.

If we jump straight from "generated reports" to "runtime atom composition," we
skip the missing middle:

- a first-class model of a generated **workspace**
- a planner that understands **roles**, not just components
- a durable identity for generated views that can be revisited and refined
- a contract for what the app can **know**, **show**, and **do**

So this rewrite changes the center of gravity.

The design system still matters, but it is not the primary abstraction.
**Adaptive workspaces** are the primary abstraction. The design system is the
renderer layer underneath them.

## The philosophical claim

Today's business software is mostly a set of frozen answers to anticipated
questions.

Pages, dashboards, and CRUD screens exist because someone guessed in advance
what users would need often enough to justify building a view around it. That
works tolerably well for common cases. It fails at the edge, where a user's
actual need is narrow, contextual, fleeting, or simply not frequent enough to
win roadmap priority.

The philosophical claim behind Resonance is not:

> "An LLM can generate UI faster than a human can."

That is true sometimes, but it is not the interesting part.

The stronger claim is:

> **UI should stop being a fixed set of pages and start being a system that can
> materialize the right workspace for the user's actual problem in the moment
> they have it.**

That is a different theory of interface design.

Pages are precomputed affordances.
Workspaces are projected affordances.

If that theory is right, a good product is less like a set of screens and more
like a capability field that can be shaped into many valid working surfaces.

## What developers actually author

If this vision is right, developers do not stop authoring UI. They stop
authoring **pages as the primary unit**.

What they author instead:

- **Data capabilities**
  What the system can query, aggregate, compare, and explain.

- **Action capabilities**
  What the user is allowed to do, with developer-owned validation and handlers.

- **Interaction patterns**
  The stable product shapes that are worth teaching the system: review queue,
  detail panel, metric strip, activity feed, action form, comparison panel,
  and so on.

- **Render kit**
  The actual Phoenix components, widgets, slots, styling rules, and interaction
  semantics that make the product feel like itself.

- **Guardrails**
  Validation rules, trust boundaries, accessibility expectations, and layout
  constraints.

So the authored system gets smaller in one sense and richer in another.

The developer no longer writes every surface the user might need. They write
the **field of valid surfaces** the product knows how to produce.

## The honest worry

The worry worth naming early:

> "A design system already lets a human developer build any view in 20 minutes.
> Swapping in an LLM at runtime produces the same artifact with worse latency.
> We have moved labor, not changed the product."

That worry is real.

There is a fake version of this vision that is exactly that: a slow,
non-deterministic substitute for a frontend engineer. That version is not
interesting enough to justify itself.

So the question is not whether the model can compose something plausible.
The question is whether query-time composition changes the **economics and
shape** of the product.

The version that might be novel is this:

- **Today:** views are shaped by the developer's imagined model of what users
  usually need.
- **Resonance:** workspaces are shaped by the user's actual framing of the
  problem they have right now.

If that leads to a growing set of useful, revisitable, shareable, user-shaped
workspaces that no team would have pre-built, the thesis holds. If it does not,
we should say so plainly.

## The missing middle between v2 and the north star

v1 and v2 established important pieces:

- **v1:** semantic primitives, resolver boundary, presenter boundary,
  renderables, read-only reports
- **v2:** interactive widgets as real LiveComponents, with Phoenix owning the
  runtime after composition

Those are good foundations. But they are still fundamentally about assembling
blocks on a page.

The missing middle is a first-class model of a **generated workspace**.

Before we jump to raw design-system composition, Resonance probably needs an
intermediate phase with capabilities like:

1. **Report-level planning**
   A generated surface should have structure beyond "a sorted list of blocks."
   It needs sections, priorities, relationships, supporting evidence, and
   refinement affordances.

2. **Workspace identity**
   If a user asks for "my stuck deals this quarter" and comes back tomorrow,
   what is the identity of that workspace? Can they save it, rerun it, share
   it, promote it, refine it?

3. **Cross-section reasoning**
   The summary should be about the assembled workspace, not just one primitive's
   result. A detail pane should be related to the focus list beside it. The
   surface needs a plan, not just a pile.

4. **Capability manifests**
   The app needs a structured way to declare what can be queried, what actions
   can be taken, and what interaction patterns it supports.

Without that middle layer, a leap straight to raw atom trees risks being
impressive in demos and brittle in product use.

## What v3 should actually be

v3 should not be "the LLM composes arbitrary atoms."

v3 should be:

> **A planner that turns user intent into a typed workspace plan, then compiles
> that plan into Phoenix surfaces using the application's declared
> capabilities, patterns, and components.**

That implies three layers.

### 1. Capability graph

The application needs to declare not only what data exists, but what it can
know, what it can do, and what kinds of surfaces it knows how to support.

The capability graph has three branches:

- **Data capabilities**
  The existing resolver world. What datasets, measures, dimensions, filters,
  and derived analyses are allowed.

- **Action capabilities**
  Mutations and commands the user can request, with developer-owned validation
  and handlers.

- **Interaction capabilities**
  The high-level ways the application can present and manipulate information:
  compare, browse, inspect, queue, review, edit, approve, triage, create,
  enrich.

The key change from the earlier draft:

The planner should reason primarily over **capabilities and patterns**, not raw
presentational atoms.

### 2. `Resonance.WorkspacePlan`

The missing IR is not a JSON tree of components. It is a typed plan for a
workspace.

Something like:

```elixir
%WorkspacePlan{
  goal: :pipeline_review,
  title: "Pipeline review for this week",
  layout: :overview_with_detail,
  sections: [
    %Section{
      id: "summary",
      role: :summary,
      pattern: :metric_strip,
      source: {:primitive, "segment_population", %{dataset: "deals", ...}}
    },
    %Section{
      id: "stuck_deals",
      role: :focus_list,
      pattern: :entity_list,
      source: {:primitive, "rank_entities", %{dataset: "deals", ...}},
      interactions: [:filter, :inspect]
    },
    %Section{
      id: "trend",
      role: :supporting_context,
      pattern: :trend_panel,
      source: {:primitive, "compare_over_time", %{dataset: "deals", ...}}
    }
  ],
  refinements: [
    %{label: "This quarter", filter: %{field: "quarter", op: "=", value: "2026-Q2"}}
  ],
  identity: %{kind: :ephemeral, saveable: true}
}
```

This is the crucial shift.

The plan expresses:

- what the workspace is for
- how it is laid out
- what each section's role is
- how sections relate to data and actions
- which refinements exist
- whether the surface has a stable identity

That is closer to the philosophical idea than a raw atom tree.

### 3. Pattern kit

The first compositional surface should be built from **mid-level patterns**,
not low-level atoms.

Examples:

- `metric_strip`
- `entity_list`
- `comparison_panel`
- `detail_panel`
- `timeline`
- `review_queue`
- `activity_feed`
- `action_form`
- `context_header`

These patterns are still developer-owned. They compile down to the app's actual
components and widgets. But they give the model a better unit of reasoning than
"card," "button," or "list_row."

This is important for four reasons:

1. The model has less surface area to thrash on.
2. The validator has stronger invariants.
3. Visual coherence is easier to preserve.
4. Accessibility and behavior stay concentrated in developer-authored patterns.

### 4. Render kit

The design system still matters. It just moves down one layer.

The render kit is the developer's actual Phoenix component vocabulary: function
components, widgets, slots, CSS conventions, interaction details.

Patterns compile to the render kit.

Later, if experiments prove it useful, Resonance may support more direct
composition from the render kit as an escape hatch. But that should not be the
first successful version of v3.

The first version should optimize for coherence and validity, not expressive
maximalism.

## Pages do not disappear; they change status

The phrase "zero pre-built pages" is useful as a north-star provocation, but it
can mislead if taken too literally.

The better claim is:

> **Pages stop being the only authored unit and become one possible stable form
> of a workspace.**

In a mature version of this system, there are several states a surface can move
through:

1. **Ephemeral workspace**
   Projected from a question for a momentary need.

2. **Saved workspace**
   Kept because the user expects to return to it.

3. **Shared workspace**
   Passed to teammates because it is useful beyond one person.

4. **Promoted workspace**
   Recognized by the product team as broadly valuable and given a durable place
   in navigation, onboarding, or operations.

5. **Stabilized page**
   A workspace that has effectively become a page because it proved worth
   keeping around.

This matters because it connects the philosophy to reality.

The future world is not "no structure." It is a world where structure
**emerges first** and is only hardened into a page when repeated use justifies
it.

That is a more plausible transition path than imagining fixed pages simply
vanishing.

## What happens to `UIKit`

The earlier draft's `Resonance.UIKit` idea is still useful, but its role
changes.

Instead of being the planner's primary abstraction, it becomes one of two
things:

1. **The implementation layer behind the pattern kit**
   The app still exposes its components and descriptions, but Resonance uses
   them mainly to render known patterns.

2. **A later-stage escape hatch**
   Once the planner and validator are proven, a developer can choose to expose
   a smaller atom-level vocabulary for freer composition where it makes sense.

So `UIKit` stays as a good idea, but not as the center of v3.

## What happens to `Actions`

The earlier draft's `Resonance.Actions` idea survives almost unchanged.

That part is sound:

- the app declares what actions exist
- the app declares the parameter shapes
- the app owns the trust boundary in `perform/3`

The change is sequencing.

I would not make action composition the first proof of v3. Read-only and
refine-only workspaces are the safer proving ground. Once the workspace planner
is credible, then composed forms and action surfaces become a meaningful next
step rather than an extra axis of uncertainty.

## What v3 is not

To keep the idea honest, v3 explicitly does **not** mean:

- ❌ **LLM-emitted HEEx**
  Never. The model does not write templates.

- ❌ **Direct raw atom composition as the primary IR**
  That is too low-level for the first serious version.

- ❌ **A Resonance-owned component library**
  The app still owns the actual product language and rendering.

- ❌ **Replacing Phoenix as the runtime**
  Phoenix still owns state, events, PubSub, forms, and LiveView semantics.

- ❌ **A total replacement for all fixed product surfaces**
  Some views should stay authored. Generated workspaces complement them.

- ❌ **A single-step jump from v2 to the full north star**
  There is probably a staircase here, not a cliff.

## How this coexists with v1 and v2

This remains additive.

- **v1** stays for semantic-result-to-component routing when the developer wants
  deterministic visual mappings.

- **v2** stays for polished, developer-authored interactive widgets and
  higher-fidelity product surfaces.

- **v3** becomes the planner layer for cases where the user's problem does not
  map cleanly to one pre-authored view.

One generated workspace can mix all three:

- a v1 chart section
- a v2 widget section
- a v3-composed pattern section

That is the right shape. Resonance should become more expressive without
invalidating the simpler modes that already work.

## The actual progression is probably not "v2 -> v3"

The earlier framing made it sound like the next big thing after widgets is
freeform design-system composition. I no longer think that is the right next
step.

What is more likely:

### v2.5: Generated workspaces over existing primitives

Before any new composition contracts, add:

- report-level planning
- section roles
- better layout semantics
- summary over assembled results
- workspace persistence / identity
- refinement flows over a saved/generated surface

This would already move Resonance closer to the philosophical top line.

### v2.6: Structured capability manifests

Introduce:

- action manifests
- interaction / pattern manifests
- a more structured story around queryable capabilities

This gives the planner real material to work with.

### v3: Adaptive workspace planning

Once the middle layer exists, add:

- `WorkspacePlan`
- pattern kit selection
- compilation into the app's render kit
- optional action surfaces

That feels like a real v3.

## The hard problems that matter now

These are the questions the rewrite sharpens.

1. **Plan schema design**
   What is the right IR for a workspace? Too weak and it collapses back into a
   bag of blocks. Too expressive and validation becomes hard.

2. **Pattern granularity**
   What is the right unit for model composition? Too coarse and the planner is
   not useful. Too fine and outputs become inconsistent.

3. **Validity and retry**
   The planner will emit malformed or incoherent plans. We need validation with
   actionable feedback, not silent failure.

4. **Workspace identity**
   When is a generated surface "the same workspace" across sessions? This is
   critical for persistence, sharing, and trust.

5. **Cross-section semantics**
   How do sections refer to one another? How does a detail pane know which list
   it supports? How does a summary cite supporting evidence?

6. **Latency**
   The planner cannot make the app feel sluggish. We need real measurements, and
   probably a mix of caching, streaming, and staged refinement.

7. **Mutation trust**
   Once forms enter the picture, we need explicit control over what the model
   may suggest, what it may prefill, and what the user must author themselves.

8. **Visual coherence**
   A generated workspace has to feel intentional. That pushes a lot of
   responsibility into the pattern kit and its compile step.

## The experiments to run before building anything serious

These should stay cheap.

### 1. Workspace-plan prototype

Do **not** start with raw atoms.

Hand-craft a pattern kit with maybe 10 to 15 patterns. Ask Claude or GPT to
emit a `WorkspacePlan`-like JSON structure for five CRM questions.

Evaluate:

- Is the plan well-formed?
- Are the section roles sensible?
- Is the layout choice coherent?
- Does it choose patterns reasonably?

If this fails, raw atom composition would likely fail more noisily.

### 2. Compiler prototype

Take a hand-written workspace plan and compile it into today's Resonance
renderables and widgets.

This tests whether the "plan first, render second" architecture is a real fit
for the current system.

### 3. Persistence / rerun test

Save a generated plan, rerun it against changed data, and inspect whether it
still feels like the same workspace.

This is closer to the real product than a one-shot generation demo.

### 4. Single action-surface test

Only after read-only planning looks good, test one composed form bound to one
safe action, with strict validation.

This tells us whether actions belong in the first real iteration or a later one.

### 5. Longitudinal dogfood

Put a prototype in front of someone who actually works in a CRM-like environment
for weeks, not minutes.

Count:

- workspaces they return to
- workspaces they save or share
- refinements they make over time
- requests that no one would have built as a fixed view

That is the real thesis test.

## If the experiments work

This probably becomes a staircase rather than one branded "v3" launch.

A plausible sequence:

- **Step 1:** report-level planning and workspace identity
- **Step 2:** capability manifests and pattern kit
- **Step 3:** planner -> `WorkspacePlan`
- **Step 4:** compiled workspaces mixing v1, v2, and new patterns
- **Step 5:** carefully scoped action surfaces
- **Step 6:** optional lower-level composition for advanced apps

That feels like a product evolution, not a stunt.

## If the experiments do not work

Then the result is still useful.

v1 and v2 remain valuable on their own terms:

- semantic-result routing
- developer-owned presentation
- Phoenix-native widgets

This vision can stay archived as a serious line of thought that did not yet
clear the bar. That is fine. A cheap failed experiment is vastly better than
building a large wrong thing.

## What we commit to now

1. **Keep the north star.**
   The philosophical direction is still worth pursuing.

2. **Change the immediate framing.**
   The next step is generated workspaces, not raw atom composition.

3. **Run cheap tests first.**
   Especially the workspace-plan prototype and compiler prototype.

4. **Do not force a direct v2 -> v3 jump.**
   There is probably at least one missing middle version here.

That is the revised position.

The application is not just a vocabulary.
It is a field of capabilities.

The UI question is not "which page should exist?"
It is "what workspace should this intent project right now?"
