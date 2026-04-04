defmodule Resonance.Primitives.SegmentPopulation do
  @moduledoc """
  Semantic primitive: break a population into groups.

  Maps to metric_grid (few segments with aggregate values) or
  data_table (many segments or detail rows).
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
      {:ok, %{data: data, title: params["title"] || params[:title], intent: intent}}
    end
  end

  @impl true
  def present(data, _context) do
    if length(data.data) <= 6 do
      metrics =
        Enum.map(data.data, fn row ->
          %{
            label: row[:label] || row["label"] || "Segment",
            value: row[:value] || row["value"] || row[:count] || row["count"] || 0,
            format: detect_format(row)
          }
        end)

      Resonance.Renderable.ready(
        "segment_population",
        Resonance.Components.MetricGrid,
        %{
          title: data.title,
          metrics: metrics,
          columns: min(length(metrics), 3)
        }
      )
    else
      Resonance.Renderable.ready(
        "segment_population",
        Resonance.Components.DataTable,
        %{
          title: data.title,
          data: data.data,
          sortable: true
        }
      )
    end
  end

  defp detect_format(row) do
    value = row[:value] || row["value"] || 0

    cond do
      is_float(value) and value < 1 -> "percent"
      is_number(value) and value > 1000 -> "currency"
      true -> "number"
    end
  end

  defp maybe_validate(resolver, intent, context) do
    if function_exported?(resolver, :validate, 2),
      do: resolver.validate(intent, context),
      else: :ok
  end
end
