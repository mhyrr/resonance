defmodule Resonance.WorkspacePlan.Validation do
  @moduledoc """
  Validation for `Resonance.WorkspacePlan`.

  Validation is intentionally deterministic and side-effect free. It does not
  call resolvers, presenters, providers, or app code. Invalid plans fail before
  any section source can execute.
  """

  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan
  alias Resonance.WorkspacePlan.Section

  @allowed_layouts [:stack, :dashboard_grid, :overview_with_detail]
  @allowed_roles [:summary, :primary, :focus_list, :supporting_context, :detail]
  @allowed_patterns [
    :prose_summary,
    :metric_strip,
    :entity_list,
    :trend_panel,
    :summary_panel,
    :comparison_panel,
    :data_table
  ]

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
  @spec allowed_patterns() :: [Section.pattern()]
  def allowed_patterns, do: @allowed_patterns

  @doc """
  Validate a workspace plan.
  """
  @spec validate(WorkspacePlan.t()) ::
          {:ok, WorkspacePlan.t()} | {:error, {:validation_failed, [error()]}}
  def validate(%WorkspacePlan{} = plan) do
    errors =
      []
      |> validate_goal(plan.goal)
      |> validate_title(plan.title)
      |> validate_layout(plan.layout)
      |> validate_sections(plan.sections)
      |> validate_refinements(plan.refinements)
      |> validate_identity(plan.identity)
      |> Enum.reverse()

    if errors == [] do
      {:ok, plan}
    else
      {:error, {:validation_failed, errors}}
    end
  end

  defp validate_goal(errors, goal) when is_atom(goal) and not is_nil(goal), do: errors

  defp validate_goal(errors, goal) do
    add_error(errors, [:goal], :invalid_goal, "goal must be a non-nil atom", %{
      received: goal
    })
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

  defp validate_sections(errors, sections) when is_list(sections) do
    errors
    |> validate_sections_present(sections)
    |> validate_duplicate_section_ids(sections)
    |> validate_each_section(sections)
  end

  defp validate_sections(errors, sections) do
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

  defp validate_each_section(errors, sections) do
    sections
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {section, index}, acc ->
      validate_section(acc, section, index)
    end)
  end

  defp validate_section(errors, %Section{} = section, index) do
    key = section_key(section, index)

    errors
    |> validate_section_id(section, key)
    |> validate_section_role(section, key)
    |> validate_section_pattern(section, key)
    |> validate_section_source(section, key)
    |> validate_section_interactions(section, key)
    |> validate_section_depends_on(section, key)
    |> validate_section_metadata(section, key)
  end

  defp validate_section(errors, section, index) do
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

  defp validate_section_pattern(errors, %Section{pattern: pattern}, _key)
       when pattern in @allowed_patterns,
       do: errors

  defp validate_section_pattern(errors, %Section{pattern: pattern}, key) do
    add_error(
      errors,
      [:sections, key, :pattern],
      :unsupported_pattern,
      "section pattern is not supported",
      %{allowed: @allowed_patterns, received: pattern}
    )
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
