# Resonance Architecture Review

**Reviewers:** José Valim (language design, OTP patterns, library contracts) and Chris McCord (LiveView, developer experience, Phoenix ecosystem fit)

**Date:** 2026-04-04
**Scope:** Full library + both example apps, every module at function level
**Tests:** 59 passing, 0 failures

---

## Executive Assessment

Resonance has a genuinely good idea at its core: a semantic layer between LLM intent and UI presentation. The five-layer architecture (Primitives → Resolver → Result → Presenter → LiveView) is sound. The finance demo — swapping ApexCharts for ECharts treemaps with zero library changes — proves the abstraction holds weight.

The code is clear, the contracts are mostly right, and the example apps are honest demonstrations rather than contrived showcases. This is a solid v0.1 scaffold.

What follows is everything that needs to happen before this is a library the Elixir community would adopt, trust, and build on.

---

## Part 1: What's Right

### The Semantic Layer Is the Right Abstraction

The decision to have the LLM select `rank_entities` instead of `render_bar_chart` is the load-bearing insight. It decouples model capability from UI capability. The Presenter layer — where the developer decides how truth becomes pixels — is exactly the extension point a library like this needs.

The `Result` struct with its `kind` field is the correct intermediate representation. It carries semantic meaning (`:comparison`, `:ranking`, `:distribution`) without presentation opinion. This is the joint where the library bends without breaking.

### The Behaviour System Is Clean

Four behaviours (`Primitive`, `Resolver`, `Presenter`, `Provider`) define clear contracts. The callbacks have the right signatures. The `@optional_callbacks` on `Resolver` for `describe/0` and `validate/2` is the right call — it lowers the barrier to entry while preserving the extension points.

### The Refresh Mechanism Is Clever

Storing tool calls in `Live.Report` and replaying them against fresh data without re-calling the LLM is both efficient and architecturally revealing. It demonstrates that the LLM's job really is just intent selection — the value is in the resolution pipeline, not the model call. The CRM demo's "Simulate New Deals" button is a compelling proof.

### Two Example Apps, Two Chart Libraries

The CRM demo (ApexCharts, default presenter) and finance demo (ECharts, custom presenter with treemaps) are the strongest argument for the architecture. Same primitives, same resolver contract, completely different visual output. This is what you show people.

### Dependency Discipline

Three runtime deps: `phoenix_live_view`, `jason`, `req`. That's it. No HTTP client abstraction layer, no config library, no telemetry dep (yet — see tickets). This restraint is correct for v0.1.

---

## Part 2: Structural Issues

### S1. Primitive Duplication — The `resolve/2` Pattern Is Begging for Extraction

Four of five primitives (`CompareOverTime`, `RankEntities`, `ShowDistribution`, `SegmentPopulation`) share this identical resolve pattern:

```elixir
def resolve(params, context) do
  resolver = context[:resolver] || context["resolver"]
  with {:ok, intent} <- QueryIntent.from_params(params),
       :ok <- maybe_validate(resolver, intent, context),
       {:ok, data} <- resolver.resolve(intent, context) do
    {:ok, %Result{kind: THE_KIND, title: params["title"], data: data,
                  intent: intent, summary: Result.compute_summary(data)}}
  end
end
```

And every one of them duplicates `maybe_validate/3` identically.

This isn't "premature abstraction" — it's five copies of the same code. The library should provide a helper (either in `Resonance.Primitive` as a `__using__` macro or as a plain function) that handles the common path:

```elixir
# In Resonance.Primitive
def resolve_intent(kind, params, context) do
  resolver = Map.get(context, :resolver) || Map.get(context, "resolver")
  with {:ok, intent} <- QueryIntent.from_params(params),
       :ok <- validate_if_implemented(resolver, intent, context),
       {:ok, data} <- resolver.resolve(intent, context) do
    {:ok, %Result{
      kind: kind,
      title: params["title"] || params[:title],
      data: data,
      intent: intent,
      summary: Result.compute_summary(data)
    }}
  end
end
```

