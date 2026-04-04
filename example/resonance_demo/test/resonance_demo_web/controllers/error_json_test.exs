defmodule ResonanceDemoWeb.ErrorJSONTest do
  use ResonanceDemoWeb.ConnCase, async: true

  test "renders 404" do
    assert ResonanceDemoWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert ResonanceDemoWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
