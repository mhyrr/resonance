defmodule Resonance.WorkspaceCompiler do
  @moduledoc """
  Deterministic compiler for hand-written workspace plans.

  The compiler validates a `Resonance.WorkspacePlan`, resolves each section's
  stored tool call through the existing composer/presenter path, and returns
  existing `Resonance.Renderable` values grouped by section metadata.

  This module does not call an LLM, persist workspaces, own app data, or render
  Phoenix surfaces. It only turns a valid plan into the renderables today's
  report pipeline already knows how to display.
  """

  alias Resonance.{Composer, Renderable, WorkspacePlan}
  alias Resonance.LLM.ToolCall
  alias Resonance.WorkspacePlan.Section

  @type compiled_section :: %{
          required(:id) => String.t(),
          required(:role) => Section.role(),
          required(:pattern) => Section.pattern(),
          required(:section) => Section.t(),
          required(:renderable) => Renderable.t()
        }

  @type compiled_workspace :: %{
          required(:plan) => WorkspacePlan.t(),
          required(:sections) => [compiled_section()],
          required(:renderables) => [Renderable.t()]
        }

  @doc """
  Compile a validated workspace plan into existing renderables.
  """
  @spec compile(WorkspacePlan.t(), map()) ::
          {:ok, compiled_workspace()} | {:error, {:validation_failed, [map()]}}
  def compile(%WorkspacePlan{} = plan, context \\ %{}) when is_map(context) do
    with {:ok, validated_plan} <- WorkspacePlan.validate(plan) do
      compiled_sections =
        Enum.map(validated_plan.sections, fn section ->
          compile_section(validated_plan, section, context)
        end)

      {:ok,
       %{
         plan: validated_plan,
         sections: compiled_sections,
         renderables: Enum.map(compiled_sections, & &1.renderable)
       }}
    end
  end

  @doc """
  Build the stable renderable ID for a compiled workspace section.

  The ID is deterministic for the same workspace identity, section ID, and
  renderable type. If the plan has no stable identity yet, the ID is still
  stable within the plan shape; TK-065 adds serializable fingerprints.
  """
  @spec stable_renderable_id(WorkspacePlan.t(), Section.t(), Renderable.t()) :: String.t()
  def stable_renderable_id(
        %WorkspacePlan{} = plan,
        %Section{} = section,
        %Renderable{} = renderable
      ) do
    ["workspace", identity_part(plan.identity), section.id, renderable.type]
    |> Enum.reject(&blank?/1)
    |> Enum.map_join("-", &slug/1)
  end

  defp compile_section(
         %WorkspacePlan{} = plan,
         %Section{source: {:tool_call, %ToolCall{} = tool_call}} = section,
         context
       ) do
    renderable =
      try do
        Composer.resolve_one(tool_call, context)
      rescue
        e -> Renderable.error(tool_call.name, {:compile_failed, Exception.message(e)})
      catch
        :exit, reason -> Renderable.error(tool_call.name, {:compile_exit, inspect(reason)})
      end

    renderable = %{renderable | id: stable_renderable_id(plan, section, renderable)}

    %{
      id: section.id,
      role: section.role,
      pattern: section.pattern,
      section: section,
      renderable: renderable
    }
  end

  defp identity_part(%{id: id}), do: id
  defp identity_part(%{"id" => id}), do: id
  defp identity_part(%{fingerprint: fingerprint}), do: fingerprint
  defp identity_part(%{"fingerprint" => fingerprint}), do: fingerprint
  defp identity_part(%{key: key}), do: key
  defp identity_part(%{"key" => key}), do: key
  defp identity_part(_identity), do: nil

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "blank"
      slug -> slug
    end
  end
end
