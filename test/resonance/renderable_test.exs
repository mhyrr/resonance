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

  test "ready/3 defaults render_via to :function" do
    r = Renderable.ready("type", SomeModule, %{})
    assert r.render_via == :function
  end

  test "ready_live/3 sets render_via to :live" do
    r = Renderable.ready_live("ranking", SomeWidget, %{title: "Top reps"})
    assert r.status == :ready
    assert r.render_via == :live
    assert r.component == SomeWidget
    assert r.props.title == "Top reps"
  end

  test "error/2 creates a renderable with status :error" do
    r = Renderable.error("bad_primitive", :something_broke)
    assert r.status == :error
    assert r.type == "bad_primitive"
    assert r.error == :something_broke
    assert r.render_via == :function
    assert is_binary(r.id)
  end

  test "ids are unique" do
    r1 = Renderable.ready("a", SomeModule, %{})
    r2 = Renderable.ready("b", SomeModule, %{})
    assert r1.id != r2.id
  end

  test "Jason encoding includes render_via" do
    r = Renderable.ready_live("ranking", SomeWidget, %{n: 1})
    encoded = Jason.encode!(r) |> Jason.decode!()
    assert encoded["render_via"] == "live"
    assert encoded["status"] == "ready"
    refute Map.has_key?(encoded, "component")
  end
end
