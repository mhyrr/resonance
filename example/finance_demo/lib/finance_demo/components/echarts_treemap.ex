defmodule FinanceDemo.Components.EChartsTreemap do
  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-treemap-#{renderable_id}"

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-treemap">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-treemap-#{@renderable_id}"}
        phx-hook="EChartsTreemap"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props[:data] || [])}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 400px;"
      />
    </div>
    """
  end
end
