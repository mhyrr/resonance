defmodule Resonance.RefineTest do
  use ExUnit.Case, async: true

  alias Resonance.{Composer, QueryIntent, Renderable, Result}

  defmodule StageResolver do
    @moduledoc """
    A resolver that filters its result rows by the `stage` filter on the
    QueryIntent. Used to verify that refine/3 actually re-runs the resolver
    with the mutated intent.
    """
    @behaviour Resonance.Resolver

    @impl true
    def resolve(%QueryIntent{filters: filters}, _context) do
      base_rows = [
        %{label: "Acme Corp", value: 100, stage: "discovery"},
        %{label: "Globex", value: 250, stage: "negotiation"},
        %{label: "Initech", value: 150, stage: "discovery"},
        %{label: "Umbrella", value: 400, stage: "closed_won"}
      ]

      filtered =
        case stage_filter(filters) do
          nil -> base_rows
          stage -> Enum.filter(base_rows, &(&1.stage == stage))
        end

      {:ok, filtered}
    end

    defp stage_filter(nil), do: nil

    defp stage_filter(filters) do
      case Enum.find(filters, fn f -> f.field == "stage" end) do
        nil -> nil
        %{value: value} -> value
      end
    end
  end

  defmodule StrictResolver do
    @behaviour Resonance.Resolver

    @impl true
    def resolve(_intent, _context), do: {:ok, []}

    @impl true
    def validate(%QueryIntent{filters: filters}, _context) do
      if filters && Enum.any?(filters, fn f -> f.field == "forbidden" end) do
        {:error, :forbidden_field}
      else
        :ok
      end
    end
  end

  defp build_renderable(resolver) do
    [renderable] =
      Composer.compose(
        [
          %Resonance.LLM.ToolCall{
            id: "call_1",
            name: "rank_entities",
            arguments: %{
              "dataset" => "deals",
              "measures" => ["sum(value)"],
              "dimensions" => ["account"],
              "title" => "Top deals"
            }
          }
        ],
        %{resolver: resolver}
      )
      |> elem(1)

    renderable
  end

  describe "refine/3 happy path" do
    test "re-resolves with the mutated intent and returns a new Renderable" do
      original = build_renderable(StageResolver)
      assert original.status == :ready
      assert is_binary(original.primitive)
      assert %Result{} = original.result
      original_row_count = length(original.result.data)
      assert original_row_count == 4

      {:ok, refined} =
        Resonance.refine(
          original,
          fn intent ->
            %{
              intent
              | filters: [%{field: "stage", op: "=", value: "discovery"} | intent.filters || []]
            }
          end,
          %{resolver: StageResolver}
        )

      assert refined.status == :ready
      # New result reflects the filter
      assert length(refined.result.data) == 2
      assert Enum.all?(refined.result.data, &(&1.stage == "discovery"))
      # Renderable id is preserved (so the LiveComponent rerenders in place)
      assert refined.id == original.id
      # Source metadata is preserved
      assert refined.primitive == original.primitive
      # The new intent is on the new result
      assert Enum.any?(refined.result.intent.filters, fn f -> f.field == "stage" end)
    end

    test "preserves the original LLM constraints (intent_fn starts from existing intent)" do
      original = build_renderable(StageResolver)
      original_dataset = original.result.intent.dataset
      original_measures = original.result.intent.measures

      {:ok, refined} =
        Resonance.refine(
          original,
          fn intent ->
            # Only touch filters; everything else should pass through
            %{intent | filters: [%{field: "stage", op: "=", value: "negotiation"}]}
          end,
          %{resolver: StageResolver}
        )

      assert refined.result.intent.dataset == original_dataset
      assert refined.result.intent.measures == original_measures
    end
  end

  describe "refine/3 error paths" do
    test "returns {:error, _} when the mutated intent fails resolver validation" do
      original = build_renderable(StrictResolver)

      assert {:error, :forbidden_field} =
               Resonance.refine(
                 original,
                 fn intent ->
                   %{intent | filters: [%{field: "forbidden", op: "=", value: 1}]}
                 end,
                 %{resolver: StrictResolver}
               )
    end

    test "returns {:error, _} when the mutated intent fails QueryIntent validation" do
      original = build_renderable(StageResolver)

      assert {:error, _} =
               Resonance.refine(
                 original,
                 fn intent ->
                   # measures cannot be empty
                   %{intent | measures: []}
                 end,
                 %{resolver: StageResolver}
               )
    end

    test "returns {:error, :renderable_missing_result} for a Renderable without source" do
      naked = %Renderable{
        id: "x",
        type: "ranking",
        component: SomeWidget,
        props: %{},
        status: :ready,
        render_via: :live
      }

      assert {:error, :renderable_missing_result} =
               Resonance.refine(naked, fn i -> i end, %{resolver: StageResolver})
    end
  end
end
