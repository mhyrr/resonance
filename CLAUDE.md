This is an Elixir library (hex package) with a Phoenix LiveView example app.

## Project Structure

- **Library**: `lib/resonance/` — the hex package consumed by apps
- **Example app**: `example/resonance_demo/` — CRM demo (Phoenix + SQLite)
- **JS hooks**: `assets/js/hooks/charts.js` — ApexCharts hooks for chart components

## Development Commands

### Essential Commands
- `mix test` — Run library tests (52 tests)
- `mix test.all` — Run library + example app tests
- `mix build.all` — Compile everything
- `mix format` — Format library code
- `mix setup` — Install deps + set up example app
- Always use Tidewave's tools for evaluating code, querying the database, etc.

Use `get_docs` to access documentation and the `get_source_location` tool to
find module/function definitions.

### Example App
- `cd example/resonance_demo && mix phx.server` — Start demo (needs ANTHROPIC_API_KEY)
- `cd example/resonance_demo && mix ecto.reset` — Reset demo database with seeds
- `cd example/resonance_demo && mix test` — Run demo app tests
- Server needs ANTHROPIC_API_KEY in the environment for LLM calls

### Testing
- `mix test` — Library tests
- `mix test test/resonance/primitives/` — Test a specific directory
- `mix test test/resonance/query_intent_test.exs` — Test a specific file

## Architecture

### Five Layers
1. **Semantic Primitives** — What the LLM selects (compare_over_time, rank_entities, etc.)
2. **Resolver** — App-provided data resolution (QueryIntent → Ecto)
3. **Presentation Mapping** — Primitive's `present/2` picks UI component based on data shape
4. **Composition Engine** — Parallel resolution + streaming
5. **LiveView Surface** — Drop-in component renders the report

### Key Contracts
- `Resonance.Primitive` behaviour: `intent_schema/0`, `resolve/2`, `present/2`
- `Resonance.Resolver` behaviour: `resolve/2`, `validate/2` (optional), `describe/0` (optional)
- `Resonance.QueryIntent` — structured query: dataset, measures, dimensions, filters, sort, limit
- `Resonance.Renderable` — what components produce: id, type, component module, props, status

### LLM Integration
- Resonance owns the LLM call — developer configures provider/api_key/model once
- Config lives in the consuming app's `config/runtime.exs`, not in the library
- Provider behaviour (`Resonance.LLM.Provider`) for custom providers
- Built-in: Anthropic and OpenAI. HTTP via Req.
- The system prompt includes `resolver.describe()` output so the LLM knows available datasets

### Data Flow
```
Resonance.generate(prompt, %{resolver: MyResolver})
  → LLM.chat (with system prompt from resolver.describe/0)
  → LLM returns tool calls (semantic primitives)
  → Composer dispatches to primitives in parallel
  → Each primitive: validate → build QueryIntent → call resolver → present
  → Layout orders the Renderables
  → LiveView renders
```

## Project Guidelines

- Use `Req` for HTTP requests — it's the only HTTP dep
- Model ID configuration lives in ONE place: the consuming app's config. Providers use `fetch!`, no fallback defaults.
- The `describe/0` callback on Resolver is critical — without it the LLM doesn't know dataset names
- Presentation components are Phoenix function components that take a `props` assign
- Chart components use JS hooks (ApexCharts) — title comes from the HEEx `<h3>`, not from ApexCharts config
- When adding a new semantic primitive, implement `Resonance.Primitive` and register it in `Resonance.Registry.register_defaults/1`
- When adding a new presentation component, create a module under `Resonance.Components.*`

## Elixir Guidelines

- Elixir lists **do not support index-based access** — use `Enum.at/2` or pattern matching
- Elixir variables are immutable but rebindable — bind block results to variables
- **Never** nest multiple modules in the same file
- **Never** use map access syntax on structs — use `my_struct.field`
- Predicate functions end with `?`, not `is_` prefix (reserve `is_` for guards)
- Use `Task.async_stream` for concurrent work with backpressure

## Phoenix / LiveView Guidelines

- Templates use `~H` (HEEx), never `~E`
- Use `{...}` for attribute interpolation, `<%= ... %>` for block constructs in tag bodies
- Use `<.form for={@form}>` with `to_form/2`, never pass changesets directly
- Use LiveView streams for collections, not regular list assigns
- **Never** write inline `<script>` tags — put JS in `assets/js/` and import in `app.js`
- Hooks that manage their own DOM need `phx-update="ignore"`

## Ecto Guidelines

- `Ecto.Schema` uses `:string` type even for text columns
- Preload associations in queries when they'll be accessed in templates
- Use `Ecto.Changeset.get_field/2` to access changeset fields, not map access
- Remember `import Ecto.Query` when writing queries

## JS and CSS Guidelines

- Tailwind CSS v4 — no `tailwind.config.js`, uses `@import "tailwindcss"` in `app.css`
- Only `app.js` and `app.css` bundles are supported — import vendor deps into them
- **Never** use `@apply` in CSS
- **Never** reference external script `src` or link `href` in layouts
