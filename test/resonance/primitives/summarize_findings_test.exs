defmodule Resonance.Primitives.SummarizeFindingsTest do
  use ExUnit.Case, async: true

  alias Resonance.Primitives.SummarizeFindings
  alias Resonance.Renderable

  defmodule MockResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context) do
      {:ok,
       [
         %{label: "Q1", value: 100},
         %{label: "Q2", value: 150},
         %{label: "Q3", value: 200},
         %{label: "Q4", value: 180}
       ]}
    end
  end

  defmodule EmptyResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context), do: {:ok, []}
  end

  test "resolve generates summary prose from data" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Summary"
    }

    assert {:ok, data} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert data.title == "Summary"
    assert is_binary(data.content)
    assert data.content =~ "4"
    assert data.content =~ "records found"
  end

  test "resolve handles empty data" do
    params = %{
      "dataset" => "deals",
      "measures" => ["count(*)"],
      "title" => "Empty"
    }

    assert {:ok, data} = SummarizeFindings.resolve(params, %{resolver: EmptyResolver})
    assert data.content =~ "No data found"
  end

  test "summary includes range and top/bottom for sufficient data" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Detailed"
    }

    assert {:ok, data} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert data.content =~ "range from"
    assert data.content =~ "Highest"
    assert data.content =~ "Lowest"
  end

  test "summary includes trend line when focus is trends" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Trends",
      "focus" => "trends"
    }

    assert {:ok, data} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert data.content =~ "trend"
  end

  test "present returns prose section component" do
    data = %{content: "Some findings.", title: "Test"}

    result = SummarizeFindings.present(data, %{})
    assert %Renderable{status: :ready} = result
    assert result.component == Resonance.Components.ProseSection
    assert result.props.style == "summary"
  end
end
