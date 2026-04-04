defmodule Resonance.Primitives.ShowDistribution do
  @moduledoc """
  Semantic primitive: show composition or proportions of a population.

  Maps to pie_chart (few categories) or bar_chart (many categories).
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
      {:ok, %{data: data, title: params["title"] || params[:title]}}
    end
  end

  @impl true
  def present(data, _context) do
    if length(data.data) <= 8 do
      Resonance.Renderable.ready(
        "show_distribution",
        Resonance.Components.PieChart,
        %{
          title: data.title,
          data: data.data,
          donut: true,
          show_percentages: true
        }
      )
    else
      Resonance.Renderable.ready(
        "show_distribution",
        Resonance.Components.BarChart,
        %{
          title: data.title,
          data: data.data,
          orientation: "horizontal"
        }
      )
    end
  end

  defp maybe_validate(resolver, intent, context) do
    if function_exported?(resolver, :validate, 2),
      do: resolver.validate(intent, context),
      else: :ok
  end
end
