defmodule Resonance.PipelineTest do
  use ExUnit.Case, async: false

  alias Resonance.{Pipeline, Renderable}

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Q1", value: 100},
         %{label: "Q2", value: 150},
         %{label: "Q3", value: 200}
       ]}
    end
  end

  defp sink_to(pid) do
    fn event -> send(pid, {:pipeline, event}) end
  end

  defp tool_call(name, args) do
    %Resonance.LLM.ToolCall{id: "call_1", name: name, arguments: args}
  end

  describe "resolve/3" do
    test "delivers a :component_ready event per tool call and a final :done" do
      calls = [
        tool_call("compare_over_time", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "Revenue over quarters"
        }),
        tool_call("rank_entities", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "title" => "Top owners"
        })
      ]

      Pipeline.resolve(calls, %{resolver: MockResolver}, sink_to(self()))

      assert_receive {:pipeline, {:component_ready, %Renderable{status: :ready}}}, 5000
      assert_receive {:pipeline, {:component_ready, %Renderable{status: :ready}}}, 5000
      assert_receive {:pipeline, :done}, 5000
    end

    test "stamps stable IDs based on tool call name and index" do
      calls = [
        tool_call("compare_over_time", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["quarter"],
          "title" => "t"
        }),
        tool_call("rank_entities", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "title" => "t"
        })
      ]

      Pipeline.resolve(calls, %{resolver: MockResolver}, sink_to(self()))

      assert_receive {:pipeline, {:component_ready, %Renderable{id: id1}}}, 5000
      assert_receive {:pipeline, {:component_ready, %Renderable{id: id2}}}, 5000
      assert_receive {:pipeline, :done}, 5000

      ids = Enum.sort([id1, id2])
      assert "compare_over_time-0" in ids
      assert "rank_entities-1" in ids
    end

    test "resolve is idempotent — re-running the same tool calls produces the same ids" do
      calls = [
        tool_call("rank_entities", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "title" => "t"
        })
      ]

      Pipeline.resolve(calls, %{resolver: MockResolver}, sink_to(self()))
      assert_receive {:pipeline, {:component_ready, %Renderable{id: first_id}}}, 5000
      assert_receive {:pipeline, :done}, 5000

      Pipeline.resolve(calls, %{resolver: MockResolver}, sink_to(self()))
      assert_receive {:pipeline, {:component_ready, %Renderable{id: second_id}}}, 5000
      assert_receive {:pipeline, :done}, 5000

      assert first_id == second_id
    end

    test "delivers an error event when the pipeline crashes inside the task" do
      defmodule CrashingResolver do
        @behaviour Resonance.Resolver
        @impl true
        def resolve(_intent, _context), do: raise("boom")
      end

      calls = [
        tool_call("rank_entities", %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["owner"],
          "title" => "t"
        })
      ]

      Pipeline.resolve(calls, %{resolver: CrashingResolver}, sink_to(self()))

      # Resolver crashes bubble up to Composer.resolve_one which wraps them
      # as an error Renderable rather than crashing the pipeline task.
      assert_receive {:pipeline, {:component_ready, %Renderable{status: :error}}}, 5000
      assert_receive {:pipeline, :done}, 5000
    end
  end
end
