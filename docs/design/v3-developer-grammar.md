# Resonance v3 Developer Grammar: Building For Planned Surfaces

> Status: first-pass thesis artifact. This is not an implementation spec yet.
> It names the developer methodology implied by the v3 planner/compiler work:
> how a Phoenix-style application should be authored when user intent can become
> a planned surface at runtime.

## The Claim

The future of web application development is not "models replace HTML" and it
is not "developers stop building interfaces."

Developers still write templates, components, widgets, contexts, changesets,
queries, policies, routes, handlers, and tests. The change is where the product
meaning lives.

Today, most of that meaning is implicit. It is scattered across routes,
controllers, LiveViews, templates, Ecto schemas, context functions, changesets,
authorization checks, and the product team's memory.

Resonance asks the developer to make that meaning explicit as a grammar.

```text
old web:
  resources + controllers + templates
  -> pre-authored pages
  -> user navigates what the team anticipated

planned-surface web:
  resources + CRUD operations + workflows + constraints + patterns
  + external capability catalogs
  -> declared product grammar
  -> model emits a plan
  -> Resonance compiles the surface
  -> user works inside what the moment requires
```

The web primitives do not disappear. They become planner-legible.

MCP fits this frame as a capability-source protocol, not as the whole product
grammar.

An MCP server can expose resources and tools. Resonance can treat those as
importable capabilities, alongside app-local resources, context functions,
patterns, and affordances. The planner should not see "anything the MCP server
can call." It should see the subset the app has admitted into its product
grammar.

## What We Have Proved

The v3 work has proven the middle layer:

```text
user intent
  -> WorkspacePlan
  -> validation
  -> deterministic compile
  -> Renderables / Widgets
  -> Phoenix surface
  -> snapshot / rerun
```

The next question is not whether a model can emit a plan. It can.

The next question is what developers must author so plans can become useful,
safe, app-native surfaces across many domains.

That answer is not a new set of verbs. It is the old set made explicit:

```text
Create
Read
Update
Delete
```

CRUD is the base calculus. Domain actions are named compositions of it.

`archive_deal`, `refund_invoice`, `approve_request`, `assign_owner`, and
`escalate_ticket` are not primitive verbs in the substrate. They are product
names for creates, reads, updates, deletes, constraints, side effects, and
confirmations.

That matters because Resonance should not become a narrow CRM framework, admin
framework, workflow framework, or internal-tools framework. It should provide
the grammar substrate those frameworks can build on.

For external workflows and functions, MCP is the useful corollary. It is a tool
bus and catalog, not a replacement for the grammar:

```text
MCP resource        -> possible read shape / external resource
MCP tool            -> possible operation / workflow step
Resonance manifest  -> admitted product grammar
WorkspacePlan       -> planned read/refine surface
ActionPlan          -> planned transaction / workflow surface
Compiler/executor   -> deterministic binding to app-owned runtime
```

The important word is "admitted." A capability can come from a Phoenix context,
an Ecto-backed resolver, an HTTP API, an SDK, a background job, or an MCP tool.
Resonance should normalize those sources into one planner-facing grammar before
the model plans against them.

## The Developer's New Work

The new work is semantic surfacing.

Developers already know how to build the parts. The new discipline is exposing
what those parts mean:

- what resources exist
- what can be read
- what can be created
- what can be updated
- what can be deleted
- which operations are reversible
- which changes require confirmation
- which constraints must hold
- which patterns can render the result
- which operations may be composed into a workflow
- which external tools or resources are admitted into the grammar

In a Phoenix application, this does not replace contexts, schemas, changesets,
or LiveViews. It gives them a planner-facing contract.

```text
Phoenix context       -> authoritative resource and operation boundary
Ecto schema           -> persisted shape
Ecto changeset        -> create/update contract for external input
Policy/scope          -> authorization boundary
Resolver              -> read/query capability
LiveComponent/widget  -> interactive pattern
Function component    -> render kit
LiveView              -> runtime host
Resonance manifest    -> planner-facing grammar
MCP server            -> optional external capability source
WorkspacePlan         -> planned surface value
Compile               -> deterministic binding to app UI
```

