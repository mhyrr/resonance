defmodule Resonance.Resolver.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Resonance.QueryIntent
  alias Resonance.LLM.ToolCall
  alias Resonance.Resolver.Capabilities

  describe "normalize/1" do
    test "keeps legacy string descriptions as prompt-only capabilities" do
      assert {:ok, capabilities} = Capabilities.normalize("Datasets: widgets")

      assert capabilities.description == "Datasets: widgets"
      assert capabilities.datasets == []
      assert Capabilities.format_description(capabilities) == "Datasets: widgets"
    end

    test "normalizes structured dataset specs" do
      assert {:ok, capabilities} = Capabilities.normalize(crm_capabilities())

      assert Capabilities.dataset_names(capabilities) == ["deals"]
      [dataset] = capabilities.datasets
      assert Enum.map(dataset.measures, & &1.name) == ["count(*)", "sum(value)"]
      assert Enum.map(dataset.dimensions, & &1.name) == ["name", "stage", "owner"]
      assert Enum.map(dataset.filters, & &1.field) == ["stage", "owner"]
    end

    test "returns structured errors for malformed capability maps" do
      assert {:error, {:validation_failed, [error]}} =
               Capabilities.normalize(%{datasets: [%{measures: ["count(*)"]}]})

      assert error.code == :invalid_dataset_name
      assert error.path == [:datasets, 0, :name]
    end
  end

  describe "format_description/1" do
    test "renders datasets, filters, and query shapes for planner prompts" do
      description = Capabilities.format_description(crm_capabilities())

      assert description =~ ~s("deals")
      assert description =~ "measures: count(*), sum(value)"
      assert description =~ "filters: stage ops: ="
      assert description =~ "dimensions [owner] with measures [count(*), sum(value)]"
    end
  end

  describe "validate_intent/3" do
    test "accepts query intents inside declared capabilities" do
      intent = %QueryIntent{
        dataset: "deals",
        measures: ["sum(value)"],
        dimensions: ["owner"],
        filters: [%{field: "stage", op: "=", value: "negotiation"}],
        sort: %{field: "sum(value)", direction: :desc}
      }

      assert :ok = Capabilities.validate_intent(intent, crm_capabilities())
    end

    test "rejects invented datasets, fields, and query shapes with actionable paths" do
      intent = %QueryIntent{
        dataset: "deals",
        measures: ["sum(probability)"],
        dimensions: ["probability"],
        filters: [%{field: "forecast_category", op: "=", value: "commit"}]
      }

      assert {:error, errors} = Capabilities.validate_intent(intent, crm_capabilities())

      assert Enum.any?(errors, &match?(%{code: :unsupported_measure}, &1))
      assert Enum.any?(errors, &match?(%{code: :unsupported_dimension}, &1))
      assert Enum.any?(errors, &match?(%{code: :unsupported_filter}, &1))
      assert Enum.any?(errors, &match?(%{code: :unsupported_query_shape}, &1))
    end
  end

  describe "validate_tool_call/3" do
    test "returns an invalid query-intent error for map-keyed filters" do
      tool_call = %ToolCall{
        id: "call_bad_filters",
        name: "rank_entities",
        arguments: %{
          "dataset" => "deals",
          "measures" => ["sum(value)"],
          "dimensions" => ["name"],
          "filters" => %{
            "stage" => %{"op" => "in", "value" => ["proposal", "negotiation"]}
          }
        }
      }

      assert {:error, [error]} =
               Capabilities.validate_tool_call(tool_call, crm_capabilities(),
                 path: [:sections, "bad", :source, :tool_call]
               )

      assert error.code == :invalid_query_intent
      assert error.path == [:sections, "bad", :source, :tool_call, :arguments]
      assert error.details.reason == {:invalid_field, :filters, "must be a list"}
    end
  end

  defp crm_capabilities do
    %{
      datasets: [
        %{
          name: "deals",
          description: "CRM opportunities",
          fields: ~w(name value stage owner),
          measures: ["count(*)", "sum(value)"],
          dimensions: ~w(name stage owner),
          filters: [
            %{field: "stage", ops: ["="]},
            %{field: "owner", ops: ["="]}
          ],
          query_shapes: [
            %{dimensions: ["name"], measures: ["count(*)", "sum(value)"]},
            %{dimensions: ["stage"], measures: ["count(*)", "sum(value)"]},
            %{dimensions: ["owner"], measures: ["count(*)", "sum(value)"]}
          ]
        }
      ]
    }
  end
end
