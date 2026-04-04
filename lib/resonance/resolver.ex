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

  @doc """
  Describe available datasets, measures, and dimensions for the LLM system prompt.

  Return a string that helps the LLM understand what data is queryable.
  This becomes part of the system prompt sent with every request.

  Optional — if not implemented, the LLM gets no dataset guidance.
  """
  @callback describe() :: String.t()

  @doc """
  Resolve a QueryIntent into data.

  Returns `{:ok, data}` where data is a list of maps, or `{:error, reason}`.
  """
  @callback resolve(intent :: Resonance.QueryIntent.t(), context :: map()) ::
              {:ok, list(map())} | {:error, term()}

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
