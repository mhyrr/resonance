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

  test "resolve generates summary prose in metadata" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Summary"
    }

    assert {:ok, result} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert result.title == "Summary"
    assert result.kind == :summary
    assert is_binary(result.metadata.content)
    assert result.metadata.content =~ "4"
    assert result.metadata.content =~ "records found"
  end

  test "resolve handles empty data" do
    params = %{
      "dataset" => "deals",
      "measures" => ["count(*)"],
      "title" => "Empty"
    }

    assert {:ok, result} = SummarizeFindings.resolve(params, %{resolver: EmptyResolver})
    assert result.metadata.content =~ "No data found"
  end

  test "summary includes range and top/bottom for sufficient data" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Detailed"
    }

    assert {:ok, result} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert result.metadata.content =~ "range from"
    assert result.metadata.content =~ "Highest"
    assert result.metadata.content =~ "Lowest"
  end

  test "summary includes trend line when focus is trends" do
    params = %{
      "dataset" => "deals",
      "measures" => ["sum(value)"],
      "title" => "Trends",
      "focus" => "trends"
    }

    assert {:ok, result} = SummarizeFindings.resolve(params, %{resolver: MockResolver})
    assert result.metadata.content =~ "trend"
  end

  test "default presenter maps summary to prose section" do
    result = %Resonance.Result{
      kind: :summary,
      title: "Test",
      metadata: %{content: "Some findings."}
    }

    renderable = Resonance.Presenters.Default.present(result, %{})
    assert %Renderable{status: :ready} = renderable
    assert renderable.component == Resonance.Components.ProseSection
    assert renderable.props.style == "summary"
  end
end
