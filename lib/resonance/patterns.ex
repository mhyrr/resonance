defmodule Resonance.Patterns do
  @moduledoc """
  Planner-facing pattern manifest for workspace sections.

  Patterns are named presentation intentions, not Phoenix components. The
  planner sees names, descriptions, compatible roles, and compatible primitive
  sources. It does not see HEEx, component modules, CSS classes, or atom trees.
  """

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan.Section

  @type spec :: %{
          required(:name) => atom(),
          optional(:description) => String.t(),
          optional(:roles) => [atom()],
          optional(:result_kinds) => [atom()],
          optional(:source_primitives) => [String.t()]
        }

  @type error :: %{
          required(:path) => [atom() | String.t() | non_neg_integer()],
          required(:code) => atom(),
          required(:message) => String.t(),
          optional(:details) => map()
        }

  @primitive_result_kinds %{
    "compare_over_time" => :comparison,
    "rank_entities" => :ranking,
    "show_distribution" => :distribution,
    "summarize_findings" => :summary,
    "segment_population" => :segmentation
  }

  @default_manifest [
    %{
      name: :prose_summary,
      description: "Narrative summary for an analytical section.",
      roles: [:summary],
      result_kinds: [:summary],
      source_primitives: ["summarize_findings"]
    },
    %{
      name: :metric_strip,
      description: "Compact metric comparison across segments.",
      roles: [:primary, :supporting_context],
      result_kinds: [:segmentation],
      source_primitives: ["segment_population"]
    },
    %{
      name: :entity_list,
      description: "Ranked list of entities for focused inspection.",
      roles: [:focus_list, :detail, :primary, :supporting_context],
      result_kinds: [:ranking],
      source_primitives: ["rank_entities"]
    },
    %{
      name: :trend_panel,
      description: "Time-series trend section.",
      roles: [:primary, :supporting_context],
      result_kinds: [:comparison],
      source_primitives: ["compare_over_time"]
    },
    %{
      name: :summary_panel,
      description: "Compact categorical breakdown or supporting chart.",
      roles: [:primary, :supporting_context],
      result_kinds: [:distribution, :ranking, :segmentation],
      source_primitives: ["show_distribution", "rank_entities", "segment_population"]
    },
    %{
      name: :comparison_panel,
      description: "Comparison section for temporal or grouped comparisons.",
      roles: [:primary, :supporting_context],
      result_kinds: [:comparison],
      source_primitives: ["compare_over_time"]
    },
    %{
      name: :data_table,
      description: "Tabular detail section for larger result sets.",
      roles: [:primary, :focus_list, :supporting_context, :detail],
      result_kinds: [:comparison, :ranking, :distribution, :segmentation],
      source_primitives: [
        "compare_over_time",
        "rank_entities",
        "show_distribution",
        "segment_population"
      ]
    }
  ]

  @doc "Default built-in workspace pattern manifest."
  @spec default_manifest() :: [spec()]
  def default_manifest, do: @default_manifest

  @doc """
  Return the built-in manifest plus app-declared patterns.

  If an app declares a pattern with a built-in name, the app declaration wins.
  """
  @spec manifest([map()] | module() | nil) :: [spec()]
  def manifest(custom_specs \\ [])

  def manifest(nil), do: @default_manifest

  def manifest(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :manifest, 0) do
          module.manifest()
          |> manifest()
        else
          @default_manifest
        end

      {:error, _reason} ->
        @default_manifest
    end
  end

  def manifest(custom_specs) when is_list(custom_specs) do
    custom_specs
    |> Enum.map(&normalize_spec/1)
    |> Enum.reject(&is_nil/1)
    |> merge_with_defaults()
  end

  def manifest(_custom_specs), do: @default_manifest

  @doc "Build a pattern manifest from planner/compiler context."
  @spec from_context(map() | nil) :: [spec()]
  def from_context(context) when is_map(context) do
    context
    |> fetch_pattern_specs()
    |> manifest()
  end

  def from_context(_context), do: @default_manifest

  @doc "Build a pattern manifest from validation options."
  @spec from_opts(keyword()) :: [spec()]
  def from_opts(opts) when is_list(opts) do
    opts
    |> Keyword.get(:patterns, Keyword.get(opts, :pattern_manifest))
    |> manifest()
  end

  def from_opts(_opts), do: @default_manifest

  @doc "Names available to the planner and workspace validator."
  @spec names([spec()]) :: [atom()]
  def names(manifest), do: Enum.map(manifest, & &1.name)

  @doc "Find a pattern spec by atom name."
  @spec get([spec()], atom()) :: spec() | nil
  def get(manifest, name) when is_atom(name), do: Enum.find(manifest, &(&1.name == name))
  def get(_manifest, _name), do: nil

  @doc """
  Validate that a section's pattern is compatible with its role and source.
  """
  @spec validate_section(Section.t(), [spec()], keyword()) :: :ok | {:error, [error()]}
  def validate_section(%Section{} = section, manifest, opts \\ []) do
    path = Keyword.get(opts, :path, [])

    errors =
      []
      |> validate_pattern_exists(section, manifest, path)
      |> validate_pattern_role(section, manifest, path)
      |> validate_pattern_source(section, manifest, path)
      |> Enum.reverse()

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc """
  Render planner-facing pattern descriptions.
  """
  @spec format_for_prompt([spec()]) :: String.t()
  def format_for_prompt(manifest) do
    manifest
    |> Enum.map(&format_pattern/1)
    |> Enum.join("\n")
  end

  @doc "Known Result kind produced by a built-in primitive."
  @spec primitive_result_kind(String.t()) :: atom() | nil
  def primitive_result_kind(name), do: Map.get(@primitive_result_kinds, name)

  defp validate_pattern_exists(errors, %Section{pattern: pattern}, manifest, path) do
    if get(manifest, pattern) do
      errors
    else
      [
        error(path ++ [:pattern], :unsupported_pattern, "section pattern is not supported", %{
          received: pattern,
          allowed: names(manifest)
        })
        | errors
      ]
    end
  end

  defp validate_pattern_role(errors, %Section{pattern: pattern, role: role}, manifest, path) do
    case get(manifest, pattern) do
      %{roles: roles} when is_list(roles) ->
        if role in roles do
          errors
        else
          [
            error(
              path ++ [:pattern],
              :incompatible_pattern_role,
              "section pattern is not compatible with role",
              %{pattern: pattern, role: role, allowed_roles: roles}
            )
            | errors
          ]
        end

      _spec ->
        errors
    end
  end

  defp validate_pattern_source(
         errors,
         %Section{
           pattern: pattern,
           source: {:tool_call, %ToolCall{name: primitive_name}}
         },
         manifest,
         path
       ) do
    case get(manifest, pattern) do
      nil ->
        errors

      spec ->
        validate_source_primitive(errors, spec, primitive_name, path)
    end
  end

  defp validate_pattern_source(errors, _section, _manifest, _path), do: errors

  defp validate_source_primitive(errors, spec, primitive_name, path) do
    allowed_primitives = spec[:source_primitives] || []

    cond do
      allowed_primitives != [] and primitive_name not in allowed_primitives ->
        [
          error(
            path ++ [:source, :tool_call, :name],
            :incompatible_pattern_source,
            "section pattern is not compatible with source primitive",
            %{
              pattern: spec.name,
              primitive: primitive_name,
              allowed_primitives: allowed_primitives
            }
          )
          | errors
        ]

      true ->
        validate_source_result_kind(errors, spec, primitive_name, path)
    end
  end

  defp validate_source_result_kind(errors, spec, primitive_name, path) do
    allowed_kinds = spec[:result_kinds] || []
    result_kind = primitive_result_kind(primitive_name)

    if (result_kind && allowed_kinds != []) and result_kind not in allowed_kinds do
      [
        error(
          path ++ [:source, :tool_call, :name],
          :incompatible_pattern_result_kind,
          "section pattern is not compatible with source result kind",
          %{
            pattern: spec.name,
            primitive: primitive_name,
            result_kind: result_kind,
            allowed_kinds: allowed_kinds
          }
        )
        | errors
      ]
    else
      errors
    end
  end

  defp format_pattern(spec) do
    roles = spec |> Map.get(:roles, []) |> join_atoms()
    result_kinds = spec |> Map.get(:result_kinds, []) |> join_atoms()
    primitives = spec |> Map.get(:source_primitives, []) |> Enum.join(", ")
    description = spec[:description] || ""

    "- #{spec.name}: #{description} roles=[#{roles}] result_kinds=[#{result_kinds}] source_primitives=[#{primitives}]"
  end

  defp fetch_pattern_specs(context) do
    Map.get(context, :patterns) ||
      Map.get(context, "patterns") ||
      Map.get(context, :pattern_manifest) ||
      Map.get(context, "pattern_manifest")
  end

  defp normalize_spec(%{} = spec) do
    with name when is_atom(name) and not is_nil(name) <-
           Map.get(spec, :name) || Map.get(spec, "name") do
      %{
        name: name,
        description: Map.get(spec, :description) || Map.get(spec, "description"),
        roles: normalize_atoms(Map.get(spec, :roles) || Map.get(spec, "roles") || []),
        result_kinds:
          normalize_atoms(Map.get(spec, :result_kinds) || Map.get(spec, "result_kinds") || []),
        source_primitives:
          normalize_strings(
            Map.get(spec, :source_primitives) || Map.get(spec, "source_primitives") || []
          )
      }
    else
      _other -> nil
    end
  end

  defp normalize_spec(_spec), do: nil

  defp merge_with_defaults(custom_specs) do
    (@default_manifest ++ custom_specs)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.name)
    |> Enum.reverse()
  end

  defp normalize_atoms(values) when is_list(values), do: Enum.filter(values, &is_atom/1)
  defp normalize_atoms(_values), do: []

  defp normalize_strings(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_strings(_values), do: []

  defp join_atoms(values), do: values |> Enum.map(&Atom.to_string/1) |> Enum.join(", ")

  defp error(path, code, message, details) do
    base = %{path: path, code: code, message: message}

    if details == %{} do
      base
    else
      Map.put(base, :details, details)
    end
  end
end
