defmodule Resonance.Resolver do
  @moduledoc """
  Behaviour for app-provided data resolvers.

  The resolver is the critical trust boundary. It receives a validated
  `Resonance.QueryIntent` and translates it into actual data queries
  against your application's database.

  ## Responsibilities

  - Validate that the requested dataset, measures, and dimensions are allowed
  - Enforce user permissions and data access controls
  - Translate the QueryIntent into Ecto queries (or whatever your data layer uses)
  - Return normalized data

  ## Example

      defmodule MyApp.DataResolver do
        @behaviour Resonance.Resolver

        @impl true
        def resolve(%Resonance.QueryIntent{dataset: "deals"} = intent, context) do
          data =
            MyApp.Deals
            |> scope_to_org(context.current_user)
            |> apply_measures(intent.measures)
            |> apply_dimensions(intent.dimensions)
            |> apply_filters(intent.filters)
            |> Repo.all()

          {:ok, data}
        end

        @impl true
        def validate(%Resonance.QueryIntent{dataset: dataset}, _context) do
          if dataset in ~w(deals contacts companies activities),
            do: :ok,
            else: {:error, :unknown_dataset}
        end
      end
  """

  @type data_row :: %{
          required(:label) => String.t(),
          required(:value) => number(),
          optional(:period) => String.t(),
          optional(:series) => String.t(),
          optional(:group) => String.t(),
          optional(:format) => atom()
        }

  @doc """
  Describe available datasets, measures, and dimensions for the LLM system prompt.

  This is the **most critical correctness callback** in Resonance. The string
  returned here becomes the LLM's only knowledge of what data is queryable.
  If `describe/0` says a field exists but the resolver doesn't handle it,
  the LLM will request it and resolution will silently fail or return empty data.

  ## Rules

  1. Every dataset name in `describe/0` **must** match a pattern in `resolve/2`
  2. Every measure and dimension listed **must** be handled by your query builder
  3. Use the exact names — "sum(value)" in describe means `resolve/2` must handle "sum(value)"
  4. When you add a new field to the resolver, update `describe/0` in the same commit

  ## Common Mistakes

  - Using synonyms: describe says "revenue" but resolver expects "value"
  - Forgetting new fields: adding a filter to resolve but not listing it in describe
  - Stale descriptions: renaming a dataset in the schema but not in describe

  ## Debugging

  When the LLM produces unexpected results:
  1. Check what `describe/0` returns — is the field/measure listed?
  2. Check `QueryIntent` in telemetry — what did the LLM actually request?
  3. Check resolver logs — did it receive the intent? Did it return data?

  Optional — if not implemented, the LLM gets no dataset guidance and must
  rely entirely on the prompt.
  """
  @callback describe() :: String.t()

  @doc """
  Resolve a QueryIntent into data.

  Returns `{:ok, data}` where data is a list of maps, or `{:error, reason}`.
  """
  @callback resolve(intent :: Resonance.QueryIntent.t(), context :: map()) ::
              {:ok, [data_row()]} | {:error, term()}

  @doc """
  Validate a QueryIntent before resolution.

  Check that the dataset exists, measures are allowed, and the user
  has permission. Return `:ok` or `{:error, reason}`.

  Optional — if not implemented, validation is skipped.
  """
  @callback validate(intent :: Resonance.QueryIntent.t(), context :: map()) ::
              :ok | {:error, term()}

  @optional_callbacks [describe: 0, validate: 2]
end
