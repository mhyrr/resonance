defmodule Resonance.Primitives.SegmentPopulation do
  @moduledoc """
  Semantic primitive: break a population into groups.

  Returns a Result with `kind: :segmentation`. The Presenter decides
  whether to render as a metric grid, table, or something else.
  """

  @behaviour Resonance.Primitive

  @impl true
  def intent_schema do
    %{
      name: "segment_population",
      description:
        "Segment or group a population by attributes. Use when the user wants to break data into meaningful groups and compare them (e.g., 'contacts by stage', 'deals by owner and stage', 'companies by size tier').",
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
            description:
              "Aggregations per segment (e.g., 'count(*)', 'sum(value)', 'avg(amount)')"
          },
          dimensions: %{
            type: "array",
            items: %{type: "string"},
            description: "Fields to segment by"
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
         kind: :segmentation,
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
