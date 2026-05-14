# After the Page

> A developer's guide to building web applications when the user's intent,
> not the team's guess, picks the surface.

## A page is a guess

Every page in your app is a bet.

Someone on the team thought: a user in this situation will need this view,
in this layout, with these affordances, so the team built that page. Most
pages get traffic; some don't. The good guesses get used; the bad guesses
become dead-link archaeology.

This is the inheritance from desktop software. It made sense when the cost of
misreading a user was an unused screen. It made less sense once apps had a
hundred screens and users could only find seven. It makes much less sense now
that the cost of misreading is invisibility. The user opens your app, doesn't
see what they came for, and switches to a tool that gets out of the way.

Resonance is built on the premise that this shape of work is ending. AI
doesn't write the page in this view; it plans the page. You ship the grammar
it's allowed to plan inside.

## What the page concealed

Pages weren't really the product. They were one expression of it.

Underneath every page in your Phoenix app is the real surface area: the data
the application owns, the operations it permits, the constraints those
operations honor, the authorization scopes that gate them, and the UI patterns
the team has chosen to render results.

Take any noun in your app. A `Deal` probably has a list view, a show view,
an edit form, and a few special-case pages like `ArchiveStaleDealsLive`.
Each one is a bet on which slice of the same data will get used,
pre-bundled into a route before the user shows up.

Pages don't get harder to write. They stop being the unit of work. The unit
of work becomes the grammar itself, the declared surface area, written once,
against which any plan can compile.

## The shift, in one move

Resonance proposes a small architectural insertion with a large consequence:

```text
user intent
  → planner (LLM)
    → WorkspacePlan (typed value)
      → validation against your Manifest
        → deterministic compile
          → Renderables
            → Phoenix LiveView mounts the surface
```

Most of this chain is *glass*: typed, deterministic, debuggable,
snapshotable, replayable. Exactly one step is *opaque*, the planner, and it
sits in the same position a query optimizer sits in a SQL database: a learned
mechanism doing the matching, surrounded by glass on both sides.

The compiler is the load-bearing object. The planner sits above it.

The planner emits a plan. The compiler binds the plan to your app's actual
operations and patterns. The plan is a value: you can store it, diff it,
snapshot it, rerun it tomorrow against fresh data with no model call. That
part is shipped. The reads side of it works end to end.

Resonance composes the surface. Phoenix renders it.

That sentence is the architectural commitment. Resonance does not invent a
runtime, generate HEEx, or own your persistence layer. It composes the
surface from your declared grammar and hands it back to Phoenix to mount.

## CRUD didn't go anywhere

A reasonable concern at this point. *"So I declare a grammar and the model
invents some surface and renders it. Doesn't that mean the model is doing my
data layer? What happens to schemas, changesets, contexts?"*

They stay. All of them.

CRUD is still the base calculus: `Create`, `Read`, `Update`, `Delete`, over
resources owned by Phoenix contexts, persisted by Ecto, gated by authorization
scopes you wrote. Nothing in that stack is replaced.

What changes is who decides which CRUD operation gets the user's screen real
estate at this moment.

Today, you decide. You build `ArchiveStaleDealsLive` because someone in last
quarter's roadmap meeting said sales ops wanted it. The route exists. The
page exists. The grammar of what "archive stale deals" *means* (which deals
are stale, what archive does to a record, who's allowed to perform it, what
confirmation is required, what the reversibility story is) exists too. It's
just buried inside the LiveView, the context function, the changeset, the
policy, the seeds. The page is the only surface where that grammar is
addressable.

In the planned-surface world, that grammar moves out of the LiveView and
into the Manifest. The page becomes one of several surfaces the same grammar
could project, alongside an ad-hoc workspace a sales lead asks for at 4pm on
a Tuesday before the team has built a route for it.

Domain verbs like `archive_deal`, `refund_invoice`, `approve_request`, or
`escalate_ticket` are *named compositions* of CRUD plus constraints plus
confirmations plus patterns. The substrate is unchanged; the addressability
changes.

## What you author: the Manifest

The Manifest is the artifact that didn't exist before.

It is the declaration of what your application can do, written in a form the
planner can read: a typed catalog with six layers.

**1. Resources.** The nouns: `Deal`, `Account`, `Contact`, `Invoice`. Not
necessarily one-to-one with database tables; `StaleDeal` and `AtRiskRenewal`
may be named read shapes over the same `Deal` table. Each resource declares
the fields safe and meaningful to expose, which is usually narrower than the
schema's full surface.

