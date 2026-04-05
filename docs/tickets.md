# Resonance Tickets

Generated from architecture review, 2026-04-04.
Priority: P0 (do now), P1 (before hex publish), P2 (v0.2).

---

## Safety & Correctness

### RESO-001: Escape HTML in ProseSection markdown renderer
**Type:** Security | **Priority:** P0

`ProseSection.render_markdown/1` (lib/resonance/components/prose_section.ex:22) applies regex markdown transforms then passes content through `Phoenix.HTML.raw/1`. If any non-library code passes user-controlled content to ProseSection via a custom Presenter, this is an XSS vector.

**Fix:** HTML-escape the paragraph text before applying bold/italic regex:
```elixir
inner = paragraph
  |> Phoenix.HTML.html_escape()
  |> Phoenix.HTML.safe_to_string()
  |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
  |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
```

**Files:** `lib/resonance/components/prose_section.ex`
**Test:** Add test with `<script>` content in ProseSection props, assert it's escaped.

---

### RESO-002: Fix normalize_sort silent fallback to :asc
**Type:** Bug | **Priority:** P0

`QueryIntent.normalize_sort/1` (lib/resonance/query_intent.ex:101) uses `String.to_existing_atom/1` with a rescue that silently defaults to `:asc`. If the LLM sends `"descending"` instead of `"desc"`, the user gets ascending sort with no indication.

**Fix:** Replace with explicit pattern matching:
```elixir
defp normalize_sort(%{"field" => f, "direction" => "asc"}), do: %{field: f, direction: :asc}
defp normalize_sort(%{"field" => f, "direction" => "desc"}), do: %{field: f, direction: :desc}
defp normalize_sort(%{"field" => f, "direction" => _}), do: %{field: f, direction: :desc}
```

Default to `:desc` for unknown values — ranking/sorting most commonly wants descending.

**Files:** `lib/resonance/query_intent.ex`
**Test:** Add case for `"direction" => "descending"` in query_intent_test.

---

### RESO-003: Default max_tokens or raise clear error
**Type:** Bug | **Priority:** P0

Both providers use `Keyword.fetch!(opts, :max_tokens)` (anthropic.ex:14, openai.ex:13). If the consuming app omits `max_tokens` from config, the first LLM call crashes with a bare `KeyError` — no indication of what's missing.

**Fix:** Use `Keyword.get(opts, :max_tokens, 4096)` for a sensible default, matching the design doc's example config. Alternatively, validate at `LLM.chat/3` entry with a clear error message.

**Files:** `lib/resonance/llm/providers/anthropic.ex`, `lib/resonance/llm/providers/openai.ex`

---

### RESO-004: Use TaskSupervisor in Composer
**Type:** Bug | **Priority:** P0

`Composer.compose/2` uses bare `Task.async_stream` (line 21) and `compose_stream/3` uses bare `Task.start` (line 40). These tasks aren't supervised — if the calling process dies, tasks leak.

`Live.Report` already uses `Task.Supervisor.start_child(Resonance.TaskSupervisor, ...)`. Composer should be consistent.

**Fix:** Replace `Task.async_stream` with `Task.Supervisor.async_stream_nolink(Resonance.TaskSupervisor, ...)` in both functions.

**Files:** `lib/resonance/composer.ex`
**Test:** Existing composer_test.exs should still pass. Add test that verifies tasks are supervised.

---

## Structural Refactors

### RESO-005: Extract shared primitive resolve pattern
**Type:** Refactor | **Priority:** P1

Four of five primitives duplicate identical resolve logic (~20 lines each) plus identical `maybe_validate/3`. Total duplication: ~80 lines.

**Fix:** Add `Resonance.Primitive.resolve_intent/3` as a public helper:
```elixir
def resolve_intent(kind, params, context) do
  resolver = context[:resolver] || context["resolver"]
  with {:ok, intent} <- QueryIntent.from_params(params),
       :ok <- validate_if_implemented(resolver, intent, context),
       {:ok, data} <- resolver.resolve(intent, context) do
    {:ok, %Result{kind: kind, title: params["title"] || params[:title],
                  data: data, intent: intent,
                  summary: Result.compute_summary(data)}}
  end
end
```

Each primitive's `resolve/2` becomes a one-liner (except SummarizeFindings which extends the pattern).

**Files:** `lib/resonance/primitive.ex`, all five files in `lib/resonance/primitives/`
**Test:** All existing primitive tests should pass unchanged.

