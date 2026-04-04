defmodule Resonance.Result do
  @moduledoc """
  Normalized output from a semantic primitive's resolution.

  A Result carries the semantic truth — what the data says — without
  any presentation decisions. The `kind` tells a Presenter what type
  of analysis produced this data, but not how to render it.

  ## Fields

  - `kind` — the semantic operation that produced this result
    (`:comparison`, `:ranking`, `:distribution`, `:segmentation`, `:summary`)
  - `title` — display title from the LLM
  - `data` — flat normalized rows from the resolver (`[%{label, value, ...}]`)
  - `intent` — the `QueryIntent` that produced the data (for presenter context)
  - `summary` — computed stats: count, min, max, avg
  - `metadata` — extensible; prose summaries put content here
  """

  @type t :: %__MODULE__{
          kind: atom(),
          title: String.t(),
          data: [map()],
          intent: Resonance.QueryIntent.t() | nil,
          summary: map(),
          metadata: map()
        }

  @enforce_keys [:kind, :title]
  defstruct [:kind, :title, :intent, data: [], summary: %{}, metadata: %{}]

  @doc """
  Compute summary statistics from a list of data rows.

  Extracts numeric values from `:value` or `"value"` keys and computes
  count, min, max, and average.
  """
  @spec compute_summary([map()]) :: map()
  def compute_summary(data) when is_list(data) do
    values =
      data
      |> Enum.map(&extract_value/1)
      |> Enum.filter(&is_number/1)

    case values do
      [] ->
        %{count: length(data)}

      vals ->
        %{
          count: length(data),
          min: Enum.min(vals),
          max: Enum.max(vals),
          avg: Enum.sum(vals) / length(vals)
        }
    end
  end

  defp extract_value(row) when is_map(row) do
    row[:value] || row["value"] || row[:count] || row["count"]
  end
end