Then each primitive becomes:

```elixir
def resolve(params, context) do
  Resonance.Primitive.resolve_intent(:comparison, params, context)
end
```

`SummarizeFindings` extends this pattern (it adds `build_summary/2` and `metadata`), which is fine — it calls the base and augments.

**Impact:** Eliminates ~80 lines of duplication and makes custom primitives trivial to write.

### S2. `Live.Report.update/2` Is a God Function

The `update/2` callback is ~90 lines of cascading `case` statements, each handling a different update signal:

- `resonance_component` (streaming component arrival)
- `resonance_tool_calls` (store for refresh)
- `resonance_done` (loading complete)
- `resonance_result` (error path)
- `set_prompt` (from parent)
- `regenerate` (from parent)
- `refresh` (from parent)
- resolver/presenter updates

This is a sequential pipeline of "if this key exists in assigns, do this thing." It works, but it's fragile — order matters, and it's easy to introduce bugs when adding new signals.

The fix is straightforward: extract each handler into a named function and pipe through them:

```elixir
def update(assigns, socket) do
  socket
  |> apply_base_assigns(assigns)
  |> handle_streaming_component(assigns)
  |> handle_tool_calls(assigns)
  |> handle_done(assigns)
  |> handle_error(assigns)
  |> handle_set_prompt(assigns)
  |> handle_regenerate(assigns)
  |> handle_refresh(assigns)
  |> then(&{:ok, &1})
end
```

Each function pattern-matches on the relevant key and no-ops otherwise. Readable, testable, maintainable.

### S3. `Composer.compose/2` Uses Bare Tasks, Not the Supervisor

`Live.Report` correctly uses `Task.Supervisor.start_child(Resonance.TaskSupervisor, ...)` for its background work. But `Composer.compose/2` and `compose_stream/2` use bare `Task.async_stream` and `Task.start`. These tasks are linked to the calling process with no supervision.

This means:
- If the calling process crashes, the tasks are orphaned
- No observability into running tasks
- Inconsistent with how `Live.Report` uses the library

Both `compose` functions should use `Task.Supervisor.async_stream_nolink(Resonance.TaskSupervisor, ...)` for consistency and fault isolation.

### S4. Registry Is a Global Singleton Agent

The Agent-based registry works, but it has limitations:

1. **Testing:** Tests must either use the global registry or spawn their own (the test file does this correctly). But library consumers writing tests will trip over it.
2. **Multi-tenancy:** Can't run two Resonance instances with different primitive sets in the same BEAM.
3. **No change notification:** If a primitive is registered after startup, running LiveView processes don't know about it.

For v0.1, this is acceptable. For v0.2, consider ETS (`:ets.new` with `:named_table, :public, read_concurrency: true`). Same API, better concurrent reads, and the data naturally survives process crashes.

### S5. Provider Tests Don't Test the Provider

The Anthropic and OpenAI test modules re-implement the private `extract_tool_calls/1` function locally:

```elixir
# In the test file — this is a COPY, not a call to the real code
defp extract_tool_calls(%{"content" => content}) do
  content
  |> Enum.filter(fn block -> block["type"] == "tool_use" end)
  # ...
end
```

This means the tests verify that the test's copy of the parsing logic works — not the actual provider. If someone changes the real `extract_tool_calls/1`, the tests still pass even if the change is broken.

Two options:
1. Make the parsing functions `@doc false` public and test them directly
2. Test through `chat/3` with a mock HTTP layer (using `Req.Test` adapter or `Bypass`)

Option 2 is better — it tests the full path including HTTP error handling.

---

## Part 3: Contract Clarity Issues

### C1. The Resolver Data Contract Is Implicit

The README says resolvers return "a list of flat maps with at minimum `label` and `value` keys." But the actual shapes vary:

- Basic: `%{label: "...", value: 42}`
- Time-series: `%{label: "...", period: "...", value: 42}`
- Multi-series: `%{label: "...", period: "...", series: "...", group: "...", value: 42}`

These optional keys (`period`, `series`, `group`) are critical for chart rendering, but they're not documented in the `Resolver` behaviour module, not validated by `QueryIntent`, and not specified by type.

The library should define data shape typespecs:

```elixir
@type data_row :: %{
  required(:label) => String.t(),
  required(:value) => number(),
  optional(:period) => String.t(),
  optional(:series) => String.t()
}
```

And the `Resolver` behaviour's `resolve/2` callback spec should reference this type.

### C2. Chart Component Contract Is Undeclared

Chart components must implement:
- `render/1` (standard Phoenix Component)
- `chart_dom_id/1` (optional, for live data push)

But there's no behaviour for this. The Presenter blindly calls `component.render(assigns)`, and `Live.Report` calls `function_exported?(comp, :chart_dom_id, 1)` defensively.

This should be a declared behaviour:

```elixir
defmodule Resonance.Component do
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback chart_dom_id(renderable_id :: String.t()) :: String.t()
  @optional_callbacks [chart_dom_id: 1]
end
```

This gives consuming developers a clear contract when building custom components.

### C3. `describe/0` Is a Free-Text String

The `describe/0` callback returns a plain string that becomes part of the LLM system prompt. The quality of Resonance's output depends heavily on this string matching the actual resolver implementation. But there's nothing that connects them — a typo in `describe/0` output causes the LLM to request invalid fields, which silently fail at resolution.

Short-term: document this clearly as the most common source of bugs.

Long-term: consider a structured `describe/0` that returns a map:

```elixir
%{
  datasets: [
    %{name: "deals", fields: [...], measures: [...], dimensions: [...]}
  ]
}
```

With a `Resonance.Resolver.format_description/1` that renders it into the system prompt string. This would let the library validate that `QueryIntent` datasets match `describe/0` output.

### C4. Context Map Is Untyped

Every function passes `context :: map()`. This map carries `:resolver`, `:current_user`, `:presenter`, and potentially app-specific keys. But there's no typespec or struct for it.

At minimum, define a typespec:

```elixir
@type context :: %{
  required(:resolver) => module(),
  optional(:current_user) => term(),
  optional(:presenter) => module()
}
```

A struct would be stronger, but a typespec is the right v0.1 move.

### C5. `detect_format` Heuristic Is Dangerous

In `Presenters.Default`:

```elixir
defp detect_format(row) do
  value = row[:value] || row["value"] || 0
  cond do
    is_float(value) and value < 1 -> "percent"
    is_number(value) and value > 1000 -> "currency"
    true -> "number"
  end
end
```

A count of 1500 becomes "currency." A ratio of 0.7 becomes "percent." This will surprise users. Format should come from the Result or the Resolver, not be guessed from magnitude.

The `Result` struct should carry an optional `:format` field, or the Resolver's data rows should support a `:format` key. The heuristic can remain as a fallback, but it should be the last resort.

---

## Part 4: Safety and Correctness

### F1. Prose Markdown Renderer Has Latent XSS Risk

`ProseSection.render_markdown/1` uses `Phoenix.HTML.raw/1` after regex-based markdown substitution:

```elixir
inner = paragraph
  |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
Phoenix.HTML.raw("<p>#{inner}</p>")
```

Today this is safe because `SummarizeFindings` generates all the content from templates. But the component is public — any developer could pass arbitrary content to ProseSection via a custom Presenter. The content should be `html_escape`d before markdown transforms are applied:

```elixir
inner = paragraph
  |> Phoenix.HTML.html_escape()
  |> Phoenix.HTML.safe_to_string()
  |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
```

### F2. `normalize_sort` Swallows Atom Creation Failures