**2. Read shapes.** What the resource supports being asked about. Today's
five semantic primitives (`compare_over_time`, `rank_entities`,
`show_distribution`, `summarize_findings`, `segment_population`) are typed
read operations over declared resources. A plan that asks `rank_entities`
against `deals` by a measure your app never declared fails at validation,
before anything renders.

**3. Mutation shapes.** Create, update, delete, with their boundaries
declared: allowed parameters, validations, authorization scope, confirmation
requirements, reversibility, side effects, after-state. In Phoenix, your
changesets and context functions already encode most of this. The Manifest
doesn't bypass them; it advertises them. (Worth flagging up front: read
workspaces are proven today. Mutation surfaces are the next frontier, not a
current claim.)

**4. Constraints.** The old web's hidden skeleton, made explicit: changeset
validations, database constraints, authorization policies, tenant scope,
idempotency, audit requirements, confirmations, irreversibility gates. They
keep the model from planning *outside* your operating envelope.

**5. Patterns.** The surface-level shapes your app knows how to render:
`record_list`, `detail_panel`, `bar_chart`, `trend_panel`, `metric_strip`,
`prose_summary`, `entity_list`. Each pattern declares what kinds of results
it can present and which interactions it supports. The model does not write
HEEx. The model picks a pattern; the compiler binds the pattern to your
function components and LiveComponents.

**6. External capabilities.** MCP tools, HTTP endpoints, SDK calls,
background jobs: admitted into the grammar one at a time, each annotated
with which product operation it implements. A capability the app hasn't
admitted does not exist as far as the planner is concerned.

A small concrete shape (illustrative, not the final API) to anchor what this
looks like in code:

```elixir
# illustrative Manifest fragment
resource :deal do
  fields do
    field :name,        :string
    field :stage,       :enum, values: [:qualified, :proposal, :negotiation, :closed]
    field :owner_id,    :user_ref
    field :value_cents, :money
    field :closed_at,   :datetime, nullable: true
  end

  measures   [:count, :sum_value, :avg_value]
  dimensions [:stage, :owner, :closed_at, :region]
  filters    [:stage, :owner, :closed_at]
end

operation :archive_deals do
  crud      :update
  resource  :deal
  updates   [:archived_at]

  accepts_many           true
  requires_confirmation  true
  reversible_with        :restore_deals

  validate_with CRM.Deals, :archive_changeset
  perform_with  CRM.Deals, :archive_deals
end

primitives [:rank_entities, :segment_population,
            :compare_over_time, :summarize_findings]

patterns   [:bar_chart, :trend_panel, :entity_list,
            :data_table, :prose_summary]
```

The Manifest is the application as the planner sees it. It is also,
increasingly, the application as new humans on your team should see it
first, because it's where the answer to *"what does this product actually
do"* lives in one place, in one language.

## MCP, and where the "P" goes

A useful clarification on naming.

MCP, the Model Context Protocol, is a standard worth using. It solves one
specific problem: how a tool exposes itself to a model. Resources, tools,
prompts, catalog-style handshakes. We're for it.

MCP is the wire format for *"here is a tool you can call."* It is not a
product grammar. A model that can call an MCP tool can do something. A model
that can plan a safe, app-native surface needs more than that. It needs to
know which tools the app has admitted into its product, which operations
require confirmation, which patterns can render which results, what the
audit trail looks like, what the after-state should show.

This is where Resonance fits, and where the naming **MPC** becomes
deliberate, not a typo. Three pieces:

- **M: Manifest.** What the app has declared it can do. Resources, read
  shapes, mutations, constraints, patterns, admitted external capabilities.
  The developer's artifact.
- **P: Plan.** What this user needs, this moment. A typed `WorkspacePlan`
  the planner emits, validated against the Manifest.
- **C: Compile.** The deterministic step from plan to surface. Resonance
  walks each section, resolves the source through your Resolver, hands the
  Result to a Presenter, stamps a stable identity, and emits Renderables
  Phoenix will mount.

MCP sits one layer under that. An MCP server exposes tools; the app admits
selected tools into its Manifest; the planner maps intent onto admitted
capabilities; the compiler binds the plan to runtime.

The wrong picture is:

```text
user intent → model picks MCP tool → tool runs
```

That's a tool picker. A demo. A parlor trick with an API key.

The right picture is:

```text
user intent
  → plan
    → validation against admitted capabilities
      → preview or confirmation when needed
        → app-owned execution
          → workspace result + audit trail
```

That's a product surface.

If MCP standardizes how capabilities are *exposed*, MPC standardizes how
capabilities become *safe, app-native, addressable surfaces.*

## What Phoenix becomes

The good news for a Phoenix developer: nothing in Phoenix has to change. The
roles of the primitives shift, but no abstraction is replaced.

