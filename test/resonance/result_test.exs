defmodule Resonance.ResultTest do
  use ExUnit.Case, async: true

  alias Resonance.Result

  test "defaults format metadata to an empty map" do
    result = %Result{kind: :ranking, title: "Top deals"}

    assert result.format == %{}
  end

  test "stores field-level format metadata" do
    result = %Result{kind: :ranking, title: "Top deals", format: %{value: :currency}}

    assert result.format.value == :currency
  end
end
