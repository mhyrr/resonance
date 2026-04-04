defmodule Resonance.Primitives.CompareOverTimeTest do
  use ExUnit.Case, async: true

  alias Resonance.Primitives.CompareOverTime
  alias Resonance.Renderable

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Q1", period: "Q1", value: 100},
         %{label: "Q2", period: "Q2", value: 150},
         %{label: "Q3", period: "Q3", value: 200}
       ]}
    end
  end

  defmodule ValidatingResolver do
    @behaviour Resonance.Resolver

    @impl true
    def validate(%{dataset: "forbidden"}, _ctx), do: {:error, :forbidden}
    def validate(_intent, _ctx), do: :ok

    @impl true
    def resolve(_intent, _context) do
      {:ok, [%{label: "A", value: 10}]}
    end
  end

  test "intent_schema returns valid tool schema" do
    schema = CompareOverTime.intent_schema()
    assert schema.name == "compare_over_time"
    assert is_binary(schema.description)
    assert schema.parameters.type == "object"
    assert Map.has_key?(schema.parameters.properties, :dataset)
  end

  test "resolve builds QueryIntent and calls resolver" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "dimensions" => ["quarter"],
      "title" => "Revenue by Quarter"
    }

    assert {:ok, data} = CompareOverTime.resolve(params, %{resolver: MockResolver})
    assert data.title == "Revenue by Quarter"
    assert length(data.data) == 3
  end

  test "resolve fails with invalid params" do
    params = %{"measures" => ["count(*)"], "title" => "Bad"}
    assert {:error, _} = CompareOverTime.resolve(params, %{resolver: MockResolver})
  end

  test "resolve respects resolver validation" do
    params = %{
      "dataset" => "forbidden",
      "measures" => ["count(*)"],
      "dimensions" => ["quarter"],
      "title" => "Nope"
    }

    assert {:error, :forbidden} = CompareOverTime.resolve(params, %{resolver: ValidatingResolver})
  end

  test "resolve returns a Result with kind :comparison" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "dimensions" => ["quarter"],
      "title" => "Revenue by Quarter"
    }

    assert {:ok, result} = CompareOverTime.resolve(params, %{resolver: MockResolver})
    assert %Resonance.Result{kind: :comparison} = result
    assert result.title == "Revenue by Quarter"
    assert length(result.data) == 3
    assert result.summary.count == 3
  end

  test "default presenter maps comparison to chart component" do
    result = %Resonance.Result{
      kind: :comparison,
      title: "Test",
      data: [%{label: "Q1", value: 100}, %{label: "Q2", value: 200}],
      intent: %Resonance.QueryIntent{
        dataset: "x",
        measures: ["count(*)"],
        dimensions: ["quarter"]
      }
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert %Renderable{status: :ready, type: "compare_over_time"} = renderable
    assert renderable.component in [Resonance.Components.LineChart, Resonance.Components.BarChart]
    assert renderable.props.title == "Test"
  end
end
