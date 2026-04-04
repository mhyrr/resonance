defmodule Resonance.Components.BarChart do
  @moduledoc """
  Bar chart presentation component for categorical comparisons.
  Renders via a JS hook using ApexCharts.
  """

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-bar-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"resonance-bar-#{System.unique_integer([:positive])}"}
        phx-hook="ResonanceBarChart"
        data-chart-data={Jason.encode!(@props.data)}
        data-orientation={@props[:orientation] || "vertical"}
        data-stacked={to_string(@props[:stacked] || false)}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 300px;"
      />
    </div>
    """
  end
end
