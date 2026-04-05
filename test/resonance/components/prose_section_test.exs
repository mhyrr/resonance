defmodule Resonance.Components.ProseSectionTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Resonance.Components.ProseSection

  defp render_prose(props) do
    assigns = %{props: props}

    rendered_to_string(~H"""
    <ProseSection.render props={@props} />
    """)
  end

  test "escapes HTML in content to prevent XSS" do
    html = render_prose(%{content: "<script>alert('xss')</script>"})

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
    assert html =~ "&lt;/script&gt;"
  end

  test "renders bold markdown as <strong>" do
    html = render_prose(%{content: "This is **bold** text"})

    assert html =~ "<strong>bold</strong>"
  end

  test "renders italic markdown as <em>" do
    html = render_prose(%{content: "This is *italic* text"})

    assert html =~ "<em>italic</em>"
  end

  test "renders paragraphs from double newlines" do
    html = render_prose(%{content: "First paragraph\n\nSecond paragraph"})

    assert html =~ "<p>First paragraph</p>"
    assert html =~ "<p>Second paragraph</p>"
  end

  test "bold and italic still work when content also contains HTML" do
    html = render_prose(%{content: "**important** <img src=x onerror=alert(1)>"})

    assert html =~ "<strong>important</strong>"
    refute html =~ "<img"
    assert html =~ "&lt;img"
  end
end
