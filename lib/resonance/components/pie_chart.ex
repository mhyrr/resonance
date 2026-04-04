defmodule Resonance.Components.PieChart do
  @moduledoc """
  Pie/donut chart component for proportional data.
  Renders via a JS hook using ApexCharts.
  """

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-pie-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"resonance-pie-#{System.unique_integer([:positive])}"}
        phx-hook="ResonancePieChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props[:data] || [])}
        data-donut={to_string(@props[:donut] || false)}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 300px;"
      />
    </div>
    """
  end
end