The developer is not writing less important code. The developer is writing code
with a second audience: the planner.

## MCP And Capability Catalogs

MCP is closest to an API catalog for tools and resources. That is useful, but it
is one layer too raw for Resonance to plan against directly.

An MCP tool might say:

```text
name: create_deal
input_schema: name, account_id, value, stage
```

That is callable. It is not yet a safe product affordance.

The Resonance grammar still needs to know:

- whether the operation is create, update, delete, or a higher workflow
- who may run it
- whether it requires confirmation
- whether it supports dry-run or preview
- whether it is reversible
- what audit record should exist
- which UI pattern can render input, preview, validation errors, and result
- what workspace context should be shown before and after execution

So the mapping should be:

```text
MCP exposes tools.
The app admits selected tools into its Resonance manifest.
The planner maps user intent onto admitted capabilities.
Resonance validates and compiles the surface.
The app executes through its runtime boundary.
```

That makes Resonance feel like an extension of MCP in the product direction:
MCP standardizes how tools are exposed; Resonance standardizes how tools,
resources, UI patterns, and affordances become safe, app-native surfaces.

The wrong version is:

```text
user intent -> model chooses MCP tool -> tool runs
```

That is a tool picker.

The right version is:

```text
user intent
  -> WorkspacePlan / ActionPlan
  -> validation against admitted capabilities
  -> preview or confirmation when needed
  -> app-owned execution
  -> workspace result and audit trail
```

That is a product surface.

## The Grammar

A useful grammar has six layers.

### 1. Resources

Resources are the nouns of the application.

They are not necessarily one-to-one with database tables. A `Deal`, `Account`,
`Contact`, `Invoice`, `Ticket`, or `Task` may map directly to a table. A
`StaleDeal`, `AtRiskRenewal`, or `UnansweredActivity` may be a named read shape
over existing tables.

The planner does not need every schema field. It needs the fields and concepts
that are safe, useful, and meaningful for users.

```elixir
# illustrative, not current API
resource :deal do
  label "Deal"
  description "A sales opportunity moving through the pipeline."

  identity :id

  fields do
    field :name, :string, readable: true
    field :stage, :enum, values: [:qualified, :proposal, :negotiation, :closed]
    field :owner_id, :user_ref
    field :value_cents, :money
    field :archived_at, :datetime, nullable: true
  end
end
```

This is not a second schema system. It is a planner-facing description of the
product concept.

### 2. Read Shapes

Read is broader than `show` and `index`.

A user rarely asks for a table because they want a table. They ask for a table
because they need to inspect, compare, filter, rank, audit, explain, or decide.

The grammar should name the readable shapes the application supports:

```text
list deals
inspect one deal
rank deals by value
segment deals by stage
compare pipeline over time
summarize unanswered activities
show account timeline
```

This is where today's Resonance primitives already fit. They are not arbitrary
UI blocks. They are typed read operations over declared resources.

### 3. Mutation Shapes

Create, update, and delete are planner-legible only when their boundaries are
declared.

For each operation, the app must expose:

- allowed parameters
- required fields
- validation rules
- authorization scope
- confirmation requirements
- reversibility
- side effects
- after-state

In Phoenix, changesets and contexts already encode much of this. Resonance
should not bypass them. It should make their contracts explicit enough for a
planner to choose the right surface.

```elixir
# illustrative, not current API
operation :archive_deals do
  crud :update
  resource :deal
  updates [:archived_at]

  accepts_many true
  requires_confirmation true
  reversible_with :restore_deals

  describe "Marks selected deals as archived without deleting history."

  validate_with CRM.Deals, :archive_changeset
  perform_with CRM.Deals, :archive_deals
end
```

The planner may plan an archive surface. It may not perform the archive.

Commit still belongs to developer-owned code.

### 4. Constraints

Constraints are not new. They are the old web's hidden skeleton:

- changeset validations
- database constraints
- authorization policies
- tenant scope
- idempotency rules
- audit requirements
- required confirmations
- irreversible-operation gates

The grammar does not replace those boundaries. It advertises them.

The point is not to trust the model. The point is to prevent the model from
planning outside the app's real operating envelope.

