defmodule Resonance.QueryIntent do
  @moduledoc """
  Structured query intent that bridges LLM output and app data resolution.

  The LLM produces semantic parameters. Primitives build a `QueryIntent`
  from those parameters. The app's resolver translates it to actual queries.

  This struct is where validation and security boundaries live — the resolver
  can inspect every field before executing.
  """

  @type t :: %__MODULE__{
          dataset: String.t(),
          measures: [String.t()],
          dimensions: [String.t()] | nil,
          filters: [filter()] | nil,
          sort: sort() | nil,
          limit: pos_integer() | nil
        }

  @type filter :: %{
          required(:field) => String.t(),
          required(:op) => String.t(),
          required(:value) => term()
        }

  @type sort :: %{
          required(:field) => String.t(),
          required(:direction) => :asc | :desc
        }

  @derive Jason.Encoder
  @enforce_keys [:dataset, :measures]
  defstruct [:dataset, :measures, :dimensions, :filters, :sort, :limit]

  @valid_ops ~w(= != > >= < <= in not_in like)

  @doc """
  Validates a QueryIntent, returning `{:ok, intent}` or `{:error, reason}`.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = intent) do
    with :ok <- validate_dataset(intent.dataset),
         :ok <- validate_measures(intent.measures),
         :ok <- validate_dimensions(intent.dimensions),
         :ok <- validate_filters(intent.filters),
         :ok <- validate_sort(intent.sort),
         :ok <- validate_limit(intent.limit) do
      {:ok, intent}
    end
  end

  @doc """
  Builds a QueryIntent from a map of parameters (typically from LLM tool call arguments).
  """
  @spec from_params(map()) :: {:ok, t()} | {:error, term()}
  def from_params(params) when is_map(params) do
    intent = %__MODULE__{
      dataset: params["dataset"] || params[:dataset],
      measures: params["measures"] || params[:measures] || [],
      dimensions: params["dimensions"] || params[:dimensions],
      filters: normalize_filters(params["filters"] || params[:filters]),
      sort: normalize_sort(params["sort"] || params[:sort]),
      limit: params["limit"] || params[:limit]
    }

    validate(intent)
  end

  defp validate_dataset(nil), do: {:error, {:invalid_field, :dataset, "is required"}}
  defp validate_dataset(d) when is_binary(d) and byte_size(d) > 0, do: :ok
  defp validate_dataset(_), do: {:error, {:invalid_field, :dataset, "must be a non-empty string"}}

  defp validate_measures(nil), do: {:error, {:invalid_field, :measures, "is required"}}
  defp validate_measures([]), do: {:error, {:invalid_field, :measures, "cannot be empty"}}

  defp validate_measures(measures) when is_list(measures) do
    if Enum.all?(measures, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_field, :measures, "must be a list of strings"}}
  end

  defp validate_measures(_), do: {:error, {:invalid_field, :measures, "must be a list"}}

  defp validate_dimensions(nil), do: :ok

  defp validate_dimensions(dims) when is_list(dims) do
    if Enum.all?(dims, &is_binary/1),
      do: :ok,
      else: {:error, {:invalid_field, :dimensions, "must be a list of strings"}}
  end

  defp validate_dimensions(_), do: {:error, {:invalid_field, :dimensions, "must be a list"}}

  defp validate_filters(nil), do: :ok

  defp validate_filters(filters) when is_list(filters) do
    Enum.reduce_while(filters, :ok, fn filter, :ok ->
      case validate_filter(filter) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_filters(_), do: {:error, {:invalid_field, :filters, "must be a list"}}

  defp validate_filter(%{field: f, op: o}) when is_binary(f) and o in @valid_ops, do: :ok
  defp validate_filter(%{"field" => f, "op" => o}) when is_binary(f) and o in @valid_ops, do: :ok
  defp validate_filter(_), do: {:error, {:invalid_field, :filters, "invalid filter format"}}

  defp validate_sort(nil), do: :ok

  defp validate_sort(%{field: f, direction: d})
       when is_binary(f) and d in [:asc, :desc],
       do: :ok

  defp validate_sort(%{"field" => f, "direction" => d})
       when is_binary(f) and d in ["asc", "desc"],
       do: :ok

  defp validate_sort(_), do: {:error, {:invalid_field, :sort, "invalid sort format"}}

  defp validate_limit(nil), do: :ok
  defp validate_limit(n) when is_integer(n) and n > 0, do: :ok
  defp validate_limit(_), do: {:error, {:invalid_field, :limit, "must be a positive integer"}}

  defp normalize_filters(nil), do: nil

  defp normalize_filters(filters) when is_list(filters) do
    Enum.map(filters, fn
      %{"field" => f, "op" => o, "value" => v} -> %{field: f, op: o, value: v}
      %{field: _, op: _, value: _} = f -> f
      other -> other
    end)
  end

  defp normalize_sort(nil), do: nil

  defp normalize_sort(%{"field" => f, "direction" => "asc"}), do: %{field: f, direction: :asc}
  defp normalize_sort(%{"field" => f, "direction" => "desc"}), do: %{field: f, direction: :desc}
  defp normalize_sort(%{"field" => f, "direction" => _}), do: %{field: f, direction: :desc}
  defp normalize_sort(%{"field" => f}), do: %{field: f, direction: :desc}

  defp normalize_sort(%{field: _, direction: _} = s), do: s
  defp normalize_sort(_), do: nil
end
