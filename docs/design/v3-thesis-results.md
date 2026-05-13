# Resonance v3 Thesis Results: What The Demo Proves

> Status: conclusion from the v2.5 implementation pass. This is not a new
> vision doc. It records what the current implementation proves, what it does
> not prove, and why the remaining v3 work is still worth doing.

Related follow-up: `docs/design/v3-developer-grammar.md` sketches the developer
methodology implied by these results: expose existing web primitives as a
planner-legible product grammar.

## 2026-05-13 real-provider planner update

The real-provider CRM planner eval now passes the v3 thesis test for the
bounded read-only CRM corpus:

```text
12 CRM prompts
  -> Anthropic planner emits create_workspace_plan
  -> JSON-safe WorkspacePlan decoding
  -> validation against CRM capabilities and pattern manifest
  -> WorkspaceCompiler
  -> existing Renderables/Widgets
```

Result: 12/12 valid plans and 12/12 compiled workspaces. One prompt required a
validation-feedback retry and recovered. The corpus includes ten ordinary CRM
asks, one off-the-wall forecast-risk prompt, and one longer board-packet prompt
that emits a larger executive dashboard. The generated artifact is
`docs/design/v3-planner-eval-real-results.md`.

This is the missing half the first demo did not prove. It does not mean the
planner is production-complete for arbitrary apps or action surfaces. It does
prove that, given a structured CRM capability contract, a production LLM can
emit typed workspace plans that validate and compile without prompt-specific
page code.

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

The golden CRM eval currently exercises twelve prompts through planner validation
and compilation, including one weird forecast-risk ask and one long-form board
packet ask that compiles into a larger dashboard. Invalid outputs return
structured validation errors, and one validation-feedback retry is measured by
the harness.

The mocked-provider eval still matters because it proves the contract
deterministically. The real-provider eval proves the contract is usable by a
production model on the CRM corpus. Both are needed: one gives regression
stability, the other gives product plausibility.

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

`Resonance.Live.Workspace` now exists as a separate LiveComponent surface. It
keeps `Live.Report` compatible, owns the workspace lifecycle states
(`:planning`, `:resolving`, `:ready`, `:failed`), calls the planner/compiler,
captures snapshots and follow-up context, supports rerun/save/refine
affordances, ignores a second prompt while busy, and emits workspace planning
and resolving telemetry. Persistence remains app-owned through an optional save
callback or snapshot assigns. The CRM `/workspace` route is now a thin wrapper
around this reusable surface rather than a bespoke compiler harness.

The missing planner proof now has its own artifact:
`docs/design/v3-planner-eval-results.md`. The CRM example app exposes
`/planner-eval`, which runs twelve deterministic CRM planner prompts through
`Planner.plan_result/3`, validation, the workspace compiler, and
`Resonance.Live.Workspace`. Under the mocked-provider contract eval, all twelve
prompts produce valid typed plans and compile, while an intentionally bad
probability-field plan is rejected with actionable validation errors.

A first real-provider attempt found the expected kind of failure: the model used
invented measure names and a non-declared filter shape. That hardened the
boundary. Non-list filters now fail as query-intent validation errors instead of
crashing, resolver modules are explicitly loaded before reading structured
capabilities, and `WorkspaceCompiler.compile/2` validates tool calls against
those capabilities before resolving sections. The eval also no longer counts
section-local error renderables as compiled success.

## The claim under test

The v3 vision made a strong claim:

> Resonance lets a user's intent project a workspace from the application's
> capabilities.

The first hand-written CRM demo did **not** fully prove that sentence. The
real-provider planner eval now proves the bounded read-only CRM version of it.

The implementation first proved the deterministic middle of the sentence: a
typed workspace can be projected from declared product capabilities into a real
Phoenix surface, bound to live application data, with stable identity,
interactivity, and rerun behavior. The planner eval adds the missing front half:
representative CRM user intent can become a valid typed workspace plan.

That is the right thing to have proven first.

If this layer did not work, an LLM planner would only make the failure more
expensive, slower to debug, and easier to mistake for intelligence. The current
demo proves that the non-LLM part of v3 has a coherent shape.

## What exists now

The original CRM demo has a hand-written workspace plan:

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

That gives the planner a firm target. The real-provider eval matters because
the planner was not asked to invent UI; it was asked to emit a valid plan inside
a constrained grammar.

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

### 1. It does not prove arbitrary user intent -> arbitrary workspace plan

The first CRM workspace was hand-written. The planner eval now proves a bounded
stronger path:

```text
CRM user intent -> valid WorkspacePlan -> working workspace
```

That is not the same as proving every possible product intent, every app
domain, or every future workspace behavior. The claim is now narrower and
stronger: within declared app capabilities, the planner can emit valid typed
plans for a representative CRM read-workspace corpus.

The next breadth test is not "can one hand-authored page render?" It is:

```text
new app capability manifest
  -> unfamiliar domain prompts
  -> valid WorkspacePlan
  -> working workspace
```

### 2. It does not yet prove the final zero-prebuilt-page product surface

There is still a `/workspace` route, and `/planner-eval` runs a fixed prompt
corpus. Those routes are demo and evaluation harnesses, not the final interface
model.

The planner eval proves that different prompts can materialize different valid
plans without each workspace being hand-authored. It does not yet prove the
open product experience around discovery, persistence, sharing, navigation, and
repeat use.

The current result makes that product shape plausible because the rendered
surface is derived from the plan. It does not prove the whole workspace product.

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

### 4. It does not yet prove complete capability manifests

The planner now has structured data capabilities and a pattern manifest:
datasets, measures, dimensions, filters, query shapes, roles, patterns, and
primitive compatibility are declared instead of inferred from prose.

That is enough for read-only CRM workspaces. It is not the complete capability
surface. Interaction capabilities, persistence affordances, and action
capabilities still need their own contracts before Resonance can claim the full
v3 product surface.

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

The original CRM demo still uses one hand-written plan, and the planner eval
uses a bounded CRM prompt corpus. So this is not yet a full adaptive workspace
system. But it proves that workspaces can be compiled from plans rather than
hand-coded as pages, and that a production LLM can emit those plans inside the
declared CRM contract.

That is the crack in the wall.

Now that planner mode emits valid plans for the CRM corpus, the same compiler
can produce different workspaces from different user intents. Resonance is no
longer merely choosing between dashboards in this bounded case. It is projecting
a workspace from the application's capability field.

## Practical conclusion

The v3 implementation has now proven both the load-bearing middle layer and the
bounded planner contract:

- `WorkspacePlan` is the right primary IR.
- The compiler can target existing Renderables and Widgets.
- Stable workspace identity is workable.
- Snapshots and reruns can work without LLM regeneration.
- Phoenix can remain the runtime.
- Resonance can avoid owning app data, app persistence, and mutations.
- v1/v2 APIs can survive underneath v3.
- CRM user intent can become valid typed plans under a structured capability
  contract.
- Real-provider validation retry can recover at least one invalid first pass.

The thesis is not fully complete, but it has crossed the important threshold:

```text
user intent
  -> valid WorkspacePlan
  -> deterministic compile
  -> working workspace
```

The remaining work is product breadth and safety, not the core read-workspace
thesis. The next decisive tests should be live exploration quality, persistence
semantics, cross-domain capability manifests, and only later action surfaces.
