defmodule Resonance.RegistryTest do
  use ExUnit.Case, async: true

  alias Resonance.Registry

  setup do
    {:ok, pid} = Registry.start_link(name: :"test_registry_#{System.unique_integer()}")
    %{registry: pid}
  end

  test "starts empty", %{registry: reg} do
    assert Registry.list(reg) == []
  end

  test "register and retrieve a primitive", %{registry: reg} do
    Registry.register("test_primitive", Resonance.Primitives.CompareOverTime, reg)
    assert Registry.get("test_primitive", reg) == Resonance.Primitives.CompareOverTime
  end

  test "returns nil for unknown primitive", %{registry: reg} do
    assert Registry.get("nonexistent", reg) == nil
  end

  test "all_schemas returns schemas from registered primitives", %{registry: reg} do
    Registry.register("compare_over_time", Resonance.Primitives.CompareOverTime, reg)
    schemas = Registry.all_schemas(reg)
    assert length(schemas) == 1
    assert hd(schemas).name == "compare_over_time"
  end

  test "register_defaults populates default primitives", %{registry: reg} do
    Registry.register_defaults(reg)
    names = Registry.list(reg)
    assert "compare_over_time" in names
  end
end