---

### RESO-006: Decompose Live.Report update/2
**Type:** Refactor | **Priority:** P1

`update/2` is ~90 lines of cascading `case` statements handling 8+ different update signals. Hard to read, hard to test, easy to break.

**Fix:** Extract each handler into a named private function:
```elixir
def update(assigns, socket) do
  {:ok,
   socket
   |> apply_base_assigns(assigns)
   |> handle_streaming_component(assigns)
   |> handle_tool_calls(assigns)
   |> handle_done(assigns)
   |> handle_error(assigns)
   |> handle_set_prompt(assigns)
   |> handle_regenerate(assigns)
   |> handle_refresh(assigns)
   |> handle_assign_updates(assigns)}
end
```

Each function pattern-matches on the relevant assign key and passes through otherwise.

**Files:** `lib/resonance/live/report.ex`
**Test:** Requires T2 (Live.Report tests) first.

---

### RESO-007: Consolidate format helpers
**Type:** Refactor | **Priority:** P2

`SummarizeFindings` has its own `format_number/1` (lines 97-99) while `Resonance.Format` exists but only handles integers. Also, `MetricCard` and `MetricGrid` both have their own `format_value/2`.

**Fix:** Expand `Resonance.Format` to handle integers, floats, currency, and percentage. Components and primitives call `Format` instead of rolling their own.

**Files:** `lib/resonance/format.ex`, `lib/resonance/primitives/summarize_findings.ex`, `lib/resonance/components/metric_card.ex`, `lib/resonance/components/metric_grid.ex`

---

## Contract Improvements

### RESO-008: Define resolver data row typespecs
**Type:** Contract | **Priority:** P1

The resolver returns maps with varying shapes (basic, time-series, multi-series) but no typespec documents this. Developers guess from examples.

**Fix:** In `resolver.ex`, define:
```elixir
@type data_row :: %{
  required(:label) => String.t(),
  required(:value) => number(),
  optional(:period) => String.t(),
  optional(:series) => String.t(),
  optional(:group) => String.t(),
  optional(:format) => atom()
}
```

Update the `resolve/2` callback return type to reference `data_row`.

**Files:** `lib/resonance/resolver.ex`

---

### RESO-009: Add Component behaviour
**Type:** Contract | **Priority:** P1

Chart components must implement `render/1` and optionally `chart_dom_id/1`, but this contract is implicit. `Live.Report` checks `function_exported?` at runtime.

**Fix:** Define `Resonance.Component` behaviour:
```elixir
defmodule Resonance.Component do
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback chart_dom_id(renderable_id :: String.t()) :: String.t()
  @optional_callbacks [chart_dom_id: 1]
end
```

Have all 7 built-in components declare `@behaviour Resonance.Component`.

**Files:** New file `lib/resonance/component.ex`, all files in `lib/resonance/components/`

---

### RESO-010: Replace detect_format heuristic
**Type:** Bug/Contract | **Priority:** P1

`Presenters.Default.detect_format/1` guesses currency vs. percent vs. number from value magnitude. A count of 1500 becomes "currency." A ratio of 0.7 becomes "percent."

**Fix (short-term):** Remove the heuristic. Default to "number" for all values. Let the resolver carry format hints via an optional `:format` key in data rows.

**Fix (long-term):** See RESO-020 (Result format metadata).

**Files:** `lib/resonance/presenters/default.ex`

---

### RESO-011: Document describe/0 as the critical correctness path
**Type:** Docs | **Priority:** P1

The connection between `describe/0` output and resolver capabilities is the most common source of bugs. A mismatch means the LLM requests invalid fields → silent failures.

**Fix:** Add a dedicated section in the Resolver moduledoc and README explaining:
- describe/0 output MUST match actual field/measure/dimension names exactly
- Common mistakes (using synonyms, forgetting new fields)
- How to debug when the LLM requests invalid data

**Files:** `lib/resonance/resolver.ex`, `README.md`

---

### RESO-012: Type the context map
**Type:** Contract | **Priority:** P2

Every function takes `context :: map()`. Define a typespec:
```elixir
@type context :: %{
  required(:resolver) => module(),
  optional(:current_user) => term(),
  optional(:presenter) => module()
}
```

**Files:** `lib/resonance.ex` (define type), reference in `composer.ex`, `primitive.ex`, `presenter.ex`

