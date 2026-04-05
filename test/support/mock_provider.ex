defmodule Resonance.Test.MockProvider do
  @behaviour Resonance.LLM.Provider

  @impl true
  def chat(_prompt, _tools, _opts) do
    {:ok,
     [
       %Resonance.LLM.ToolCall{
         id: "test-1",
         name: "rank_entities",
         arguments: %{
           "dataset" => "test",
           "measures" => ["count(*)"],
           "dimensions" => ["name"],
           "title" => "Test Ranking"
         }
       }
     ]}
  end
end
