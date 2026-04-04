defmodule Resonance.Primitives.RankEntities do
  @moduledoc """
  Semantic primitive: order entities by a metric.

  Returns a Result with `kind: :ranking`. The Presenter decides
  whether to render as a bar chart, table, or something else.
  """

  @behaviour Resonance.Primitive

  @impl true
  def intent_schema do
    %{
      name: "rank_entities",
      description:
        "Rank or order entities by a metric. Use when the user wants to see top/bottom items, leaderboards, or sorted lists (e.g., 'top 10 deals', 'largest accounts', 'most active contacts').",
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
            description: "Aggregation expressions to rank by"
          },
          dimensions: %{
            type: "array",
            items: %{type: "string"},
            description: "The entity fields to group by (e.g., 'company_name', 'contact_name')"
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
          sort: %{
            type: "object",
            properties: %{
              field: %{type: "string"},
              direction: %{type: "string", enum: ["asc", "desc"]}
            },
            description: "Sort order — defaults to descending by first measure"
          },
          limit: %{
            type: "integer",
            description: "Number of results to return (default 10)"
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

    params =
      params
      |> Map.put_new("limit", 10)
      |> Map.put_new("sort", %{"field" => hd(params["measures"] || [""]), "direction" => "desc"})

    with {:ok, intent} <- Resonance.QueryIntent.from_params(params),
         :ok <- maybe_validate(resolver, intent, context),
         {:ok, data} <- resolver.resolve(intent, context) do
      {:ok,
       %Resonance.Result{
         kind: :ranking,
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
