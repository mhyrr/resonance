# v3 Planner Eval Results

Date: 2026-05-12

## Claim

Given a user's CRM intent and the app's declared capabilities, Resonance can
produce a valid typed workspace plan that compiles into a working Phoenix
surface without prompt-specific page code.

## Harness

This eval uses the CRM example app's deterministic planner provider:
`ResonanceDemo.PlannerEval.Provider`.

The path under test is the real v3 path:

1. CRM prompt
2. `Resonance.Planner.plan_result/3`
3. `create_workspace_plan` tool output
4. `WorkspacePlan.from_map/2`
5. validation against registered primitives, CRM resolver capabilities, and
   pattern manifest
6. `WorkspaceCompiler.compile/2`
7. renderable workspace preview through `Resonance.Live.Workspace`

The provider is mocked so the eval measures the contract, validation,
compilation, and surface behavior without network variance. A real-provider
benchmark should come after this contract stays green.

For eval purposes, "compiled" means every section produced a non-error
renderable. Section-local error renderables remain valid runtime behavior for
product surfaces, but they are counted as compile failures here because this
test is measuring whether planner output can produce a working workspace.

## Summary

| Metric | Result |
| --- | ---: |
| CRM prompts | 12 |
| Valid workspace plans | 12 |
| Compiled workspaces | 12 |
| Invalid plans | 0 |
| Compile failures | 0 |
| Validation retries | 0 |
| Invented capability failures | 0 |
| Invented pattern failures | 0 |
| Invented primitive failures | 0 |
| Compile rate | 100% |

## Prompt Results

| Prompt | Workspace Sections | Primitives | Status |
| --- | ---: | --- | --- |
| Show me pipeline health by stage and owner. | 3 | `summarize_findings`, `show_distribution`, `segment_population` | compiled |
| Which deals are stuck in negotiation? | 1 | `rank_entities` | compiled |
| Compare this quarter's pipeline to last quarter. | 1 | `compare_over_time` | compiled |
| Give me an account review for top enterprise deals. | 2 | `rank_entities` | compiled |
| What should Alice focus on this week? | 1 | `rank_entities` | compiled |
| Show open pipeline by owner. | 1 | `segment_population` | compiled |
| What does the contact funnel look like? | 1 | `show_distribution` | compiled |
| Where are sales activities getting no response? | 1 | `show_distribution` | compiled |
| Rank the largest deals in the pipeline. | 1 | `rank_entities` | compiled |
| Summarize proposal-stage pipeline. | 2 | `summarize_findings`, `rank_entities` | compiled |
| Which opportunities are the forecast vampires: technically alive, still draining attention, and most likely to embarrass us on Friday? | 3 | `summarize_findings`, `rank_entities`, `segment_population` | compiled |
| Board packet is tomorrow. I need a compact CRM operating dashboard... | 6 | `summarize_findings`, `show_distribution`, `compare_over_time`, `segment_population`, `rank_entities` | compiled |

## Guardrail Check

The eval suite also checks an intentionally bad planner output:

> Show deal probability by owner.

The mocked plan invents `sum(probability)` and a `probability` dimension. The
planner eval records it as an invalid plan with actionable validation errors,
including `:unsupported_measure`. That proves the validator catches invented
CRM fields before the compiler or resolver runs.

## CRM Exploration Surface

The CRM example app now exposes `/planner-eval`.

That page runs the same 12-prompt eval, shows validity/compile metrics,
lets a user select each prompt, inspects the emitted typed plan, and renders the
selected valid plan through `Resonance.Live.Workspace`. It also shows the
invalid probability-field guardrail result so validation failures are visible in
the app, not only in tests. `Run Eval` re-runs the deterministic harness,
increments the visible run counter, updates the timestamp, and remounts the
selected workspace preview. The page code is generic: the prompt corpus and
deterministic provider live in `ResonanceDemo.PlannerEval`; the LiveView renders
result data and does not branch per prompt.

## Real-Provider Hardening

The first real-provider run exposed a useful boundary bug: the model emitted
filters as a map keyed by field name, for example `%{"stage" => %{...}}`,
instead of the declared list of filter maps. `QueryIntent.from_params/1` now
rejects that shape as `{:invalid_field, :filters, "must be a list"}` instead of
raising a function-clause error. Capability-invalid tool calls are also
validated by `WorkspaceCompiler.compile/2` before section resolution when the
resolver exposes structured capabilities.

## Conclusion

This proves the missing contract layer under deterministic provider conditions:
CRM intent can become a valid typed `WorkspacePlan`, validation catches invented
capabilities, and valid plans compile into Phoenix surfaces through the reusable
workspace component.

The next harder proof is a real-provider benchmark over the same 12 prompts. If
that holds, TK-070 action surfaces become a reasonable next experiment. If it
does not, the schema/capability contract needs tightening before actions.

Run that benchmark from the CRM example app with:

```sh
mix resonance_demo.planner_eval.real --allow-paid --json ../../docs/design/v3-planner-eval-real-results.json
```

The task refuses to run without `--allow-paid` or
`RESONANCE_ALLOW_PAID_LLM_EVAL=1` because it calls the configured external LLM
provider and may incur API cost.
