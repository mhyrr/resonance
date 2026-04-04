defmodule Resonance.QueryIntentTest do
  use ExUnit.Case, async: true

  alias Resonance.QueryIntent

  describe "validate/1" do
    test "valid intent passes" do
      intent = %QueryIntent{
        dataset: "deals",
        measures: ["sum(value)"],
        dimensions: ["stage", "quarter"],
        filters: [%{field: "year", op: ">=", value: 2024}]
      }

      assert {:ok, ^intent} = QueryIntent.validate(intent)
    end

    test "missing dataset fails" do
      intent = %QueryIntent{dataset: nil, measures: ["count(*)"]}
      assert {:error, {:invalid_field, :dataset, _}} = QueryIntent.validate(intent)
    end

    test "empty measures fails" do
      intent = %QueryIntent{dataset: "deals", measures: []}
      assert {:error, {:invalid_field, :measures, _}} = QueryIntent.validate(intent)
    end

    test "invalid filter op fails" do
      intent = %QueryIntent{
        dataset: "deals",
        measures: ["count(*)"],
        filters: [%{field: "x", op: "DROP TABLE", value: 1}]
      }

      assert {:error, {:invalid_field, :filters, _}} = QueryIntent.validate(intent)
    end

    test "negative limit fails" do
      intent = %QueryIntent{dataset: "deals", measures: ["count(*)"], limit: -1}
      assert {:error, {:invalid_field, :limit, _}} = QueryIntent.validate(intent)
    end

    test "nil optional fields are valid" do
      intent = %QueryIntent{dataset: "deals", measures: ["sum(value)"]}
      assert {:ok, _} = QueryIntent.validate(intent)
    end
  end

  describe "from_params/1" do
    test "builds from string-keyed map" do
      params = %{
        "dataset" => "contacts",
        "measures" => ["count(*)"],
        "dimensions" => ["stage"],
        "filters" => [%{"field" => "created_at", "op" => ">=", "value" => "2024-01-01"}]
      }

      assert {:ok, intent} = QueryIntent.from_params(params)
      assert intent.dataset == "contacts"
      assert intent.measures == ["count(*)"]
      assert intent.dimensions == ["stage"]
      assert [%{field: "created_at", op: ">=", value: "2024-01-01"}] = intent.filters
    end

    test "builds from atom-keyed map" do
      params = %{
        dataset: "deals",
        measures: ["sum(value)"],
        dimensions: ["stage"]
      }

      assert {:ok, intent} = QueryIntent.from_params(params)
      assert intent.dataset == "deals"
    end

    test "rejects invalid params" do
      assert {:error, _} = QueryIntent.from_params(%{"measures" => ["count(*)"]})
    end
  end
end
