defmodule Resonance.Test.StructuredResolver do
  @behaviour Resonance.Resolver

  @impl true
  def describe do
    %{
      datasets: [
        %{
          name: "deals",
          measures: ["count(*)", "sum(value)"],
          dimensions: ["owner"],
          query_shapes: [
            %{dimensions: ["owner"], measures: ["count(*)", "sum(value)"]}
          ]
        }
      ]
    }
  end

  @impl true
  def resolve(_intent, _context), do: {:ok, []}
end
