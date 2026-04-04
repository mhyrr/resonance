defmodule Resonance.Primitives.ShowDistribution do
  @moduledoc """
  Semantic primitive: show composition or proportions of a population.

  Returns a Result with `kind: :distribution`. The Presenter decides
  whether to render as a pie chart, treemap, bar chart, or something else.
  """

  @behaviour Resonance.Primitive

  @impl true
  def intent_schema do
    %{
      name: "show_distribution",
      description:
        "Show the distribution or composition of data across categories. Use when the user wants to see proportions, breakdowns, or how a total is divided (e.g., 'deals by stage', 'revenue by region', 'contacts by industry').",
      parameters: %{
        type: "object",
        properties: %{
          dataset: %{
            type: "string",
            description: "The data source to query"
          },
          measures: %{
            type: "array",
            items: %{type: "string"},
            description: "What to measure (e.g., 'count(*)', 'sum(value)')"
          },
          dimensions: %{
            type: "array",
            items: %{type: "string"},
            description: "Category to distribute across (e.g., 'stage', 'region')"
          },
          filters: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                field: %{type: "string"},
                op: %{type: "string", enum: ["=", "!=", ">", ">=", "<", "<=", "in", "not_in"]},
                value: %{description: "Filter value"}
              },
              required: ["field", "op", "value"]
            }
          },
          title: %{
            type: "string",
            description: "Display title"
          }
        },
        required: ["dataset", "measures", "dimensions", "title"]
      }
    }
  end

  @impl true
  def resolve(params, context) do
    resolver = context[:resolver] || context["resolver"]

    with {:ok, intent} <- Resonance.QueryIntent.from_params(params),
         :ok <- maybe_validate(resolver, intent, context),
         {:ok, data} <- resolver.resolve(intent, context) do
      {:ok,
       %Resonance.Result{
         kind: :distribution,
         title: params["title"] || params[:title],
         data: data,
         intent: intent,
         summary: Resonance.Result.compute_summary(data)
       }}
    end
  end

  defp maybe_validate(resolver, intent, context) do
    if function_exported?(resolver, :validate, 2),
      do: resolver.validate(intent, context),
      else: :ok
  end
end