**Contexts remain the operation boundary.** They were already the right
place for `CRM.Deals.archive_deals/2` and `Billing.Invoices.refund_invoice/3`.
They stay there. The Manifest points at context functions. Schemas and
LiveView events are left alone. The rule that LiveViews translate
interaction and contexts own business logic survives intact.

**Ecto schemas remain the persisted shape.** Changesets remain the
create/update contract for external input. The Manifest can eventually
consume changeset metadata to surface fields, validations, and constraints
to the planner, but you keep authorship of what's product-meaningful.

**LiveView becomes a runtime host for planned workspaces.** A route like
`/workspace` or `/accounts/:id/workspace` doesn't ship pre-decided sections;
it shows whatever the plan, given this user's intent and scope, compiled
into. Lifecycle, PubSub subscriptions, URL state, form events, authorization
re-checks, persistence hooks: Phoenix owns all of it. Resonance owns plan
validation, compile, renderable identity, and snapshot shape.

**Function components and LiveComponents become pattern implementations.**
A `record_list` pattern compiles to a LiveComponent. A `metric_strip`
compiles to function components. A `bulk_editor` may combine both. The
planner doesn't pick HTML. The planner picks a pattern. The app decides how
that pattern becomes Phoenix code.

**Routes change status.** They don't disappear. They become stable entry
points for hosts, saved workspaces, canonical resources, and promoted
workflows. The shift is that not every useful surface needs a route before
a user can ask for it.