---

## Ecosystem Readiness

### RESO-013: Add telemetry events
**Type:** Enhancement | **Priority:** P0

Table stakes for ecosystem adoption. Add `:telemetry` as a dependency and emit events:

- `[:resonance, :generate, :start | :stop | :exception]` — measurements: `%{system_time: ...}`, metadata: `%{prompt: ..., resolver: ...}`
- `[:resonance, :llm, :call, :start | :stop | :exception]` — measurements: `%{duration: ...}`, metadata: `%{provider: ..., tool_count: ...}`
- `[:resonance, :primitive, :resolve, :start | :stop | :exception]` — measurements: `%{duration: ...}`, metadata: `%{primitive: ..., row_count: ...}`

Wrap the key call sites in `Resonance.generate/2`, `LLM.chat/3`, and `Composer.resolve_one/2`.

**Files:** `mix.exs` (add dep), `lib/resonance.ex`, `lib/resonance/llm.ex`, `lib/resonance/composer.ex`

---

### RESO-014: Configure ExDoc for hex.pm
**Type:** Enhancement | **Priority:** P1

Add docs configuration to mix.exs:
```elixir
docs: [
  main: "Resonance",
  extras: ["README.md"],
  groups_for_modules: [
    "Behaviours": [...],
    "Primitives": ~r/Resonance.Primitives/,
    "Components": ~r/Resonance.Components/,
    "LLM": ~r/Resonance.LLM/
  ]
]
```

**Files:** `mix.exs`

---

### RESO-015: Derive Jason.Encoder on core structs
**Type:** Enhancement | **Priority:** P1

Add `@derive Jason.Encoder` to `Result`, `QueryIntent`, `Renderable`, and `ToolCall`. Enables serialization for saved reports (v0.2), API responses, and logging.

Do this now to avoid a breaking change when saved reports ship.

**Files:** `lib/resonance/result.ex`, `lib/resonance/query_intent.ex`, `lib/resonance/renderable.ex`, `lib/resonance/llm/tool_call.ex`

---

### RESO-016: Validate LLM config at startup (warning)
**Type:** Enhancement | **Priority:** P2

Add a `validate_config/0` call in `Application.start/2` that logs a warning if provider/api_key/model are not configured. Don't crash — the app should boot even with incomplete Resonance config (e.g., during test runs that don't need LLM).

**Files:** `lib/resonance/application.ex`

---

### RESO-017: Smarter DataTable column ordering
**Type:** Enhancement | **Priority:** P2

`DataTable.infer_columns/1` sorts alphabetically. Better default: `label` first, `value` last, rest alphabetized. Also wire the existing `assign_new(:columns, ...)` to accept a prop from the Presenter.

**Files:** `lib/resonance/components/data_table.ex`

---

## Test Harness

### RESO-018: HTTP-mocked provider tests
**Type:** Test | **Priority:** P0

Current provider tests re-implement private parsing functions locally. They don't test the actual provider code.

**Fix:** Add `bypass` or use `Req.Test` to mock HTTP. Test through the public `chat/3` function:
- Successful tool call extraction
- API error responses (4xx, 5xx)
- Network failures
- Empty/malformed responses

**Files:** `test/resonance/llm/providers/anthropic_test.exs`, `test/resonance/llm/providers/openai_test.exs`, `mix.exs` (add test dep if needed)

---

### RESO-019: Live.Report LiveView tests
**Type:** Test | **Priority:** P0

The most complex module in the library has zero test coverage.

**Fix:** Create `test/resonance/live/report_test.exs` using `Phoenix.LiveViewTest`:
- Mount renders prompt input
- Submit empty prompt does nothing
- Submit prompt triggers loading state
- Streaming components appear progressively
- Error display on LLM failure
- Refresh re-resolves without LLM call
- Clear resets state

Requires a mock LLM provider. Create `test/support/mock_provider.ex` that returns canned tool calls.

**Files:** New `test/resonance/live/report_test.exs`, new `test/support/mock_provider.ex`

---

### RESO-020: Full pipeline integration test
**Type:** Test | **Priority:** P1

No test exercises `Resonance.generate/2` end-to-end.

**Fix:** Create `test/resonance/integration_test.exs`:
```elixir
test "generate resolves prompt through full pipeline" do
  # Configure test provider returning canned tool calls
  # Call Resonance.generate/2
  # Assert returned Renderables have correct types, components, data
end
```

