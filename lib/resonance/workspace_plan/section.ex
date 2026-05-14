defmodule Resonance.WorkspacePlan.Section do
  @moduledoc """
  One planned section inside a `Resonance.WorkspacePlan`.

  Sections are stable workspace units. They carry a developer-readable role,
  a mid-level pattern name, and a source. Phase 1 supports only stored tool
  calls as sources; later phases can add snapshots, widgets, or action sources
  without changing the basic section identity contract.
  """

  @type role :: :summary | :primary | :focus_list | :supporting_context | :detail
  @type pattern ::
          :prose_summary
          | :metric_strip
          | :entity_list
          | :trend_panel
          | :summary_panel
          | :comparison_panel
          | :data_table

  @type source :: {:tool_call, Resonance.LLM.ToolCall.t()}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          title: String.t() | nil,
          role: role() | atom() | nil,
          pattern: pattern() | atom() | nil,
          source: source() | term(),
          interactions: [atom()],
          depends_on: [String.t()],
          metadata: map()
        }

  defstruct [
    :id,
    :title,
    :role,
    :pattern,
    :source,
    interactions: [],
    depends_on: [],
    metadata: %{}
  ]
end
