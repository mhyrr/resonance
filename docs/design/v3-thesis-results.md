# Resonance v3 Thesis Results: What The Demo Proves

> Status: conclusion from the v2.5 implementation pass. This is not a new
> vision doc. It records what the current implementation proves, what it does
> not prove, and why the remaining v3 work is still worth doing.

## 2026-05-11 planner/pattern update

The implementation now proves the planner contract with mocked providers:

```text
CRM prompt
  -> create_workspace_plan tool call
  -> JSON-safe WorkspacePlan decoding
  -> deterministic validation against resolver capabilities and pattern manifest
  -> WorkspaceCompiler
  -> existing Renderables/Widgets
```

The golden CRM eval currently exercises ten prompts through planner validation
and compilation. Invalid outputs return structured validation errors, and one
validation-feedback retry is measured by the harness.

This still does **not** prove that a production LLM will reliably choose the
right plan on live prompts. It proves the contract the model must satisfy:
available datasets, measures, dimensions, filters, query shapes, roles,
patterns, and primitive sources are declared structurally, and impossible plans
fail before rendering.

The pattern layer is deliberately small. `Resonance.Patterns` is a manifest of
planner-facing names and compatibility rules, not a Phoenix component behavior.
The planner sees descriptions, roles, result kinds, and allowed source
primitives. It does not see HEEx, component modules, CSS classes, or raw atom
trees. The CRM demo can add a product-specific pattern such as
`:deal_focus_list` without forking Resonance internals.

Workspace-scoped follow-up context now has a pure value boundary:
`Resonance.WorkspaceContext` can summarize a plan, compiled workspace, or
snapshot into planner-facing context. Planner prompts can therefore include the
current workspace's original prompt, sections, roles, patterns, stored primitive
sources, filters, and latest result summaries without making LiveView own the
reasoning contract. This proves the follow-up prompt contract; the reusable
`Resonance.Live.Workspace` surface still needs to decide when to capture,
persist, and pass that context.

## The claim under test

The v3 vision made a strong claim:

> Resonance lets a user's intent project a workspace from the application's
> capabilities.

The current CRM demo does **not** fully prove that sentence.

It proves the deterministic middle of the sentence: a typed workspace can be
projected from declared product capabilities into a real Phoenix surface, bound
to live application data, with stable identity, interactivity, and rerun
behavior.

That is the right thing to have proven first.

If this layer did not work, an LLM planner would only make the failure more
expensive, slower to debug, and easier to mistake for intelligence. The current
demo proves that the non-LLM part of v3 has a coherent shape.

## What exists now

The CRM demo now has a hand-written workspace plan:

- `ResonanceDemo.Workspaces.pipeline_review/0`
- goal: `:pipeline_review`
- layout: `:overview_with_detail`
- stable identity: `crm:pipeline-review`
- five sections: summary, stage mix, quarter trend, top deals, owner scorecard
- each section sources data through an existing `Resonance.LLM.ToolCall`

That plan is not a Phoenix page. It is not HEEx. It is not a component tree.
It is a middle-layer description of the workspace that should exist.

The runtime path is:

```text
WorkspacePlan
  -> validation
  -> WorkspaceCompiler
  -> existing primitive / resolver / presenter path
  -> Renderables and Widgets
  -> Phoenix LiveView
  -> WorkspaceSnapshot
  -> rerun through stored section sources
```

This matters because the old stack is still doing the jobs it was good at:

- primitives interpret the analysis shape
- the app resolver owns data access
- `Result` carries semantic truth
- presenters map truth to UI
- widgets own interaction after mount
- Phoenix owns runtime state, events, PubSub, forms, and rendering

v3 adds the missing layer above those pieces: a workspace plan with identity,
sections, roles, patterns, and sources.

## What the demo proves

### 1. A workspace can be a value, not a page

The screenshot looks like a page because Phoenix has to render somewhere. But
the important artifact is the workspace value.

The CRM surface is produced from a `WorkspacePlan`. The route is only a harness
for rendering and operating that value. That is the first move away from "pages
as the primary unit."

The developer did not build a bespoke `PipelineReviewPage` with hard-coded
queries and fixed component slots. They authored a valid workspace plan using
the product's vocabulary: deals, stages, quarters, owners, rankings, trends,
and scorecards.

### 2. The compiler is the Schwerpunkt

The critical v3 object is not the planner. It is the deterministic compiler.

`WorkspaceCompiler.compile/2` validates the plan before resolving anything. It
then compiles each section through the existing composer/presenter path and
stamps stable renderable IDs from workspace identity, section ID, and renderable
type.

That gives the planner a firm target later. The planner will not be asked to
invent UI. It will be asked to emit a valid plan inside a constrained grammar.

### 3. v1 and v2 were not thrown away

The demo reuses the lower layers instead of replacing them.

v1 gave Resonance:

- semantic primitives
- resolver boundary
- `Result`
- presenter boundary
- renderables

v2 added:

- interactive widgets as LiveComponents
- Phoenix-owned runtime behavior
- refresh paths that do not re-call the LLM

v3 composes those pieces into a workspace. That is a stronger result than a
rewrite. It means the architecture is accumulating capability rather than
forking itself every version.

### 4. The workspace is bound to real app data

