defmodule Resonance.Test.MockResolver do
  @behaviour Resonance.Resolver

  @impl true
  def resolve(_intent, _context) do
    {:ok,
     [
       %{label: "Alpha", value: 100},
       %{label: "Beta", value: 75},
       %{label: "Gamma", value: 50}
     ]}
  end

  @impl true
  def describe do
    "Test dataset with name dimension and count/sum measures."
  end
end
