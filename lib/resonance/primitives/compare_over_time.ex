defmodule Resonance.Primitives.CompareOverTime do
  @moduledoc """
  Semantic primitive: compare a metric's values across time periods.

  Returns a Result with `kind: :comparison`. The Presenter decides
  whether to render as a line chart, bar chart, or something else.
  """

  @behaviour Resonance.Primitive

  @impl true
  def intent_schema do
    %{
      name: "compare_over_time",
      description:
        "Compare a metric's values across time periods. Use when the user wants to see trends, changes over time, year-over-year comparisons, or temporal patterns.",
      parameters: %{
        type: "object",
        properties: %{
          dataset: %{
            type: "string",
            description: "The data source to query (e.g., 'deals', 'contacts', 'activities')"
          },
          measures: %{
            type: "array",
            items: %{type: "string"},
            description: "Aggregation expressions (e.g., 'sum(value)', 'count(*)', 'avg(amount)')"
          },
          dimensions: %{
            type: "array",
            items: %{type: "string"},
            description:
              "Grouping fields — must include a time dimension (e.g., 'month', 'quarter', 'year')"
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
            },
            description: "Optional filters to narrow the data"
          },
          sort: %{
            type: "object",
            properties: %{
              field: %{type: "string"},
              direction: %{type: "string", enum: ["asc", "desc"]}
            },
            description: "Sort order — defaults to time dimension ascending"
          },
          title: %{
            type: "string",
            description: "Chart title"
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
         kind: :comparison,
         title: params["title"] || params[:title],
         data: data,
         intent: intent,
         summary: Resonance.Result.compute_summary(data)
       }}
    end
  end

  defp maybe_validate(resolver, intent, context) do
    if function_exported?(resolver, :validate, 2) do
      resolver.validate(intent, context)
    else
      :ok
    end
  end
end
