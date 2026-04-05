defmodule Resonance.Primitives.SummarizeFindings do
  @moduledoc """
  Semantic primitive: generate a narrative summary from resolved data.

  Template-based — no second LLM call. Formats data into structured
  prose that highlights key findings, comparisons, and notable values.

  Returns a Result with `kind: :summary` and the prose content in
  `metadata.content`.
  """

  @behaviour Resonance.Primitive

  @impl true
  def intent_schema do
    %{
      name: "summarize_findings",
      description:
        "Generate a narrative summary of data findings. Use when the user would benefit from a written analysis alongside charts and tables — highlighting key takeaways, notable changes, or contextual observations.",
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
            description: "What to measure"
          },
          dimensions: %{
            type: "array",
            items: %{type: "string"},
            description: "How to group the data"
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
            description: "Summary heading"
          },
          focus: %{
            type: "string",
            description:
              "What aspect to focus on (e.g., 'trends', 'outliers', 'comparison', 'overview')"
          }
        },
        required: ["dataset", "measures", "title"]
      }
    }
  end

  @impl true
  def resolve(params, context) do
    with {:ok, result} <- Resonance.Primitive.resolve_intent(:summary, params, context) do
      summary = build_summary(result.data, params)
      {:ok, %{result | metadata: %{content: summary}}}
    end
  end

  defp build_summary([], _params) do
    "No data found for the requested query."
  end

  defp build_summary(data, params) when is_list(data) do
    focus = params["focus"] || params[:focus] || "overview"
    values = extract_values(data)

    [count_line(data)]
    |> maybe_add(length(values) > 0, fn -> range_line(values) end)
    |> maybe_add(length(values) >= 3, fn -> top_bottom_line(data) end)
    |> maybe_add(focus in ["trends", "comparison"] and length(data) >= 2, fn ->
      trend_line(data)
    end)
    |> Enum.join("\n\n")
  end

  defp maybe_add(lines, true, fun), do: lines ++ [fun.()]
  defp maybe_add(lines, false, _fun), do: lines

  defp count_line(data) do
    "**#{length(data)}** records found."
  end

  defp range_line(values) do
    min = Enum.min(values)
    max = Enum.max(values)
    avg = Enum.sum(values) / length(values)

    "Values range from **#{format_number(min)}** to **#{format_number(max)}**, " <>
      "with an average of **#{format_number(avg)}**."
  end

  defp top_bottom_line(data) do
    sorted = Enum.sort_by(data, &extract_value/1, :desc)
    top = hd(sorted)
    bottom = List.last(sorted)

    top_label = top[:label] || top["label"] || "top"
    bottom_label = bottom[:label] || bottom["label"] || "bottom"

    "Highest: **#{top_label}** (#{format_number(extract_value(top))}). " <>
      "Lowest: **#{bottom_label}** (#{format_number(extract_value(bottom))})."
  end

  defp trend_line(data) do
    first_val = extract_value(hd(data))
    last_val = extract_value(List.last(data))

    cond do
      first_val == 0 ->
        "Starting value was zero."

      true ->
        pct = Float.round((last_val - first_val) / first_val * 100, 1)

        direction = if pct >= 0, do: "increased", else: "decreased"
        "Overall trend: #{direction} by **#{abs(pct)}%** from first to last period."
    end
  end

  defp extract_values(data) do
    data
    |> Enum.map(&extract_value/1)
    |> Enum.filter(&is_number/1)
  end

  defp extract_value(row) when is_map(row) do
    row[:value] || row["value"] || row[:count] || row["count"] || 0
  end

  defp format_number(n) when is_float(n),
    do: :erlang.float_to_binary(Float.round(n, 2), decimals: 2)

  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(n), do: inspect(n)
end