```text
The model can propose.
The grammar can validate.
The context can authorize.
The changeset can reject.
The database can enforce.
The user can confirm.
```

Every layer still matters.

### 5. Patterns

Patterns are the surface-level shapes the app knows how to render and operate.

They are not raw HTML atoms. They are mid-level product forms:

- record list
- detail panel
- comparison panel
- metric strip
- timeline
- review queue
- bulk editor
- confirmation surface
- action form
- audit summary

Each pattern should declare what it can support:

```text
record_list:
  works with read shapes returning rows
  supports filter, sort, select, inspect

bulk_editor:
  works with update operations over many records
  requires selection source
  requires preview and confirmation

confirmation_surface:
  works with create/update/delete operations
  shows affected records, irreversible flags, and validation errors
```

This is where good HTML generation becomes useful.

The model can emit excellent HTML, but HTML is not the authority. The authority
is the pattern contract. Generated markup should live inside a known pattern,
bound to declared data and allowed operations, then checked before it becomes a
product surface.

### 6. Workflows

Workflow is the hardest word because it tempts us into building a new workflow
engine.

For Resonance, a workflow should first mean:

> a planned sequence of reads and CRUD operations, with explicit checkpoints,
> rendered as a working surface.

Example user request:

```text
Archive stale deals from last quarter.
```

If the app declares the right grammar, the planner can produce:

```text
1. Read candidate deals where close date is last quarter and activity is stale.
2. Render a review list with selection enabled.
3. Explain why each deal is a candidate.
4. Preview the update: set archived_at.
5. Require confirmation.
6. Submit through CRM.Deals.archive_deals(scope, deal_ids).
7. Render post-action summary.
8. Offer restore if the operation is reversible.
```

No developer hand-authored `ArchiveStaleDealsLive`.

But the developer did author all the important things:

- what a deal is
- how stale deals can be read
- what archive means as an update
- who can archive
- how archive is validated
- whether archive is reversible
- what confirmation must show
- which patterns can render review, preview, and completion

That is the difference.

The model did not invent a business process. It planned a surface over a
declared process grammar.

Some workflow steps may be backed by MCP tools rather than local context
functions. That does not change the rule. The MCP tool is still only a backing
implementation for an admitted operation. The grammar owns the preconditions,
preview, confirmation, audit, and UI affordances.

## What This Means For Phoenix

Phoenix already has the right primitives. The change is how deliberately they
are exposed.

### Contexts Become The Operation Boundary

Contexts should remain the only public place where business operations happen.

The grammar should point to context functions, not schemas and not LiveView
events.

```text
good:
  CRM.Deals.archive_deals(scope, deal_ids)
  CRM.Tasks.create_task(scope, attrs)
  Billing.Invoices.refund_invoice(scope, invoice_id, attrs)

bad:
  Repo.update_all(...)
  Deal |> changeset |> Repo.update from a generated handler
  LiveView event contains business logic
```

This preserves the Phoenix rule: LiveViews translate interaction; contexts own
business logic.

### Changesets Become Planner-Visible Contracts

Changesets already answer the right questions:

- Which fields can external input change?
- Which fields are required?
- Which values are valid?
- Which constraints can fail?
- Which errors should users see?

Resonance should eventually be able to consume changeset-like metadata, but the
developer may still need to annotate what is product-meaningful. Not every
changeset field belongs in the planner grammar.

### LiveViews Become Runtime Hosts

A LiveView no longer has to be the unique authored page for one anticipated
workflow.

It can be a host for a planned workspace:

```text
/workspace
/workspace/:snapshot_id
/accounts/:id/workspace
```

The LiveView owns:

- lifecycle
- connected mount behavior
- PubSub subscriptions
- URL state
- form events
- authorization re-checks
- persistence hooks

Resonance owns:

- plan validation
- compile
- renderable identity
- workspace snapshot shape

That keeps Phoenix running the app instead of making Resonance pretend to be a
runtime.

### Components And Widgets Become Pattern Implementations

Developers still write the UI.

Function components and LiveComponents become the implementation layer behind
patterns. A `review_queue` pattern may compile to a LiveComponent. A
`metric_strip` may compile to function components. A `bulk_editor` may combine
both.

