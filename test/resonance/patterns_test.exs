defmodule Resonance.PatternsTest do
  use ExUnit.Case, async: true

  alias Resonance.LLM.ToolCall
  alias Resonance.Patterns
  alias Resonance.WorkspacePlan.Section

  describe "manifest/1" do
    test "includes built-in pattern names" do
      names = Patterns.default_manifest() |> Patterns.names()

      assert :prose_summary in names
      assert :entity_list in names
      assert :trend_panel in names
    end

    test "merges app-declared patterns without dynamic atom creation" do
      manifest = Patterns.manifest(custom_patterns())

      assert :deal_focus_list in Patterns.names(manifest)
      assert Patterns.get(manifest, :deal_focus_list).source_primitives == ["rank_entities"]
      assert Patterns.get(manifest, "deal_focus_list") == nil
    end

    test "renders only planner-facing pattern facts" do
      prompt_text =
        custom_patterns()
        |> Patterns.manifest()
        |> Patterns.format_for_prompt()

      assert prompt_text =~ "deal_focus_list"
      assert prompt_text =~ "roles=[focus_list, detail]"
      assert prompt_text =~ "source_primitives=[rank_entities]"
      refute prompt_text =~ "HEEx"
      refute prompt_text =~ "Phoenix"
      refute prompt_text =~ "CSS"
      refute prompt_text =~ "Resonance.Components"
    end
  end

  describe "validate_section/3" do
    test "accepts compatible role and source primitive" do
      section =
        section(%{
          role: :focus_list,
          pattern: :deal_focus_list,
          source: {:tool_call, tool_call("rank_entities")}
        })

      assert :ok = Patterns.validate_section(section, Patterns.manifest(custom_patterns()))
    end

    test "accepts entity lists as supporting context" do
      section =
        section(%{
          role: :supporting_context,
          pattern: :entity_list,
          source: {:tool_call, tool_call("rank_entities")}
        })

      assert :ok = Patterns.validate_section(section, Patterns.default_manifest())
    end

    test "rejects incompatible pattern roles" do
      section =
        section(%{
          role: :summary,
          pattern: :deal_focus_list,
          source: {:tool_call, tool_call("rank_entities")}
        })

      assert {:error, [%{code: :incompatible_pattern_role}]} =
               Patterns.validate_section(section, Patterns.manifest(custom_patterns()))
    end

    test "rejects incompatible pattern source primitives" do
      section =
        section(%{
          role: :primary,
          pattern: :metric_strip,
          source: {:tool_call, tool_call("rank_entities")}
        })

      assert {:error, [%{code: :incompatible_pattern_source}]} =
               Patterns.validate_section(section, Patterns.default_manifest())
    end
  end

  defp custom_patterns do
    [
      %{
        name: :deal_focus_list,
        description: "CRM deal list for follow-up work.",
        roles: [:focus_list, :detail],
        result_kinds: [:ranking],
        source_primitives: ["rank_entities"]
      }
    ]
  end

  defp section(attrs) do
    struct!(
      %Section{
        id: "section",
        role: :primary,
        pattern: :summary_panel,
        source: {:tool_call, tool_call("show_distribution")}
      },
      attrs
    )
  end

  defp tool_call(name) do
    %ToolCall{
      id: "call_#{name}",
      name: name,
      arguments: %{"dataset" => "deals", "measures" => ["sum(value)"], "dimensions" => ["name"]}
    }
  end
end
