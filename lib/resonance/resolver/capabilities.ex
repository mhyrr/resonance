defmodule Resonance.Resolver.Capabilities do
  @moduledoc """
  Structured resolver capability descriptions.

  A resolver may still return the old free-form `describe/0` string. When it
  returns a map, this module normalizes it into a small manifest the planner
  and validators can trust: datasets, fields, measures, dimensions, filters,
  and allowed query shapes.
  """

  alias Resonance.QueryIntent

  @type named_spec :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:type) => String.t(),
          optional(:values) => [term()]
        }

  @type filter_spec :: %{
          required(:field) => String.t(),
          optional(:description) => String.t(),
          optional(:ops) => [String.t()],
          optional(:values) => [term()]
        }

  @type query_shape :: %{
          required(:dimensions) => [String.t()],
          optional(:measures) => [String.t()],
          optional(:description) => String.t()
        }

  @type dataset_spec :: %{
          required(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:fields) => [named_spec()],
          optional(:measures) => [named_spec()],
          optional(:dimensions) => [named_spec()],
          optional(:filters) => [filter_spec()],
          optional(:query_shapes) => [query_shape()]
        }

  @type t :: %{
          optional(:description) => String.t(),
          required(:datasets) => [dataset_spec()],
          optional(:notes) => [String.t()]
        }

  @type raw :: String.t() | map()

  @type validation_error :: %{
          required(:path) => [atom() | String.t() | non_neg_integer()],
          required(:code) => atom(),
          required(:message) => String.t(),
          optional(:details) => map()
        }

  @doc "An empty structured capability manifest."
  @spec empty() :: t()
  def empty, do: %{datasets: []}

  @doc """
  Normalize a free-form string or structured map into a capability manifest.
  """
  @spec normalize(raw() | nil) ::
          {:ok, t()} | {:error, {:validation_failed, [validation_error()]}}
  def normalize(nil), do: {:ok, empty()}

  def normalize(description) when is_binary(description) do
    {:ok, %{description: String.trim(description), datasets: []}}
  end

  def normalize(%{} = raw) do
    datasets = fetch(raw, "datasets") || []
    notes = normalize_notes(fetch(raw, "notes") || [])

    errors =
      []
      |> validate_dataset_list(datasets)
      |> Enum.reverse()

    if errors == [] do
      {:ok,
       %{
         description: fetch(raw, "description"),
         datasets: normalize_datasets(datasets),
         notes: notes
       }}
    else
      {:error, {:validation_failed, errors}}
    end
  end

  def normalize(other) do
    {:error,
     {:validation_failed,
      [
        error(
          [:describe],
          :invalid_capabilities,
          "resolver describe/0 must return a string or structured map",
          %{received: other}
        )
      ]}}
  end

  @doc """
  Read and normalize capabilities from a resolver module.
  """
  @spec from_resolver(module() | nil) ::
          {:ok, t()} | {:error, {:validation_failed, [validation_error()]}}
  def from_resolver(resolver) when is_atom(resolver) and not is_nil(resolver) do
    if function_exported?(resolver, :describe, 0) do
      resolver.describe()
      |> normalize()
    else
      {:ok, empty()}
    end
  end

  def from_resolver(_resolver), do: {:ok, empty()}

  @doc """
  Render a capability manifest into the resolver section of an LLM prompt.

  This function is deliberately tolerant for the legacy string path: a string
  is returned as-is. Invalid maps render a developer-facing error string instead
  of raising while a prompt is being built.
  """
  @spec format_description(raw() | t() | nil) :: String.t()
  def format_description(nil), do: ""
  def format_description(description) when is_binary(description), do: description

  def format_description(%{} = raw) do
    case normalize(raw) do
      {:ok, %{datasets: []} = capabilities} ->
        capabilities[:description] || ""

      {:ok, capabilities} ->
        capabilities
        |> description_lines()
        |> Enum.reject(&blank?/1)
        |> Enum.join("\n")

      {:error, {:validation_failed, errors}} ->
        "Invalid resolver capabilities: #{inspect(errors)}"
    end
  end

  def format_description(other), do: inspect(other)

  @doc """
  Validate that a `QueryIntent` only uses declared resolver capabilities.

  Legacy free-form descriptions cannot be validated structurally, so they pass.
  """
  @spec validate_intent(QueryIntent.t(), t() | raw(), keyword()) ::
          :ok | {:error, [validation_error()]}
  def validate_intent(%QueryIntent{} = intent, capabilities_or_raw, opts \\ []) do
    path = Keyword.get(opts, :path, [])

    with {:ok, capabilities} <- normalize(capabilities_or_raw) do
      validate_intent_against_capabilities(intent, capabilities, path)
    else
      {:error, {:validation_failed, errors}} -> {:error, errors}
    end
  end

  @doc """
  Validate tool-call arguments against resolver capabilities.
  """
  @spec validate_tool_call(Resonance.LLM.ToolCall.t(), t() | raw(), keyword()) ::
          :ok | {:error, [validation_error()]}
  def validate_tool_call(
        %Resonance.LLM.ToolCall{name: name, arguments: arguments},
        capabilities,
        opts
      ) do
    path = Keyword.get(opts, :path, [])
    primitive_names = Keyword.get(opts, :primitive_names)

    errors =
      []
      |> validate_primitive_name(name, primitive_names, path)

    intent_result = QueryIntent.from_params(arguments)

    errors =
      case intent_result do
        {:ok, intent} ->
          case validate_intent(intent, capabilities, path: path ++ [:arguments]) do
            :ok -> errors
            {:error, intent_errors} -> errors ++ intent_errors
          end

        {:error, reason} ->
          errors ++
            [
              error(
                path ++ [:arguments],
                :invalid_query_intent,
                "tool call arguments must form a valid QueryIntent",
                %{reason: reason}
              )
            ]
      end

    if errors == [], do: :ok, else: {:error, errors}
  end

  def validate_tool_call(_tool_call, _capabilities, opts) do
    path = Keyword.get(opts, :path, [])

    {:error,
     [
       error(path, :invalid_tool_call, "source must be a Resonance.LLM.ToolCall")
     ]}
  end

  @doc "Return the declared dataset names."
  @spec dataset_names(t() | raw()) :: [String.t()]
  def dataset_names(capabilities_or_raw) do
    case normalize(capabilities_or_raw) do
      {:ok, capabilities} -> Enum.map(capabilities.datasets, & &1.name)
      {:error, _} -> []
    end
  end

  defp validate_intent_against_capabilities(%QueryIntent{}, %{datasets: []}, _path),
    do: :ok

  defp validate_intent_against_capabilities(%QueryIntent{} = intent, capabilities, path) do
    case Enum.find(capabilities.datasets, &(&1.name == intent.dataset)) do
      nil ->
        {:error,
         [
           error(path ++ [:dataset], :unknown_dataset, "dataset is not declared", %{
             received: intent.dataset,
             allowed: Enum.map(capabilities.datasets, & &1.name)
           })
         ]}

      dataset ->
        errors =
          []
          |> validate_named_values(
            path ++ [:measures],
            :unsupported_measure,
            "measure is not declared for dataset",
            intent.measures || [],
            names(dataset[:measures])
          )
          |> validate_named_values(
            path ++ [:dimensions],
            :unsupported_dimension,
            "dimension is not declared for dataset",
            intent.dimensions || [],
            names(dataset[:dimensions])
          )
          |> validate_filters(path ++ [:filters], intent.filters || [], dataset[:filters] || [])
          |> validate_sort(path ++ [:sort], intent.sort, dataset)
          |> validate_query_shape(path, intent, dataset)
          |> Enum.reverse()

        if errors == [], do: :ok, else: {:error, errors}
    end
  end

  defp validate_primitive_name(errors, _name, nil, _path), do: errors

  defp validate_primitive_name(errors, name, primitive_names, path)
       when is_list(primitive_names) do
    if name in primitive_names do
      errors
    else
      [
        error(path ++ [:name], :unknown_primitive, "primitive is not registered", %{
          received: name,
          allowed: primitive_names
        })
        | errors
      ]
    end
  end

  defp validate_named_values(errors, _path, _code, _message, [], _allowed), do: errors
  defp validate_named_values(errors, _path, _code, _message, _values, []), do: errors

  defp validate_named_values(errors, path, code, message, values, allowed) do
    values
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {value, index}, acc ->
      if value in allowed do
        acc
      else
        [
          error(path ++ [index], code, message, %{received: value, allowed: allowed})
          | acc
        ]
      end
    end)
  end

  defp validate_filters(errors, _path, [], _filter_specs), do: errors
  defp validate_filters(errors, _path, _filters, []), do: errors

  defp validate_filters(errors, path, filters, filter_specs) do
    filters
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {filter, index}, acc ->
      field = Map.get(filter, :field) || Map.get(filter, "field")
      op = Map.get(filter, :op) || Map.get(filter, "op")

      case Enum.find(filter_specs, &(&1.field == field)) do
        nil ->
          [
            error(path ++ [index, :field], :unsupported_filter, "filter field is not declared", %{
              received: field,
              allowed: Enum.map(filter_specs, & &1.field)
            })
            | acc
          ]

        %{ops: ops} when is_list(ops) and ops != [] ->
          if op in ops do
            acc
          else
            [
              error(path ++ [index, :op], :unsupported_filter_op, "filter op is not declared", %{
                received: op,
                allowed: ops
              })
              | acc
            ]
          end

        _spec ->
          acc
      end
    end)
  end

  defp validate_sort(errors, _path, nil, _dataset), do: errors

  defp validate_sort(errors, path, sort, dataset) do
    field = Map.get(sort, :field) || Map.get(sort, "field")
    allowed = sort_fields(dataset)

    if allowed == [] or field in allowed do
      errors
    else
      [
        error(path ++ [:field], :unsupported_sort_field, "sort field is not declared", %{
          received: field,
          allowed: allowed
        })
        | errors
      ]
    end
  end

  defp validate_query_shape(errors, _path, _intent, %{query_shapes: []}), do: errors

  defp validate_query_shape(errors, path, intent, dataset) do
    if is_list(dataset[:query_shapes]) do
      validate_query_shape_list(errors, path, intent, dataset)
    else
      errors
    end
  end

  defp validate_query_shape_list(errors, path, intent, dataset) do
    dimensions = intent.dimensions || []
    measures = intent.measures || []

    shape =
      Enum.find(dataset.query_shapes, fn shape ->
        shape.dimensions == dimensions and measures_allowed_by_shape?(measures, shape)
      end)

    if shape do
      errors
    else
      [
        error(path ++ [:dimensions], :unsupported_query_shape, "query shape is not declared", %{
          dimensions: dimensions,
          measures: measures,
          allowed: Enum.map(dataset.query_shapes, &Map.take(&1, [:dimensions, :measures]))
        })
        | errors
      ]
    end
  end

  defp measures_allowed_by_shape?(_measures, %{measures: []}), do: true

  defp measures_allowed_by_shape?(measures, %{measures: allowed}),
    do: Enum.all?(measures, &(&1 in allowed))

  defp measures_allowed_by_shape?(_measures, _shape), do: true

  defp sort_fields(dataset) do
    []
    |> Kernel.++(names(dataset[:fields]))
    |> Kernel.++(names(dataset[:measures]))
    |> Kernel.++(names(dataset[:dimensions]))
    |> Kernel.++(Enum.map(dataset[:filters] || [], & &1.field))
    |> Enum.uniq()
  end

  defp description_lines(capabilities) do
    [
      capabilities[:description],
      "Datasets:",
      Enum.map_join(capabilities.datasets, "\n", &dataset_line/1),
      notes_lines(capabilities[:notes] || [])
    ]
  end

  defp dataset_line(dataset) do
    [
      "- #{inspect(dataset.name)}#{description_suffix(dataset)}",
      "  fields: #{join_names(dataset[:fields])}",
      "  measures: #{join_names(dataset[:measures])}",
      "  dimensions: #{join_names(dataset[:dimensions])}",
      filter_line(dataset[:filters] || []),
      query_shape_line(dataset[:query_shapes] || [])
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  defp description_suffix(%{description: description})
       when is_binary(description) and description != "",
       do: " — #{description}"

  defp description_suffix(_dataset), do: ""

  defp filter_line([]), do: nil

  defp filter_line(filters) do
    rendered =
      Enum.map_join(filters, ", ", fn filter ->
        ops =
          case filter[:ops] do
            ops when is_list(ops) and ops != [] -> " ops: #{Enum.join(ops, "/")}"
            _ -> ""
          end

        "#{filter.field}#{ops}"
      end)

    "  filters: #{rendered}"
  end

  defp query_shape_line([]), do: nil

  defp query_shape_line(shapes) do
    rendered =
      Enum.map_join(shapes, "; ", fn shape ->
        dims = if shape.dimensions == [], do: "<none>", else: Enum.join(shape.dimensions, ", ")

        measures =
          if shape[:measures] in [nil, []], do: "<any>", else: Enum.join(shape.measures, ", ")

        "dimensions [#{dims}] with measures [#{measures}]"
      end)

    "  query shapes: #{rendered}"
  end

  defp notes_lines([]), do: nil
  defp notes_lines(notes), do: "Notes:\n" <> Enum.map_join(notes, "\n", &"- #{&1}")

  defp validate_dataset_list(errors, datasets) when is_list(datasets) do
    datasets
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {dataset, index}, acc ->
      validate_dataset(acc, dataset, index)
    end)
    |> validate_duplicate_dataset_names(datasets)
  end

  defp validate_dataset_list(errors, datasets) do
    [
      error([:datasets], :invalid_datasets, "datasets must be a list", %{received: datasets})
      | errors
    ]
  end

  defp validate_dataset(errors, %{} = dataset, index) do
    name = fetch(dataset, "name")

    errors =
      if is_binary(name) and String.trim(name) != "" do
        errors
      else
        [
          error([:datasets, index, :name], :invalid_dataset_name, "dataset name is required", %{
            received: name
          })
          | errors
        ]
      end

    errors
    |> validate_named_spec_list(dataset, "fields", index)
    |> validate_named_spec_list(dataset, "measures", index)
    |> validate_named_spec_list(dataset, "dimensions", index)
    |> validate_filter_spec_list(dataset, index)
    |> validate_query_shape_spec_list(dataset, index)
  end

  defp validate_dataset(errors, dataset, index) do
    [
      error([:datasets, index], :invalid_dataset, "dataset must be a map", %{received: dataset})
      | errors
    ]
  end

  defp validate_duplicate_dataset_names(errors, datasets) do
    duplicate_names =
      datasets
      |> Enum.flat_map(fn
        %{} = dataset ->
          case fetch(dataset, "name") do
            name when is_binary(name) and name != "" -> [name]
            _ -> []
          end

        _ ->
          []
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    Enum.reduce(duplicate_names, errors, fn name, acc ->
      [
        error([:datasets, name, :name], :duplicate_dataset_name, "dataset name must be unique", %{
          name: name
        })
        | acc
      ]
    end)
  end

  defp validate_named_spec_list(errors, dataset, key, index) do
    case fetch(dataset, key) do
      nil ->
        errors

      values when is_list(values) ->
        values
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {value, value_index}, acc ->
          validate_named_spec(acc, value, [
            :datasets,
            index,
            String.to_existing_atom(key),
            value_index
          ])
        end)

      value ->
        [
          error(
            [:datasets, index, String.to_existing_atom(key)],
            :invalid_capability_list,
            "#{key} must be a list",
            %{received: value}
          )
          | errors
        ]
    end
  end

  defp validate_named_spec(errors, value, _path) when is_binary(value), do: errors

  defp validate_named_spec(errors, %{} = value, path) do
    name = fetch(value, "name")

    if is_binary(name) and String.trim(name) != "" do
      errors
    else
      [
        error(path ++ [:name], :invalid_capability_spec, "capability spec name is required", %{
          received: name
        })
        | errors
      ]
    end
  end

  defp validate_named_spec(errors, value, path) do
    [
      error(path, :invalid_capability_spec, "capability spec must be a string or map", %{
        received: value
      })
      | errors
    ]
  end

  defp validate_filter_spec_list(errors, dataset, index) do
    case fetch(dataset, "filters") do
      nil ->
        errors

      filters when is_list(filters) ->
        filters
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {filter, filter_index}, acc ->
          validate_filter_spec(acc, filter, [:datasets, index, :filters, filter_index])
        end)

      filters ->
        [
          error(
            [:datasets, index, :filters],
            :invalid_capability_list,
            "filters must be a list",
            %{
              received: filters
            }
          )
          | errors
        ]
    end
  end

  defp validate_filter_spec(errors, field, _path) when is_binary(field), do: errors

  defp validate_filter_spec(errors, %{} = filter, path) do
    field = fetch(filter, "field") || fetch(filter, "name")
    ops = fetch(filter, "ops") || fetch(filter, "operators")

    errors =
      if is_binary(field) and String.trim(field) != "" do
        errors
      else
        [
          error(path ++ [:field], :invalid_filter_spec, "filter field is required", %{
            received: field
          })
          | errors
        ]
      end

    if is_nil(ops) or string_list?(ops) do
      errors
    else
      [
        error(path ++ [:ops], :invalid_filter_ops, "filter ops must be strings", %{
          received: ops
        })
        | errors
      ]
    end
  end

  defp validate_filter_spec(errors, filter, path) do
    [
      error(path, :invalid_filter_spec, "filter spec must be a string or map", %{received: filter})
      | errors
    ]
  end

  defp validate_query_shape_spec_list(errors, dataset, index) do
    case fetch(dataset, "query_shapes") do
      nil ->
        errors

      shapes when is_list(shapes) ->
        shapes
        |> Enum.with_index()
        |> Enum.reduce(errors, fn {shape, shape_index}, acc ->
          validate_query_shape_spec(acc, shape, [:datasets, index, :query_shapes, shape_index])
        end)

      shapes ->
        [
          error(
            [:datasets, index, :query_shapes],
            :invalid_capability_list,
            "query_shapes must be a list",
            %{received: shapes}
          )
          | errors
        ]
    end
  end

  defp validate_query_shape_spec(errors, %{} = shape, path) do
    errors
    |> validate_optional_string_list(shape, "dimensions", path)
    |> validate_optional_string_list(shape, "measures", path)
  end

  defp validate_query_shape_spec(errors, shape, path) do
    [
      error(path, :invalid_query_shape_spec, "query shape spec must be a map", %{
        received: shape
      })
      | errors
    ]
  end

  defp validate_optional_string_list(errors, map, key, path) do
    value = fetch(map, key)

    if is_nil(value) or string_list?(value) do
      errors
    else
      [
        error(
          path ++ [String.to_existing_atom(key)],
          :invalid_capability_list,
          "#{key} must be a list of strings",
          %{received: value}
        )
        | errors
      ]
    end
  end

  defp normalize_datasets(datasets) do
    Enum.map(datasets, fn dataset ->
      %{
        name: fetch(dataset, "name"),
        description: fetch(dataset, "description"),
        fields: normalize_named_specs(fetch(dataset, "fields") || []),
        measures: normalize_named_specs(fetch(dataset, "measures") || []),
        dimensions: normalize_named_specs(fetch(dataset, "dimensions") || []),
        filters: normalize_filter_specs(fetch(dataset, "filters") || []),
        query_shapes: normalize_query_shapes(fetch(dataset, "query_shapes") || [])
      }
    end)
  end

  defp normalize_named_specs(values) when is_list(values) do
    Enum.flat_map(values, fn
      value when is_binary(value) ->
        [%{name: value}]

      %{} = value ->
        case fetch(value, "name") do
          name when is_binary(name) and name != "" ->
            [
              %{
                name: name,
                description: fetch(value, "description"),
                type: fetch(value, "type"),
                values: fetch(value, "values") || []
              }
            ]

          _ ->
            []
        end

      _other ->
        []
    end)
  end

  defp normalize_named_specs(_values), do: []

  defp normalize_filter_specs(filters) when is_list(filters) do
    Enum.flat_map(filters, fn
      field when is_binary(field) ->
        [%{field: field}]

      %{} = filter ->
        field = fetch(filter, "field") || fetch(filter, "name")

        if is_binary(field) and field != "" do
          [
            %{
              field: field,
              description: fetch(filter, "description"),
              ops:
                normalize_string_list(fetch(filter, "ops") || fetch(filter, "operators") || []),
              values: fetch(filter, "values") || []
            }
          ]
        else
          []
        end

      _other ->
        []
    end)
  end

  defp normalize_filter_specs(_filters), do: []

  defp normalize_query_shapes(shapes) when is_list(shapes) do
    Enum.flat_map(shapes, fn
      %{} = shape ->
        [
          %{
            dimensions: normalize_string_list(fetch(shape, "dimensions") || []),
            measures: normalize_string_list(fetch(shape, "measures") || []),
            description: fetch(shape, "description")
          }
        ]

      _other ->
        []
    end)
  end

  defp normalize_query_shapes(_shapes), do: []

  defp normalize_notes(notes) when is_list(notes), do: Enum.filter(notes, &is_binary/1)
  defp normalize_notes(note) when is_binary(note), do: [note]
  defp normalize_notes(_notes), do: []

  defp string_list?(values) when is_list(values), do: Enum.all?(values, &is_binary/1)
  defp string_list?(_values), do: false

  defp normalize_string_list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_string_list(_values), do: []

  defp names(nil), do: []
  defp names(specs), do: Enum.map(specs, & &1.name)
  defp join_names(nil), do: "<none>"
  defp join_names([]), do: "<none>"
  defp join_names(specs), do: specs |> names() |> Enum.join(", ")

  defp fetch(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, safe_existing_atom(key))
  end

  defp fetch(_map, _key), do: nil

  defp safe_existing_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp error(path, code, message, details \\ %{}) do
    base = %{path: path, code: code, message: message}

    if details == %{} do
      base
    else
      Map.put(base, :details, details)
    end
  end
end
