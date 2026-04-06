defmodule Resonance.Components.BarChart do
  @moduledoc """
  Bar chart presentation component for categorical comparisons.
  Renders via a JS hook using ApexCharts.
  """

  use Phoenix.Component

  @behaviour Resonance.Component

  @doc false
  def chart_dom_id(renderable_id), do: "resonance-bar-#{renderable_id}"

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-bar-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"resonance-bar-#{@renderable_id}"}
        phx-hook="ResonanceBarChart"
        phx-update="ignore"

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
