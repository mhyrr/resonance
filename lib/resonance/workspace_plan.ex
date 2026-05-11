defmodule Resonance.WorkspacePlan do
  @moduledoc """
  Typed plan for a generated workspace.

  `WorkspacePlan` is the v3 middle layer above LLM tool calls and below
  rendered Phoenix surfaces. Phase 1 keeps the contract intentionally small:
  hand-written plans, known layouts/roles/pattern names, and section sources
  that are stored `Resonance.LLM.ToolCall` structs.

  The plan does not resolve data or render UI. It only describes what should
  appear. `Resonance.WorkspacePlan.Validation` checks that description before
  any resolver or presenter runs.
  """

  alias Resonance.WorkspacePlan.{Section, Validation}

  @type layout :: :stack | :dashboard_grid | :overview_with_detail
  @type identity :: %{optional(atom()) => term()}

  @type t :: %__MODULE__{
          goal: atom() | nil,
          title: String.t() | nil,
          layout: layout() | atom() | nil,
          sections: [Section.t()],
          refinements: [map()],
          identity: identity()
        }

  defstruct goal: nil,
            title: nil,
            layout: :stack,
            sections: [],
            refinements: [],
            identity: %{kind: :ephemeral, saveable: true}

  @doc """
  Validate a workspace plan.

  Returns `{:ok, plan}` or `{:error, {:validation_failed, errors}}`, where each
  error has `:path`, `:code`, `:message`, and optional `:details`.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, {:validation_failed, [Validation.error()]}}
  def validate(%__MODULE__{} = plan), do: Validation.validate(plan)
end