Phoenix is still running the application. Resonance is filling a missing
seam (the one between user intent and the app's declared grammar) and
getting out of the way.

## A day building a feature

Concretely. Sales ops asks: *"Can we see at-risk renewals for the next 60
days, grouped by owner, with a panel that shows the recent activity on each
one?"*

In the page-centric world, someone first has to anticipate the request
before any user makes it. The team plans, builds, routes, and maintains
a screen for that anticipated need. With modern coding tools, the build
itself can be quick; the structural cost is the anticipation, the
maintenance, and the fact that each variation on a noun needs its own
screen.

In the planned-surface world, you check whether the grammar already covers
it. You almost always find that it does: `renewals` is a declared resource,
`at_risk` is a declared filter, `rank_entities` and `summarize_findings`
over admitted measures already exist, the `entity_list` and `detail_panel`
patterns already render this shape. The user can ask. The plan compiles.
Done.

When the grammar *doesn't* cover it, that's where your work lives. The
renewals dataset isn't admitted; you admit it. The "at-risk" measure has
product-meaningful definitions in your team's head but no formal one; you
write it. The detail-panel pattern doesn't yet know how to render activity
timelines; you teach it. Each of those changes lives in one place, ships
once, and instantly becomes available across every workspace any user can
ask for.

You're still building the application. You're no longer building five
hundred slightly-different LiveViews for permutations of the same five
concepts.

## What gets easier, what gets harder

**Easier:**

- The long tail. Every workspace a user could plausibly want but isn't
  worth a page-week of effort. Free.
- New surfaces over old data. The expensive part of *"we should have a view
  of X by Y"* has moved from building the view to getting Y declared
  cleanly.
- Removing dead surfaces. Routes you no longer need don't have to be
  maintained because they don't exist; the user-generated workspace
  replaced them.
- Onboarding. The Manifest is a single artifact a new engineer reads to
  understand the application's actual surface.

**Harder:**

- Declarative discipline. The Manifest is read by a planner that has to
  make decisions from it. Vague resource names, missing measures,
  undocumented constraints used to surface as awkward LiveView bugs. Now
  they surface as workspaces the planner couldn't produce, or worse, plans
  that the planner produced but you wouldn't have.
- Cross-surface invariants. When every screen is hand-authored, you can
  hand-enforce things like *"always show the revenue caveat on this view."*
  In the planned world, that caveat lives in a constraint or pattern, not
  in a template. You write it once, and you have to know to write it.
- Performance reasoning. A planner can compose patterns that hit your
  resolver harder than any hand-authored page would have. Your resolver
  has to be honest about what it costs to answer.
- Pattern vs primitive discipline. Patterns are how things look;
  primitives are what they mean. The Manifest forces precision about which
  is which; the precision is good, but it requires taste you used to be
  able to defer.

If you've worked with strongly-typed APIs or schema-first development,
this will feel familiar. You trade implementation flexibility for
declarative leverage. It's the same trade, applied one layer up, at the
product grammar rather than the data grammar.

## From workspace to route

A reasonable next question. *"If everything is generated, are routes
meaningless?"*

No. Generated workspaces have a promotion path.

A workspace begins as an ephemeral surface: one user, one intent, one
session. If it's useful once, it stays useful. The user (or the team) can
save it. The same plan, snapshot-stored, becomes a stable artifact they can
return to and share. If a saved workspace gets used widely, it earns a
route. If the route gets stable enough that it deserves an opinionated
layout the planner shouldn't be allowed to vary, it becomes a hand-authored
page over the same grammar.

```text
ad-hoc surface
  → saved workspace
    → shared workspace
      → promoted workflow
        → authored page
```

This is what page-as-unit-of-work hid: pages were always hardened
workspaces. We just had no way to know which workspaces deserved the
hardening until users had been asking for them. Now they tell us, by what
they ask for and how often.

The surface area of your app comes to reflect what people actually do with
it, rather than what the team predicted at planning time.

Workspaces become pages.

## The role moves up

The fear in any *"AI does the thing"* conversation, for developers, is that
the thing moves up the stack and the role stays where it was. Which means
the role gets smaller.

That isn't the shape here.

The grammar still has to be authored. The contexts still own correctness.
The changesets still own validation. The authorization scopes still own
safety. The patterns still embody the team's taste about how this kind of
result should look. The constraints still encode the irreversibility and
audit requirements that protect users from the planner's enthusiasm.

What changes is *which decisions get made by whom.*

- Routing decisions (*"does this user need a screen for X?"*) move from the
  developer to the user.
- Layout decisions (*"primary panel, supporting detail, summary up top"*)
  move from the developer to the planner, inside a pattern set the
  developer authored.
- Composition decisions (*"when X and Y are both relevant, show them like
  this"*) move to the planner, inside constraints the developer wrote.
- Schema, business logic, authorization, validation, security, runtime
  behavior, observability, performance: all stay with the developer,
  unchanged.

Reading this as *"developers do less"* misses the actual shift. Developers
do less of the busywork and more of the work that was always the actual
job. Choosing what to admit, what to name, what to expose, what to gate,
what is safe to vary, what must never vary: that is the engineering.
Resonance is asking developers to do that work in *one place,
deliberately,* instead of scattering it across two hundred hand-authored
screens.

The job becomes more like writing a strongly-typed API for a planner, and
less like writing a hundred views over the same five concepts. If you
liked Phoenix because it made the boring parts boring, you'll like this.
The same instinct, applied to a layer that was previously all manual.

## What we're claiming, and what we're not

This is a thesis document, so it's worth being precise about what's
shipped versus what's argued.

**Shipped, in v3:** the `WorkspacePlan` typed IR, the deterministic
compiler, the snapshot/rerun path, a planner that emits valid plans against
a CRM grammar with single-retry recovery on validation failure, and a
complete end-to-end demo where a hand-authored plan compiles into a working
Phoenix workspace. The read side of the architecture, end to end.

**Argued, not yet shipped:** the full Manifest abstraction over arbitrary
apps, mutation and action surfaces (create/update/delete with preview and
confirmation), workflow surfaces that compose multiple operations, the MCP
admission path, the saved-workspace promotion path to routes, and the
pattern kit broad enough for general application work.

The thesis is that the architectural seam works: that a typed plan can sit
between user intent and Phoenix surface, that the compiler is the
load-bearing object, that the planner can be opaque without compromising
the surface. The next frontiers are scope, not soundness.

## The closing argument

The web grew up writing pages.

A page is a useful fiction. It compressed a lot of decisions into a single
artifact: what data appears, in what order, with what affordances, for
whom, when. For most of web development's history, that compression was
unavoidable. The user had no way to ask for anything else, and the team
had no way to project anything else.

Both of those things have changed. The user can ask. The team can declare.
A typed plan can sit between them. A deterministic compiler can bind the
plan to the application's actual operations.

The work that produces a useful, safe, fast web app looks like this:

```text
1. Build the application normally: contexts, schemas, changesets, scopes.
2. Declare its grammar: resources, reads, mutations, constraints, patterns.
3. Let the planner map user intent into the grammar.
4. Let the compiler bind plans to surfaces.
5. Promote the workspaces users actually use.
```

That's the work. It's smaller than building five hundred screens and larger
than writing prompts, centered on the thing developers were always best at:
encoding a domain so cleanly that other software can use it correctly.

Build the app. Expose the grammar. Let intent find its surface.

---

*Companion reading: [`v3-developer-grammar.md`](../design/v3-developer-grammar.md)
for the longer architectural thesis behind this document.
[`marketing/index.html`](./index.html) for the slide-deck form of the same
argument. [`v3-thesis-results.md`](../design/v3-thesis-results.md) for what
the current implementation does and does not prove.*
