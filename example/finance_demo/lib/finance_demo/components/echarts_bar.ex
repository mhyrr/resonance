defmodule FinanceDemo.Components.EChartsBar do
  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-bar-#{renderable_id}"

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-bar-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-bar-#{@renderable_id}"}
        phx-hook="EChartsBarChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props.data)}
        data-orientation={@props[:orientation] || "vertical"}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 350px;"
      />
    </div>
    """
  end
end