```elixir
defp normalize_sort(%{"field" => f, "direction" => d}) do
  %{field: f, direction: String.to_existing_atom(d)}
rescue
  ArgumentError -> %{field: f, direction: :asc}
end
```

If the LLM sends `"direction": "descending"` instead of `"desc"`, this silently defaults to `:asc`. The user gets ascending sort when they asked for descending. This should be an explicit match:

```elixir
defp normalize_sort(%{"field" => f, "direction" => "asc"}), do: %{field: f, direction: :asc}
defp normalize_sort(%{"field" => f, "direction" => "desc"}), do: %{field: f, direction: :desc}
defp normalize_sort(%{"field" => f, "direction" => _}), do: %{field: f, direction: :desc}
```

### F3. No `max_tokens` Default

Both providers use `Keyword.fetch!(opts, :max_tokens)`. If the consuming app configures only `:provider`, `:api_key`, and `:model`, the first LLM call crashes with a `KeyError`. The library should provide a default (4096 is reasonable) or raise a clear error at config validation time.

### F4. No Configuration Validation at Startup

When `Resonance.Application` starts, it only starts the Registry and TaskSupervisor. It doesn't check if LLM provider config exists. The error surfaces only at the first `generate/2` call, which might be minutes later in production.

Add a `validate_config/0` that warns (not crashes) at startup if provider config is missing. Crashing would be wrong — the app should still boot even if Resonance config is incomplete (maybe the developer is only running tests).

---

## Part 5: Ecosystem Readiness

### E1. No Telemetry Events

This is the single biggest gap for ecosystem adoption. Every Elixir library that does I/O should emit telemetry. Resonance should emit:

- `[:resonance, :generate, :start | :stop | :exception]` — full pipeline
- `[:resonance, :llm, :call, :start | :stop | :exception]` — LLM roundtrip
- `[:resonance, :primitive, :resolve, :start | :stop | :exception]` — per-primitive
- `[:resonance, :compose, :start | :stop | :exception]` — composition phase

This gives consuming apps observability without coupling to a specific logging or monitoring system.

### E2. No ExDoc Configuration

For hex.pm publication:

```elixir
def project do
  [
    # ...
    docs: [
      main: "Resonance",
      extras: ["README.md", "docs/design_doc.md"],
      groups_for_modules: [
        "Behaviours": [Resonance.Primitive, Resonance.Resolver, Resonance.Presenter, Resonance.LLM.Provider],
        "Primitives": ~r/Resonance.Primitives/,
        "Components": ~r/Resonance.Components/,
        "LLM": ~r/Resonance.LLM/
      ]
    ]
  ]
end
```

### E3. No `@derive Jason.Encoder` on Core Structs

`Result`, `QueryIntent`, `Renderable`, and `ToolCall` should derive `Jason.Encoder`. This enables:
- Saved reports (v0.2 roadmap item)
- API endpoints returning Resonance output
- Debugging (serializing to logs)

Add this now to avoid a breaking change later.

### E4. `SummarizeFindings` Uses Its Own `format_number` Despite `Resonance.Format` Existing

```elixir
# In SummarizeFindings
defp format_number(n) when is_float(n),
  do: :erlang.float_to_binary(Float.round(n, 2), decimals: 2)

# In Resonance.Format
def integer(n) when is_integer(n) do
  n |> Integer.to_string() |> String.reverse()
  |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
end
```

`Resonance.Format` only handles integers with comma formatting. `SummarizeFindings` needs float formatting. Consolidate into `Resonance.Format` with `integer/1`, `float/1`, and `number/1` functions.

### E5. DataTable Column Order Is Alphabetical

```elixir
defp infer_columns([first | _]) when is_map(first) do
  first |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
end
```

