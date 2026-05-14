defmodule ResonanceDemo.CRM.Patterns do
  @moduledoc """
  CRM-owned workspace pattern declarations.

  These names describe product-level workspace intent. They are not Phoenix
  components and do not expose rendering modules to the planner.
  """

  @doc "Pattern manifest entries added to Resonance's built-in patterns."
  def manifest do
    [
      %{
        name: :deal_focus_list,
        description: "CRM deal list for owner/account follow-up work.",
        roles: [:focus_list, :detail],
        result_kinds: [:ranking],
        source_primitives: ["rank_entities"]
      }
    ]
  end
end
