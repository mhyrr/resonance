defmodule Resonance.WorkspacePlan.Validation do
  @moduledoc """
  Validation for `Resonance.WorkspacePlan`.

  Validation is intentionally deterministic and side-effect free. It does not
  call resolvers, presenters, providers, or app code. Invalid plans fail before
  any section source can execute.
  """

  alias Resonance.{Patterns, WorkspacePlan}
  alias Resonance.LLM.ToolCall
  alias Resonance.Resolver.Capabilities
  alias Resonance.WorkspacePlan.Section

  @allowed_layouts [:stack, :dashboard_grid, :overview_with_detail]
  @allowed_roles [:summary, :primary, :focus_list, :supporting_context, :detail]

  @type error :: %{
          required(:path) => [atom() | String.t() | non_neg_integer()],
          required(:code) => atom(),
          required(:message) => String.t(),
          optional(:details) => map()
        }

  @doc "Allowed Phase 1 workspace layouts."
  @spec allowed_layouts() :: [WorkspacePlan.layout()]
  def allowed_layouts, do: @allowed_layouts

  @doc "Allowed Phase 1 section roles."
  @spec allowed_roles() :: [Section.role()]
  def allowed_roles, do: @allowed_roles

  @doc "Allowed Phase 1 section patterns."
  @spec allowed_patterns(keyword()) :: [Section.pattern()]
  def allowed_patterns(opts \\ []), do: opts |> Patterns.from_opts() |> Patterns.names()

  @doc """
  Validate a workspace plan.
  """
  @spec validate(WorkspacePlan.t(), keyword()) ::
          {:ok, WorkspacePlan.t()} | {:error, {:validation_failed, [error()]}}
  def validate(%WorkspacePlan{} = plan, opts \\ []) do
    pattern_manifest = Patterns.from_opts(opts)

    errors =
      []
      |> validate_goal(plan.goal)
      |> validate_title(plan.title)
      |> validate_layout(plan.layout)
      |> validate_sections(plan.sections, pattern_manifest)
      |> validate_refinements(plan.refinements)
      |> validate_identity(plan.identity)
      |> validate_capabilities(plan, opts)
      |> Enum.reverse()

    if errors == [] do
      {:ok, plan}
    else
      {:error, {:validation_failed, errors}}
    end
  end

  defp validate_goal(errors, goal) when is_atom(goal) and not is_nil(goal), do: errors
  defp validate_goal(errors, goal) when is_binary(goal) and byte_size(goal) > 0, do: errors

  defp validate_goal(errors, goal) do
    add_error(
      errors,
      [:goal],
      :invalid_goal,
      "goal must be a non-empty string or non-nil atom",
      %{
        received: goal
      }
    )
  end

  defp validate_title(errors, title) when is_binary(title) and byte_size(title) > 0, do: errors

  defp validate_title(errors, title) do
    add_error(errors, [:title], :invalid_title, "title must be a non-empty string", %{
      received: title
    })
  end

  defp validate_layout(errors, layout) when layout in @allowed_layouts, do: errors

  defp validate_layout(errors, layout) do
    add_error(errors, [:layout], :unsupported_layout, "layout is not supported", %{
      allowed: @allowed_layouts,
      received: layout
    })
  end

  defp validate_sections(errors, sections, pattern_manifest) when is_list(sections) do
    errors
    |> validate_sections_present(sections)
    |> validate_duplicate_section_ids(sections)
    |> validate_each_section(sections, pattern_manifest)
  end

  defp validate_sections(errors, sections, _pattern_manifest) do
    add_error(errors, [:sections], :invalid_sections, "sections must be a list", %{
      received: sections
    })
  end

  defp validate_sections_present(errors, []),
    do: add_error(errors, [:sections], :missing_sections, "sections cannot be empty")

  defp validate_sections_present(errors, _sections), do: errors

  defp validate_duplicate_section_ids(errors, sections) do
    duplicate_ids =
      sections
      |> Enum.flat_map(fn
        %Section{id: id} when is_binary(id) and byte_size(id) > 0 -> [id]
        _ -> []
      end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)

    Enum.reduce(duplicate_ids, errors, fn id, acc ->
      add_error(acc, [:sections, id, :id], :duplicate_section_id, "section id must be unique", %{
        id: id
      })
    end)
  end

  defp validate_each_section(errors, sections, pattern_manifest) do
    sections
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {section, index}, acc ->
      validate_section(acc, section, index, pattern_manifest)
    end)
  end

  defp validate_section(errors, %Section{} = section, index, pattern_manifest) do
    key = section_key(section, index)

    errors
    |> validate_section_id(section, key)
    |> validate_section_role(section, key)
    |> validate_section_pattern(section, key, pattern_manifest)
    |> validate_section_source(section, key)
    |> validate_section_pattern_compatibility(section, key, pattern_manifest)
    |> validate_section_interactions(section, key)
    |> validate_section_depends_on(section, key)
    |> validate_section_metadata(section, key)
  end

  defp validate_section(errors, section, index, _pattern_manifest) do
    add_error(
      errors,
      [:sections, index],
      :invalid_section,
      "section must be a WorkspacePlan.Section",
      %{
        received: section
      }
    )
  end

  defp validate_section_id(errors, %Section{id: id}, _key)
       when is_binary(id) and byte_size(id) > 0,
       do: errors

  defp validate_section_id(errors, %Section{id: id}, key) do
    add_error(
      errors,
      [:sections, key, :id],
      :invalid_section_id,
      "section id must be a non-empty string",
      %{
        received: id
      }
    )
  end

  defp validate_section_role(errors, %Section{role: role}, _key) when role in @allowed_roles,
    do: errors

  defp validate_section_role(errors, %Section{role: role}, key) do
    add_error(
      errors,
      [:sections, key, :role],
      :unsupported_role,
      "section role is not supported",
      %{
        allowed: @allowed_roles,
        received: role
      }
    )
  end

  defp validate_section_pattern(errors, %Section{pattern: pattern}, key, pattern_manifest) do
    allowed_patterns = Patterns.names(pattern_manifest)

    if pattern in allowed_patterns do
      errors
    else
      add_error(
        errors,
        [:sections, key, :pattern],
        :unsupported_pattern,
        "section pattern is not supported",
        %{allowed: allowed_patterns, received: pattern}
      )
    end
  end

  defp validate_section_source(
         errors,
         %Section{source: {:tool_call, %ToolCall{name: name, arguments: arguments}}},
         key
       ) do
    errors
    |> validate_tool_call_name(name, key)
    |> validate_tool_call_arguments(arguments, key)
  end

  defp validate_section_source(errors, %Section{source: source}, key) do
    add_error(
      errors,
      [:sections, key, :source],
      :invalid_source,
      "section source must be {:tool_call, %Resonance.LLM.ToolCall{}}",
      %{received: source}
    )
  end

  defp validate_tool_call_name(errors, name, _key) when is_binary(name) and byte_size(name) > 0,
    do: errors

  defp validate_tool_call_name(errors, name, key) do
    add_error(
      errors,
      [:sections, key, :source, :tool_call, :name],
      :invalid_tool_call_name,
      "tool call name must be a non-empty string",
      %{received: name}
    )
  end

  defp validate_tool_call_arguments(errors, arguments, _key) when is_map(arguments), do: errors

  defp validate_tool_call_arguments(errors, arguments, key) do
    add_error(
      errors,
      [:sections, key, :source, :tool_call, :arguments],
      :invalid_tool_call_arguments,
      "tool call arguments must be a map",
      %{received: arguments}
    )
  end

  defp validate_section_pattern_compatibility(
         errors,
         %Section{
           role: role,
           pattern: pattern,
           source: {:tool_call, %ToolCall{name: name}}
         } = section,
         key,
         pattern_manifest
       )
       when role in @allowed_roles and is_binary(name) and byte_size(name) > 0 do
    if Patterns.get(pattern_manifest, pattern) do
      case Patterns.validate_section(section, pattern_manifest, path: [:sections, key]) do
        :ok -> errors
        {:error, pattern_errors} -> pattern_errors ++ errors
      end
    else
      errors
    end
  end

  defp validate_section_pattern_compatibility(errors, _section, _key, _pattern_manifest),
    do: errors

  defp validate_section_interactions(errors, %Section{interactions: interactions}, key)
       when is_list(interactions) do
    if Enum.all?(interactions, &is_atom/1) do
      errors
    else
      add_error(
        errors,
        [:sections, key, :interactions],
        :invalid_interactions,
        "interactions must be atoms"
      )
    end
  end

  defp validate_section_interactions(errors, %Section{interactions: interactions}, key) do
    add_error(
      errors,
      [:sections, key, :interactions],
      :invalid_interactions,
      "interactions must be a list of atoms",
      %{received: interactions}
    )
  end

  defp validate_section_depends_on(errors, %Section{depends_on: depends_on}, key)
       when is_list(depends_on) do
    if Enum.all?(depends_on, &is_binary/1) do
      errors
    else
      add_error(
        errors,
        [:sections, key, :depends_on],
        :invalid_depends_on,
        "depends_on must be section id strings"
      )
    end
  end

  defp validate_section_depends_on(errors, %Section{depends_on: depends_on}, key) do
    add_error(
      errors,
      [:sections, key, :depends_on],
      :invalid_depends_on,
      "depends_on must be a list of section id strings",
      %{received: depends_on}
    )
  end

  defp validate_section_metadata(errors, %Section{metadata: metadata}, _key)
       when is_map(metadata),
       do: errors

  defp validate_section_metadata(errors, %Section{metadata: metadata}, key) do
    add_error(
      errors,
      [:sections, key, :metadata],
      :invalid_metadata,
      "metadata must be a map",
      %{received: metadata}
    )
  end

  defp validate_refinements(errors, refinements) when is_list(refinements), do: errors

  defp validate_refinements(errors, refinements) do
    add_error(errors, [:refinements], :invalid_refinements, "refinements must be a list", %{
      received: refinements
    })
  end

  defp validate_identity(errors, identity) when is_map(identity), do: errors

  defp validate_identity(errors, identity) do
    add_error(errors, [:identity], :invalid_identity, "identity must be a map", %{
      received: identity
    })
  end

  defp validate_capabilities(errors, _plan, opts) when opts == [], do: errors

  defp validate_capabilities(errors, %WorkspacePlan{sections: sections}, opts)
       when is_list(sections) do
    capabilities = Keyword.get(opts, :capabilities)
    primitive_names = Keyword.get(opts, :primitive_names)

    if is_nil(capabilities) and is_nil(primitive_names) do
      errors
    else
      sections
      |> Enum.with_index()
      |> Enum.reduce(errors, fn
        {%Section{source: {:tool_call, %ToolCall{} = tool_call}} = section, index}, acc ->
          key = section_key(section, index)

          case Capabilities.validate_tool_call(tool_call, capabilities || %{},
                 path: [:sections, key, :source, :tool_call],
                 primitive_names: primitive_names
               ) do
            :ok -> acc
            {:error, capability_errors} -> capability_errors ++ acc
          end

        {_section, _index}, acc ->
          acc
      end)
    end
  end

  defp validate_capabilities(errors, _plan, _opts), do: errors

  defp section_key(%Section{id: id}, _index) when is_binary(id) and byte_size(id) > 0, do: id
  defp section_key(_section, index), do: index

  defp add_error(errors, path, code, message, details \\ %{}) do
    error = %{path: path, code: code, message: message}

    error =
      if details == %{} do
        error
      else
        Map.put(error, :details, details)
      end

    [error | errors]
  end
end
