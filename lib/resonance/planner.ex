defmodule Resonance.Planner do
  @moduledoc """
  Planner boundary for v3 workspace generation.

  The planner asks the configured provider for one tool call:
  `create_workspace_plan`. The provider output is decoded into
  `Resonance.WorkspacePlan`, validated against workspace enums and resolver
  capabilities, then returned to the caller. It does not compile, render, or
  mutate application data.
  """

  alias Resonance.{LLM, Patterns, Registry, Resolver, WorkspaceContext, WorkspacePlan}
  alias Resonance.Resolver.Capabilities

  @tool_name "create_workspace_plan"

  @doc """
  Produce a validated workspace plan from a user prompt and app capabilities.
  """
  @spec plan(String.t(), map(), keyword()) ::
          {:ok, WorkspacePlan.t()} | {:error, term()}
  def plan(prompt, context, opts \\ []) when is_binary(prompt) and is_map(context) do
    case plan_result(prompt, context, opts) do
      {:ok, %{plan: plan}} -> {:ok, plan}
      {:error, %{reason: reason}} -> {:error, reason}
    end
  end

  @doc """
  Produce a validated workspace plan with planner attempt metadata.
  """
  @spec plan_result(String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, map()}
  def plan_result(prompt, context, opts \\ []) when is_binary(prompt) and is_map(context) do
    pattern_manifest = Patterns.from_context(context)
    workspace_context = WorkspaceContext.from_context(context)

    with {:ok, capabilities} <- resolver_capabilities(context),
         {:ok, result} <-
           plan_attempt(
             prompt,
             prompt,
             context,
             capabilities,
             pattern_manifest,
             workspace_context,
             opts,
             retry_count(opts),
             1,
             nil
           ) do
      {:ok, result}
    else
      {:error, %{reason: _reason} = result} -> {:error, result}
      {:error, reason} -> {:error, %{reason: reason, attempts: 0, retried?: false}}
    end
  end

  @doc """
  Validate a workspace plan against registered primitives and resolver capabilities.
  """
  @spec validate(WorkspacePlan.t(), Capabilities.t(), [Patterns.spec()]) ::
          {:ok, WorkspacePlan.t()} | {:error, term()}
  def validate(
        %WorkspacePlan{} = plan,
        capabilities,
        pattern_manifest \\ Patterns.default_manifest()
      ) do
    WorkspacePlan.validate(plan,
      capabilities: capabilities,
      primitive_names: Registry.list(),
      patterns: pattern_manifest
    )
  end

  @doc """
  Tool schema given to the provider for planner mode.
  """
  @spec create_workspace_plan_schema([Patterns.spec()]) :: map()
  def create_workspace_plan_schema(pattern_manifest \\ Patterns.default_manifest()) do
    %{
      name: @tool_name,
      description:
        "Create a typed Resonance workspace plan. Emit only workspace structure and tool-call sources; never emit UI code, HEEx, CSS classes, component modules, or mutations.",
      parameters: %{
        type: "object",
        properties: %{
          goal: %{
            type: "string",
            description: "Short snake_case intent label for the workspace"
          },
          title: %{
            type: "string",
            description: "Human-readable workspace title"
          },
          layout: %{
            type: "string",
            enum: atom_strings(Resonance.WorkspacePlan.Validation.allowed_layouts())
          },
          identity: %{
            type: "object",
            description: "Stable workspace identity metadata",
            properties: %{
              id: %{type: "string"},
              kind: %{type: "string"},
              saveable: %{type: "boolean"}
            }
          },
          sections: %{
            type: "array",
            minItems: 1,
            items: section_schema(pattern_manifest)
          },
          refinements: %{
            type: "array",
            items: %{type: "object"}
          }
        },
        required: ["goal", "title", "layout", "sections"]
      }
    }
  end

  @doc false
  @spec build_system_prompt(Capabilities.t(), [Patterns.spec()], WorkspaceContext.t() | nil) ::
          String.t()
  def build_system_prompt(
        capabilities,
        pattern_manifest \\ Patterns.default_manifest(),
        workspace_context \\ nil
      ) do
    """
    You are the Resonance workspace planner.

    Return exactly one #{@tool_name} tool call. The plan must be valid against
    the declared app capabilities. Use only declared datasets, measures,
    dimensions, filters, query shapes, primitive names, layouts, roles, and
    patterns.

    Do not emit HEEx, HTML, CSS classes, Phoenix component modules, raw design
    atoms, persistence instructions, or mutation/action surfaces. Each section
    source must be a semantic primitive tool call with QueryIntent arguments.

    Prefer 2-5 sections. Use a summary section when the prompt asks for a
    review, insight, recommendation, or account/deal focus. Choose narrow,
    useful workspaces over broad dashboards.

    Available workspace layouts:
    #{enum_line(Resonance.WorkspacePlan.Validation.allowed_layouts())}

    Available section roles:
    #{enum_line(Resonance.WorkspacePlan.Validation.allowed_roles())}

    Available section patterns:
    #{Patterns.format_for_prompt(pattern_manifest)}

    Available semantic primitives:
    #{Enum.join(Registry.list(), ", ")}

    #{workspace_context_block(workspace_context)}

    App data capabilities:
    #{Resolver.format_description(capabilities)}
    """
  end

  @doc false
  @spec validation_feedback_prompt(String.t(), [map()]) :: String.t()
  def validation_feedback_prompt(original_prompt, errors) when is_binary(original_prompt) do
    """
    The previous workspace plan was invalid.

    Original user prompt:
    #{original_prompt}

    Validation errors:
    #{format_validation_errors(errors)}

    Return a corrected #{@tool_name} tool call. Fix only the invalid plan fields.
    Keep the same contract: no HEEx, HTML, CSS classes, component modules, raw
    design atoms, persistence instructions, mutation runtime, or action surfaces.
    """
  end

  defp plan_attempt(
         original_prompt,
         request_prompt,
         context,
         capabilities,
         pattern_manifest,
         workspace_context,
         opts,
         retries_remaining,
         attempt,
         previous_errors
       ) do
    with {:ok, tool_call} <-
           request_plan(
             request_prompt,
             context,
             capabilities,
             pattern_manifest,
             workspace_context,
             opts
           ),
         {:ok, workspace_plan} <-
           WorkspacePlan.from_map(tool_call.arguments, patterns: pattern_manifest),
         {:ok, validated_plan} <- validate(workspace_plan, capabilities, pattern_manifest) do
      {:ok,
       %{
         plan: validated_plan,
         attempts: attempt,
         retried?: attempt > 1,
         recovered?: attempt > 1 and previous_errors not in [nil, []]
       }}
    else
      {:error, {:validation_failed, errors}} = error ->
        maybe_retry_plan(
          error,
          original_prompt,
          context,
          capabilities,
          pattern_manifest,
          workspace_context,
          opts,
          retries_remaining,
          attempt,
          errors
        )

      {:error, reason} ->
        {:error, %{reason: reason, attempts: attempt, retried?: attempt > 1, recovered?: false}}
    end
  end

  defp maybe_retry_plan(
         _error,
         original_prompt,
         context,
         capabilities,
         pattern_manifest,
         workspace_context,
         opts,
         retries_remaining,
         attempt,
         errors
       )
       when retries_remaining > 0 do
    retry_prompt = validation_feedback_prompt(original_prompt, errors)

    plan_attempt(
      original_prompt,
      retry_prompt,
      context,
      capabilities,
      pattern_manifest,
      workspace_context,
      opts,
      retries_remaining - 1,
      attempt + 1,
      errors
    )
  end

  defp maybe_retry_plan(
         error,
         _original_prompt,
         _context,
         _capabilities,
         _pattern_manifest,
         _workspace_context,
         _opts,
         _retries,
         attempt,
         _errors
       ) do
    {:error,
     %{reason: elem(error, 1), attempts: attempt, retried?: attempt > 1, recovered?: false}}
  end

  defp request_plan(prompt, context, capabilities, pattern_manifest, workspace_context, _opts) do
    case LLM.chat(prompt, [create_workspace_plan_schema(pattern_manifest)], context,
           system: build_system_prompt(capabilities, pattern_manifest, workspace_context)
         ) do
      {:ok, tool_calls} ->
        select_plan_tool_call(tool_calls)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp retry_count(opts) do
    opts
    |> Keyword.get(:max_validation_retries, 1)
    |> max(0)
  end

  defp format_validation_errors(errors) when is_list(errors) do
    Enum.map_join(errors, "\n", &format_validation_error/1)
  end

  defp format_validation_errors(error), do: inspect(error)

  defp format_validation_error(%{path: path, code: code, message: message} = error) do
    details =
      case Map.get(error, :details) do
        nil -> ""
        details -> " details=#{inspect(details)}"
      end

    "- path=#{format_path(path)} code=#{code} message=#{message}#{details}"
  end

  defp format_validation_error(error), do: "- #{inspect(error)}"

  defp format_path(path) when is_list(path), do: Enum.map_join(path, ".", &to_string/1)
  defp format_path(path), do: to_string(path)

  defp resolver_capabilities(context) do
    context
    |> Map.get(:resolver)
    |> Resolver.capabilities()
  end

  defp workspace_context_block(nil), do: ""

  defp workspace_context_block(%WorkspaceContext{} = context) do
    WorkspaceContext.format_for_prompt(context)
  end

  defp select_plan_tool_call(tool_calls) do
    case Enum.find(tool_calls, &(&1.name == @tool_name)) do
      nil ->
        {:error,
         {:planning_failed, :missing_workspace_plan_tool_call,
          %{received: Enum.map(tool_calls, & &1.name)}}}

      tool_call ->
        {:ok, tool_call}
    end
  end

  defp section_schema(pattern_manifest) do
    %{
      type: "object",
      properties: %{
        id: %{
          type: "string",
          description: "Stable snake_case section id unique within the workspace"
        },
        title: %{type: "string"},
        role: %{
          type: "string",
          enum: atom_strings(Resonance.WorkspacePlan.Validation.allowed_roles())
        },
        pattern: %{
          type: "string",
          enum: atom_strings(Patterns.names(pattern_manifest))
        },
        source: %{
          type: "object",
          properties: %{
            type: %{type: "string", enum: ["tool_call"]},
            tool_call: %{
              type: "object",
              properties: %{
                id: %{type: "string"},
                name: %{
                  type: "string",
                  enum: Registry.list()
                },
                arguments: %{
                  type: "object",
                  description:
                    "QueryIntent-compatible primitive arguments: dataset, measures, dimensions, filters, sort, limit, title"
                }
              },
              required: ["name", "arguments"]
            }
          },
          required: ["type", "tool_call"]
        },
        interactions: %{
          type: "array",
          items: %{type: "string", enum: ["filter", "inspect", "refine"]}
        },
        depends_on: %{
          type: "array",
          items: %{type: "string"}
        },
        metadata: %{type: "object"}
      },
      required: ["id", "role", "pattern", "source"]
    }
  end

  defp atom_strings(atoms), do: Enum.map(atoms, &Atom.to_string/1)
  defp enum_line(atoms), do: atoms |> atom_strings() |> Enum.join(", ")
end
