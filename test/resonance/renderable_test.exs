defmodule Resonance.RenderableTest do
  use ExUnit.Case, async: true

  alias Resonance.Renderable

  test "ready/3 creates a renderable with status :ready" do
    r = Renderable.ready("compare_over_time", Resonance.Components.LineChart, %{title: "Test"})
    assert r.status == :ready
    assert r.type == "compare_over_time"
    assert r.component == Resonance.Components.LineChart
    assert r.props.title == "Test"
    assert is_binary(r.id)
    assert r.error == nil
  end

  test "error/2 creates a renderable with status :error" do
    r = Renderable.error("bad_primitive", :something_broke)
    assert r.status == :error
    assert r.type == "bad_primitive"
    assert r.error == :something_broke
    assert is_binary(r.id)
  end

  test "ids are unique" do
    r1 = Renderable.ready("a", SomeModule, %{})
    r2 = Renderable.ready("b", SomeModule, %{})
    assert r1.id != r2.id
  end
end