The demo reads real CRM data through the app-owned resolver. When `Simulate New
Deals` runs, the app mutates its own database and broadcasts its own update.
Resonance does not own that data layer and does not own that mutation runtime.

The saved workspace is then rerun against the changed data. The summary,
leaderboard, stage distribution, quarter trend, and owner scorecard all update
from the same workspace identity.

That proves the distinction the vision needs:

```text
Resonance composes what should appear.
Phoenix and the app run what appears.
```

### 5. Rerun is a first-class behavior, not regeneration

The page has a snapshot fingerprint and rerun counter because revisiting a
workspace is part of the model.

`WorkspaceSnapshot` stores the validated plan, section metadata, original
prompt, created-at timestamp, and deterministic fingerprint. Rerun uses the
stored section sources and `Pipeline.resolve/3`. It does not call an LLM.

That matters philosophically. A workspace is not an ephemeral chat answer. It
is something the user can come back to, refresh, compare, and eventually refine.

### 6. The demo avoids the dangerous shortcut

The implementation does not use:

- LLM-emitted HEEx
- raw atom trees as the primary IR
- arbitrary component selection by the model
- Resonance-owned app persistence
- Resonance-owned mutations

That is not a limitation to apologize for. It is the thesis taking a safer
shape.

The interesting part is not "the model generated UI." The interesting part is:

> a constrained workspace description can become a working product surface
> through deterministic code and developer-owned capabilities.

## What the demo does not prove

### 1. It does not yet prove user intent -> workspace plan

The CRM workspace is hand-written. The user prompt is present as the original
intent string, but no planner currently turns that string into the plan.

So the current demo proves:

```text
valid WorkspacePlan -> working workspace
```

It does not yet prove:

```text
open-ended user intent -> valid WorkspacePlan -> working workspace
```

That is the next real test.

### 2. It does not yet prove zero pre-built pages

There is still a `/workspace` route. That route is a demo harness, not the final
interface model.

The stronger claim becomes true only when a user can ask for different
workspaces and the system materializes different valid plans without each
workspace having been hand-authored in advance.

The current result makes that plausible because the rendered surface is derived
from the plan. It does not prove planner breadth.

### 3. It does not yet prove action surfaces

The north star includes "create a new deal" and other do-surfaces. This demo is
read-only plus interactive filtering and app-owned simulated mutation.

Action surfaces still need their own safety proof:

- action manifest
- developer-owned validator
- developer-owned handler
- generated confirmation surface
- app-owned execution

That should remain deferred until read/refine workspaces are credible.

### 4. It does not yet prove capability manifests

The plan uses tool calls directly as section sources. That is acceptable for
the v2.5 layer, but the planner eventually needs a richer capability manifest:
data capabilities, interaction capabilities, patterns, and action capabilities.

Without that, planner mode risks becoming "LLM picks primitive names" instead
of "intent projects a workspace from product capabilities."

### 5. It does not yet prove cross-section intelligence

The current sections are coherent, but they are not deeply aware of each other.
The summary summarizes one source, not the assembled workspace. The trend does
not drive the focus list. The focus list does not open a workspace-scoped detail
panel.

Those are later workspace behaviors. The current proof is structural, not yet
relational.

## The refined thesis

The demo clarifies the v3 thesis:

> Resonance should not generate UI. Resonance should project typed workspaces
> from application capabilities, then compile those workspaces into Phoenix
> surfaces the application knows how to run.

That sounds like a small wording change. It is not.

"Generate UI" points toward arbitrary components, visual novelty, and prompt
fragility.

"Project typed workspaces" points toward:

- constrained plans
- deterministic compilation
- developer vocabulary
- stable identity
- rerun and refinement
- app-owned runtime semantics

The second framing is the product.

## Why this is not just a prettier dashboard router

A dashboard router has prebuilt destinations. The model's job is to pick which
destination the user probably meant.

The current v3 path is different. It can represent the surface itself as data:
which sections exist, what roles they play, what sources feed them, which
patterns they use, and how their identities survive refresh.

The CRM demo still uses one hand-written plan, so it is not yet a full adaptive
workspace system. But it proves that a workspace can be compiled from a plan
rather than hand-coded as a page.

That is the crack in the wall.

Once planner mode emits valid plans, the same compiler can produce different
workspaces from different user intents. At that point Resonance is no longer
choosing between dashboards. It is projecting a workspace from the application's
capability field.

## Practical conclusion

The v3 implementation has proven the load-bearing middle layer:

- `WorkspacePlan` is the right primary IR.
- The compiler can target existing Renderables and Widgets.
- Stable workspace identity is workable.
- Snapshots and reruns can work without LLM regeneration.
- Phoenix can remain the runtime.
- Resonance can avoid owning app data, app persistence, and mutations.
- v1/v2 APIs can survive underneath v3.

The thesis is not fully validated yet.

The next decisive proof is planner mode:

```text
user intent
  -> valid WorkspacePlan
  -> deterministic compile
  -> working workspace
```

The success bar should be unforgiving. If planner mode cannot reliably emit
valid, useful plans against a capability manifest, then v3 collapses back into
dashboard routing. If it can, Resonance becomes something more interesting: a
runtime for user-shaped product surfaces.
