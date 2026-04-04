defmodule FinanceDemo.Components.EChartsLine do
  use Phoenix.Component

  def chart_dom_id(renderable_id), do: "echarts-line-#{renderable_id}"

  def render(assigns) do
    assigns = assign_new(assigns, :multi_series, fn -> false end)

    ~H"""
    <div class="resonance-component resonance-line-chart">
      <h3 :if={@props[:title]} class="resonance-chart-title"><%= @props.title %></h3>
      <div
        id={"echarts-line-#{@renderable_id}"}
        phx-hook="EChartsLineChart"
        phx-update="ignore"
        data-chart-data={Jason.encode!(@props.data)}
        data-multi-series={to_string(@props[:multi_series] || false)}
        data-title={@props[:title] || ""}
        style="width: 100%; min-height: 350px;"
      />
    </div>
    """
  end
end