This means a row like `%{label: "Acme", value: 500000, stage: "won"}` renders columns as `label | stage | value`. A smarter default: put `label` first, `value` last, alphabetize the rest. Or accept a `:columns` prop to control order explicitly (already partially there — `assign_new(:columns, ...)` exists but isn't wired to the Presenter).

---

## Part 6: Test Harness

### T1. Provider Tests Need HTTP Mocking

Replace the re-implemented private function tests with proper integration tests using `Req.Test` or `Bypass`:

```elixir
test "anthropic provider parses tool call response" do
  Req.Test.stub(ResonanceAnthropicTest, fn conn ->
    Req.Test.json(conn, %{content: [%{type: "tool_use", id: "t1", name: "rank_entities", input: %{}}]})
  end)

  assert {:ok, [%ToolCall{name: "rank_entities"}]} =
    Anthropic.chat("test", [], api_key: "k", model: "m", max_tokens: 100,
                   base_url: ... )
end
```

This tests the real code path — HTTP, JSON parsing, response handling, error cases.

### T2. No Tests for `Live.Report`

The LiveComponent has zero test coverage. This is the most complex module in the library. It should have:

- Mount test (initial state)
- Generate event test (with mock LLM)
- Streaming component arrival test
- Refresh test (re-resolve without LLM)
- Error handling test (LLM failure, resolver failure)
- Layout ordering in rendered output

Use `Phoenix.LiveViewTest` with a mock provider.

### T3. No Tests for Presentation Components

None of the 7 presentation components have render tests. At minimum:

```elixir
test "BarChart renders with data" do
  assigns = %{props: %{title: "Test", data: [%{label: "A", value: 10}]}, renderable_id: "abc"}
  html = rendered_to_string(~H"<BarChart.render props={@props} renderable_id={@renderable_id} />")
  assert html =~ "resonance-bar-chart"
  assert html =~ "Test"
end
```

### T4. No Integration Test That Runs the Full Pipeline

There's no test that calls `Resonance.generate/2` end-to-end with a mock LLM provider. The composer test gets close, but it bypasses the LLM layer. A full integration test would:

1. Configure a test provider that returns canned tool calls
2. Call `Resonance.generate("test prompt", %{resolver: MockResolver})`
3. Assert the returned Renderables match expectations

### T5. No Test for `Resonance.generate_stream/3`

The streaming API has no direct test. `Composer.compose_stream/3` is tested, but `generate_stream/3` itself isn't.

### T6. Resolver Tests Missing for CRM Demo

The finance demo has `test/finance_demo/finance/resolver_test.exs`. The CRM demo has none. Both resolvers are complex enough to warrant direct testing.

---

## Part 7: Enhancement Ideas

### Ideas Aligned with the Vision

**I1. Structured `describe/0` with Validation**
Turn the free-text describe into a structured DSL that generates both the LLM prompt string and validation rules. This is the single highest-leverage improvement for reliability.

**I2. `mix resonance.gen.primitive`**
A generator that scaffolds a new primitive with intent_schema, resolve callback, and test file. Lowers the barrier to extending the library.

**I3. Conversation Context / Follow-up Queries**
The current architecture is stateless per query. But users naturally want to drill down: "Show me deals by stage" → "Now just the closed_won ones" → "Who closed them?" Each follow-up should carry context from the previous query (the filters, the dataset).

**I4. Query Explanation**
Before resolving, show the user what Resonance understood: "I'll query the deals dataset, grouped by stage, measuring sum(value)." This builds trust and helps debug when the LLM misinterprets.

**I5. Component Playground**
A standalone LiveView page that renders each component with sample data. Useful for development, theming, and documentation. The design doc mentions this.

**I6. Result Metadata for Formatting**
Let the resolver or primitive attach format hints to results: `format: :currency`, `format: :percent`, `format: {:decimal, 2}`. The presenter uses these instead of guessing.

---

## Ticket Summary

| # | Type | Priority | Title |
|---|------|----------|-------|
| S1 | Refactor | High | Extract shared primitive resolve pattern |
| S2 | Refactor | High | Decompose Live.Report update/2 |
| S3 | Bug | High | Use TaskSupervisor in Composer |
| S4 | Enhancement | Medium | Consider ETS-based Registry |
| S5 | Bug | High | Fix provider tests to test actual code |
| C1 | Contract | High | Define resolver data row typespecs |
| C2 | Contract | Medium | Add Component behaviour |
| C3 | Contract | Medium | Document describe/0 as critical correctness path |
| C4 | Contract | Low | Type the context map |
| C5 | Bug | Medium | Replace detect_format heuristic |
| F1 | Security | High | Escape HTML in ProseSection before markdown |
| F2 | Bug | Medium | Fix normalize_sort silent default |
| F3 | Bug | High | Default max_tokens or validate at config |
| F4 | Enhancement | Medium | Validate config at startup (warning) |
| E1 | Enhancement | High | Add telemetry events |
| E2 | Enhancement | Medium | Configure ExDoc for hex.pm |
| E3 | Enhancement | Medium | Derive Jason.Encoder on core structs |
| E4 | Refactor | Low | Consolidate format helpers |
| E5 | Enhancement | Low | Smarter DataTable column ordering |
| T1 | Test | High | HTTP-mocked provider tests |
| T2 | Test | High | Live.Report LiveView tests |
| T3 | Test | Medium | Presentation component render tests |
| T4 | Test | High | Full pipeline integration test |
| T5 | Test | Medium | generate_stream/3 test |
| T6 | Test | Medium | CRM demo resolver tests |
| I1 | Feature | High | Structured describe/0 with validation |
| I2 | Feature | Medium | mix resonance.gen.primitive generator |
| I3 | Feature | High | Conversation context for follow-up queries |
| I4 | Feature | Medium | Query explanation before resolution |
| I5 | Feature | Low | Component playground |
| I6 | Feature | Medium | Result format metadata |

---

## Priority Path: What to Do First

If we were advising on the next three sprints:

**Sprint 1: Trust the Foundation**
- F1 (XSS fix), F2 (sort fix), F3 (max_tokens) — safety first
- S1 (extract primitive pattern) — reduce surface area for bugs
- T1 (provider tests), T4 (integration test) — test what matters
- E1 (telemetry) — ecosystem table stakes

**Sprint 2: Polish the Contracts**
- S2 (decompose update/2) — maintainability
- S3 (TaskSupervisor in Composer) — correctness
- C1 (data row types), C2 (Component behaviour) — developer experience
- T2 (Live.Report tests), T3 (component tests) — coverage gaps
- E2 (ExDoc), E3 (Jason.Encoder) — hex.pm readiness

**Sprint 3: Differentiate**
- I1 (structured describe) — reliability leap
- I3 (conversation context) — product differentiation
- I6 (format metadata) — presentation quality
- C5 (kill detect_format) — depends on I6
- S4 (ETS registry) — scalability

---

## Closing Thoughts

The architecture is right. The semantic layer between LLM and UI is genuinely novel in the Elixir ecosystem, and the Presenter swap between example apps proves it works. The code reads well, the contracts are mostly clear, and the design doc articulates a real vision.

The gaps are implementation gaps, not design gaps. Duplicate code, missing tests, implicit contracts that should be explicit, a LiveComponent that grew organically. All fixable.

The single biggest risk to adoption is the `describe/0` → LLM → `QueryIntent` → Resolver pipeline being too fragile for real-world data. A typo in the describe string, a hallucinated field name, a format the resolver doesn't handle — these all produce silent failures or confusing errors. Structured describe (I1) is the highest-leverage feature for reliability.

The single biggest gap for ecosystem acceptance is telemetry (E1). Every serious Elixir library emits telemetry. Without it, ops teams can't monitor LLM latency, resolution time, or error rates.

Ship these fixes and Resonance is a library worth talking about at ElixirConf.
