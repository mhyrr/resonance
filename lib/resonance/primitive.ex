defmodule Resonance.Primitive do
  @moduledoc """
  Behaviour for semantic primitives.

  A semantic primitive represents an analytical operation — not a UI widget.
  The LLM selects primitives based on user intent. Each primitive:

  1. Describes itself to the LLM via `intent_schema/0`
  2. Resolves data via the app's resolver and returns a `Resonance.Result`

  Primitives produce truth. A separate `Resonance.Presenter` handles
  mapping results to UI components — the developer controls that layer.

  ## Example

      defmodule MyApp.Primitives.CompareOverTime do
        @behaviour Resonance.Primitive

        @impl true
        def intent_schema do
          %{
            name: "compare_over_time",
            description: "Compare a metric's values across time periods",
            parameters: %{...}
          }
        end

        @impl true
        def resolve(params, context) do
          # Build QueryIntent, call context.resolver, return Result
          {:ok, %Resonance.Result{kind: :comparison, title: "...", data: data}}
        end
      end
  """

  @doc """
  Returns the JSON tool schema that the LLM sees.

  Must include `:name`, `:description`, and `:parameters` keys.
  The parameters should follow JSON Schema format.
  """
  @callback intent_schema() :: map()

  @doc """
  Resolve data for this primitive given LLM-provided parameters.

  Builds a `Resonance.QueryIntent` from params, delegates to
  `context.resolver` for data fetching, and returns a normalized
  `Resonance.Result` with the semantic kind, data, and summary.

  The Result is passed to a `Resonance.Presenter` for UI mapping —
  primitives produce truth, presenters choose visualization.
  """
  @callback resolve(params :: map(), context :: map()) ::
              {:ok, Resonance.Result.t()} | {:error, term()}
end