**Files:** New `test/resonance/integration_test.exs`

---

### RESO-021: Presentation component render tests
**Type:** Test | **Priority:** P1

None of the 7 components have render tests.

**Fix:** Create `test/resonance/components/` with tests for each component:
- BarChart renders hook div with data attributes
- LineChart handles multi_series flag
- PieChart passes donut option
- DataTable infers columns and formats cells
- MetricCard computes trend
- MetricGrid renders grid items
- ProseSection renders markdown (and escapes HTML — ties to RESO-001)
- ErrorDisplay shows error message

**Files:** New test files in `test/resonance/components/`

---

### RESO-022: generate_stream/3 test
**Type:** Test | **Priority:** P1

`Resonance.generate_stream/3` has no direct test.

**Fix:** Test with mock provider, assert process receives streaming messages in correct order.

**Files:** Could be part of integration_test.exs (RESO-020)

---

### RESO-023: CRM demo resolver tests
**Type:** Test | **Priority:** P2

Finance demo has resolver tests. CRM demo doesn't.

**Fix:** Create `example/resonance_demo/test/resonance_demo/crm/resolver_test.exs` covering the major query paths.

**Files:** New test file in example app

---

## Feature Ideas

### RESO-024: Structured describe/0 with validation
**Type:** Feature | **Priority:** P1

Replace free-text `describe/0` with a structured return:
```elixir
@callback describe() :: String.t() | [dataset_spec()]

@type dataset_spec :: %{
  name: String.t(),
  fields: [String.t()],
  measures: [String.t()],
  dimensions: [String.t()],
  description: String.t()
}
```

Provide `Resonance.Resolver.format_description/1` to render specs into the system prompt string. This enables:
- Validation that QueryIntent datasets match describe output
- Better error messages when the LLM requests invalid data
- Auto-generated documentation

Backward-compatible: string return still works (pass-through).

**Files:** `lib/resonance/resolver.ex`, new helper module or function

---

### RESO-025: Conversation context for follow-up queries
**Type:** Feature | **Priority:** P1

Users naturally drill down: "Show deals by stage" → "Just the closed_won ones" → "Who closed them?" Each follow-up should carry context from the previous query.

**Design sketch:**
- `Live.Report` stores the last Result set and QueryIntents
- Follow-up prompts include prior context in the LLM system prompt
- The LLM can reference prior filters/datasets without re-specifying

This is the biggest product differentiator after the semantic layer itself.

---

### RESO-026: Result format metadata
**Type:** Feature | **Priority:** P1

Let resolvers or primitives attach format hints to Results:
```elixir
%Result{
  kind: :ranking,
  format: %{value: :currency},  # or per-row: data rows include :format key
  ...
}
```

The Presenter uses these instead of the broken `detect_format` heuristic.

**Files:** `lib/resonance/result.ex`, `lib/resonance/presenters/default.ex`

---

### RESO-027: mix resonance.gen.primitive
**Type:** Feature | **Priority:** P2

Generator that scaffolds:
- `lib/my_app/primitives/my_primitive.ex` with behaviour, intent_schema, resolve
- `test/my_app/primitives/my_primitive_test.exs`
- Registration in application.ex

Lowers the barrier for custom primitives.

**Files:** New mix task

---

### RESO-028: Query explanation before resolution
**Type:** Feature | **Priority:** P2

Before resolving, show the user what Resonance understood:
"Querying deals grouped by stage, measuring sum(value)"

Emit a `{:resonance, {:query_plan, explanation}}` message. The LiveComponent can render it as a collapsed detail section above the results.

Builds trust and aids debugging.

---

### RESO-029: Component playground
**Type:** Feature | **Priority:** P2

A standalone LiveView page that renders each component with sample data. Useful for development, theming, and documentation.

Could ship as a route the example apps mount, or as a separate mix task (`mix resonance.playground`).

---

### RESO-030: Consider ETS-based Registry
**Type:** Enhancement | **Priority:** P2

Replace the Agent-based Registry with ETS for better concurrent read performance and crash resilience. Same API, backed by `:ets.new(:resonance_registry, [:named_table, :public, read_concurrency: true])`.

Benefits: faster reads (no message passing), survives registry process crashes (data in ETS), enables multiple instances (named tables per instance).

**Files:** `lib/resonance/registry.ex`, `lib/resonance/application.ex`
