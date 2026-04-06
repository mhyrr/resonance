defmodule Resonance.Components.ProseSection do
  @moduledoc """
  Narrative text section for analysis summaries.

  Renders markdown-formatted content as HTML. Uses a simple
  markdown subset (bold, paragraphs) since we control the output.
  """

  use Phoenix.Component

  @behaviour Resonance.Component

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:style, fn -> assigns.props[:style] || "default" end)

    ~H"""
    <div class={"resonance-component resonance-prose resonance-prose-#{@style}"}>
      <h3 :if={@props[:title]} class="resonance-prose-title"><%= @props.title %></h3>
      <div class="resonance-prose-content">
        <%= render_markdown(@props[:content] || "") %>
      </div>
    </div>
    """
  end

  defp render_markdown(text) do
    text
    |> String.split("\n\n", trim: true)
    |> Enum.map(fn paragraph ->
      inner =
        paragraph
        |> Phoenix.HTML.html_escape()
        |> Phoenix.HTML.safe_to_string()
        |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
        |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")

      Phoenix.HTML.raw("<p>#{inner}</p>")
    end)
  end
end
