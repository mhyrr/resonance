defmodule Resonance.LLM.ToolCall do
  @moduledoc """
  Normalized tool call struct — provider-agnostic representation
  of an LLM's tool invocation.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @derive Jason.Encoder
  @enforce_keys [:name, :arguments]
  defstruct [:id, :name, :arguments]
end
