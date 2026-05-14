# Resonance Failure Policy

> Status: v3 baseline policy. This records the intended behavior for the
> semantic report pipeline and the workspace pipeline. Some current behavior
> already matches this; gaps should become implementation tickets.

## Principle

Resonance wraps stochastic planning and app-owned data access, so failures must
be boring.

Every failure should land in one of three buckets:

1. **Pipeline-fatal** - nothing trustworthy can be resolved. The surface shows a
   top-level error and stops loading.
2. **Section-local** - one primitive, result, or section failed. The rest of the
   report/workspace continues, and the failed section renders an inline error.
3. **Validation failure** - a plan or source is invalid before resolution. The
   system returns structured errors; it does not guess, partially execute, or
   silently drop invalid sections.

The user sees a concise failure. The developer gets the precise reason in logs
and telemetry. The library never hides malformed LLM output by inventing a
fallback UI.

## Error Shape

Existing report errors may stay as tagged tuples because v1/v2 APIs already use
them:

```elixir
{:api_error, status, body}
{:request_failed, reason}
{:unknown_primitive, name}
{:invalid_field, field, message}
{:unsupported_query, dataset}
{:query_failed, message}
{:internal_error, message}
{:task_exit, message}
```

New workspace validation should return a structured list:

```elixir
{:error, {:validation_failed, errors}}

%{
  path: [:sections, "stuck_deals", :source],
  code: :invalid_source,
  message: "section source must be {:tool_call, %Resonance.LLM.ToolCall{}}",
  details: %{received: source}
}
```

Rules:

- `:code` is stable and machine-readable.
- `:message` is developer-readable and safe to show in a debug surface.
- `:path` points to the smallest invalid plan field.
- `:details` is optional and for logs/tests, not user-facing copy.
- Validation errors accumulate where possible. A planner retry needs the whole
  correction set, not one drip-fed error at a time.

## Current Report Pipeline

Current behavior:

- `Resonance.Pipeline.run/3` emits `{:error, reason}` when the LLM call or
  outer pipeline task fails.
- `Resonance.Pipeline.resolve/3` reruns stored tool calls without the LLM and
  emits the same resolution events.
- `Resonance.Composer.resolve_one/2` turns unknown primitives and resolver
  errors into error Renderables.
- `Resonance.Live.Report` shows pipeline errors as a top-level banner and
  component errors inline.
- Primitive resolution is telemetry-wrapped; LLM/generate paths already emit
  telemetry spans.

Target behavior:

- Keep the split: pipeline-fatal errors become top-level surface errors;
  primitive/result errors become inline error Renderables.
- Preserve partial success. One failed primitive should not cancel unrelated
  sections.
- Log the primitive name and arguments for section-local failures.
- Emit telemetry for each phase that can materially affect latency or adoption:
  LLM call, plan validation, primitive/section resolution, presenter compile,
  and workspace rerun.

## Failure Matrix

| Failure | Current user behavior | Target user behavior | Developer signal |
|---|---|---|---|
| LLM returns malformed or unparseable response | Provider-specific parsing usually returns no tool calls or request failure; Live.Report may show a top-level provider/request error. | Top-level error: the request could not be planned. No resolution. | Log provider, parse reason, truncated response metadata; telemetry `[:resonance, :llm, :call]` with error. |
| LLM returns no tool calls | Providers log a warning and return `{:ok, []}`; the report can complete empty. | Top-level empty-plan error for report/workspace generation. Empty output is not success unless the caller explicitly allows it. | Warning with truncated assistant text and prompt metadata. |
| LLM returns tool calls for unknown primitives | Error Renderable for that primitive; other primitives continue. | Same for reports and workspaces: section-local error. | Warning with primitive name; telemetry resolution event tagged error. |
| LLM returns valid primitive names but unsupported fields | Resolver validation or query intent parsing returns `{:error, reason}`; error Renderable. | Same for reports. Workspace planner mode should catch obvious source/shape errors in plan validation before resolution. | Validation error path and source args in logs/tests. |
| Resolver returns partial data | No explicit contract today beyond whatever resolver returns. | Resolver should either return `{:ok, data}` plus metadata when partial results are intentional, or `{:error, reason}` when the section is not trustworthy. Resonance should not infer partial correctness from arbitrary rows. | Future Result metadata should carry partial flags/counts; until then, log resolver-provided error reason. |
| Resolver returns error | Error Renderable for that primitive. | Same: section-local error. Other sections continue. | Warning with primitive name and arguments. |
| Presenter cannot render Result kind | May raise, which is caught by the primitive task and surfaced as crashed/unknown error Renderable. | Section-local compile error with presenter, result kind, and reason. No crash should escape the section boundary. | Error log plus telemetry for presenter compile once that phase is explicit. |
| Provider is down, rate-limited, unauthorized, or times out | Top-level error banner via `{:api_error, status, body}` or `{:request_failed, reason}`. | Same. The surface must stop loading and keep prior stable content if it is a rerun/refinement. | Error log with provider/status/reason. No secrets in logs. |
| LiveView reconnects mid-generation | Current in-flight task may finish against the old component process; new mount loses transient state unless parent/app stores it. | Live.Report may remain transient. Live.Workspace must be snapshot-backed for saved workspaces and tolerate reconnect by rerunning from stored plan/tool calls. | Telemetry can record rerun/reconnect later; no hidden server state dependency for saved workspace recovery. |
| User fires two queries before the first resolves | Live.Report disables its own prompt while loading, but parent-driven `set_prompt`/`regenerate` can still race. | Each generation should carry a run id. Newer runs win; stale events are ignored. Until run ids land, parent surfaces should avoid concurrent sends. | Debug log when stale events are dropped. |
| Workspace plan has invalid layout/sections/source | Not implemented. | Validation failure before resolution: `{:error, {:validation_failed, errors}}`. No sections execute. | Structured errors with `path`, `code`, `message`, optional `details`. |
| Workspace section source resolves but result cannot compile | Not implemented. | Section-local error for that section. Other sections continue if their sources are valid. | Error tagged with workspace id, section id, source, and presenter/pattern. |
| Workspace rerun source is stale or cannot resolve | Not implemented. | The workspace remains the same workspace. Failed sections render inline errors; successful sections update in place. | Rerun telemetry tags workspace fingerprint and section ids. |

## Workspace Rules

Workspace execution adds one rule the report pipeline did not need:

> Validate the whole plan before resolving any section.

That means:

- Duplicate section IDs fail validation.
- Unknown layouts, roles, patterns, and source types fail validation.
- A source that is not `{:tool_call, %Resonance.LLM.ToolCall{}}` fails in
  Phase 1.
- Validation failure is not partial success. It returns structured errors and
  does not call resolvers.
- Resolution/compile failures after validation are section-local unless they
  indicate the whole runtime is unavailable.

## User-Facing Copy

Default user copy should be plain and non-technical:

- Pipeline-fatal: "Something went wrong while planning this report."
- Provider/network: "Could not reach the LLM provider."
- Empty plan: "I could not find an analysis to run for that request."
- Section-local: "This section could not be loaded."
- Workspace validation: "This workspace plan is invalid."

Detailed reasons belong in developer surfaces, logs, telemetry, and tests.

## Implementation Notes

- Do not add LLM-emitted HEEx as a fallback for presenter or pattern failures.
- Do not silently drop invalid sections.
- Do not convert user/provider strings into atoms.
- Do not let planner retry logic mutate the contract. Retry receives
  structured validation errors and must return the same typed plan shape.
- `Resonance.Live.Workspace` should have explicit states: planning, validating,
  resolving, ready, failed.
