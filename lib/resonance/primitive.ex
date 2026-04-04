defmodule Resonance.Primitive do
  @moduledoc """
  Behaviour for semantic primitives.

  A semantic primitive represents an analytical operation — not a UI widget.
  The LLM selects primitives based on user intent. Each primitive:

  1. Describes itself to the LLM via `intent_schema/0`
  2. Resolves data via the app's resolver in `resolve/2`
  3. Maps resolved data to a presentation component in `present/2`

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
          # Build QueryIntent, call context.resolver
        end

        @impl true
        def present(data, context) do
          # Pick LineChart or BarChart based on data shape
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

  Typically builds a `Resonance.QueryIntent` from params and delegates
  to `context.resolver` for actual data fetching.
  """
  @callback resolve(params :: map(), context :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Map resolved data to a presentation component.

  Returns a `Resonance.Renderable` struct with the chosen component
  and props derived from the resolved data.
  """
  @callback present(data :: map(), context :: map()) :: Resonance.Renderable.t()
end