The planner should not care.

The planner sees:

```text
pattern: review_queue
role: primary
source: stale_deals_query
interactions: select, inspect, confirm_update
```

The app decides how that becomes Phoenix code.

### Routes Change Status

Routes do not vanish. They become stable entry points for hosts, saved
workspaces, canonical resources, and promoted workflows.

The difference is that not every useful surface needs a route before a user can
ask for it.

A useful generated workspace can later become:

1. ephemeral surface
2. saved workspace
3. shared workspace
4. promoted workflow
5. authored page

Pages become hardened workspaces.

That is less theatrical than "no pages" and more true.

## CRUD As The Substrate

CRUD is still the correct lowest-level action grammar.

The mistake is treating CRUD screens as the product.

```text
CRUD as screens:
  /deals
  /deals/:id
  /deals/new
  /deals/:id/edit

CRUD as grammar:
  Deal can be listed, inspected, created, updated, archived, restored.
  These operations have constraints, permissions, confirmations, and patterns.
  A planner can compose them into surfaces the team did not prebuild.
```

This is why a lot of business software is a good target. Much of it is already
structured around resources and state transitions. The value is not inventing a
new theory of business actions. The value is making the existing theory
addressable at runtime.

## What Frameworks Can Build On Top

Resonance should stay below domain frameworks.

On top of this substrate, others could build:

- an admin framework
- a CRM framework
- an internal-tools framework
- a customer-support workflow framework
- a reporting workspace framework
- a domain-specific form/workflow builder

Those frameworks can invent higher-level names. Resonance should provide the
lower-level grammar:

```text
resources
read shapes
CRUD operations
constraints
patterns
workflow steps
external tool/resource capabilities
plans
compile
snapshots
```

That is the platform line.

## The Artifact Developers Should Produce

A grammar-native application should have a first-class product grammar
artifact.

It may be code, not a static document. But conceptually it should answer:

```text
Resources:
  What nouns does the product expose?

Read shapes:
  What can be queried, aggregated, ranked, compared, inspected, summarized?

Create:
  Which resources can be created, with which fields and validations?

Update:
  Which fields or state transitions can be changed, singly or in bulk?

Delete:
  What can be deleted, archived, restored, or hidden?

Constraints:
  What must be authorized, confirmed, audited, scoped, or made reversible?

Patterns:
  Which surfaces can render each kind of read or operation?

Composition:
  Which operation sequences are allowed, and where must the user confirm?

External capabilities:
  Which MCP tools, HTTP endpoints, SDK calls, or background jobs are admitted,
  and what product operation does each one implement?
```

That is the methodology.

Not "write prompts."

Not "generate HTML."

Not "replace your Phoenix app."

Write the app normally, then expose its grammar.

## The Resonance Role

Resonance should make this methodology concrete.

The likely product surface is:

```text
Manifest
  The app's planner-facing resource, operation, constraint, pattern, workflow,
  and admitted external capability grammar.

Plan
  A typed value emitted by the model for one user intent.

Compile
  Deterministic binding from plan to app-owned reads, operations, patterns, and
  Phoenix renderables.
```

The current v3 implementation has started with read workspaces because they are
the safe first proof. The next frontier is action surfaces and workflow
composition over CRUD.

The success bar should be concrete:

```text
Given a Phoenix app with declared resources, CRUD operations, constraints, and
patterns, can a user ask for a surface the developer did not hand-author, and
receive a valid workspace that reads, previews, confirms, and commits through
the app's existing context functions?
```

If yes, Resonance is not just a better dashboard generator.

It is a methodology for building web applications whose latent grammar can be
planned against at runtime.

## The Philosophical Line

The old web binds resources to pages ahead of time.

The new web exposes resources and operations as a grammar, then binds them to
surfaces at runtime.

Developers still build the application. They still own correctness, taste,
security, and runtime behavior. What changes is that the application becomes
legible to a planner.

That is the future worth pursuing:

```text
Developers author the grammar.
Users bring intent.
The model plans a valid surface.
The application compiles and runs it.
```
