defmodule Resonance.Components.LineChart do
  @moduledoc """
  Line chart presentation component for time-series and trend data.
  Renders via a JS hook using ApexCharts.
  """

  use Phoenix.Component

  def render(assigns) do
    assigns = assign_new(assigns, :multi_series, fn -> false end)

    ~H"""
    <div class="resonance-component resonance-line-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"resonance-line-#{@renderable_id}"}
        phx-hook="ResonanceLineChart"

        data-chart-data={Jason.encode!(@props.data)}
        data-multi-series={to_string(@props[:multi_series] || false)}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 300px;"
      />
    </div>
    """
  end
end
