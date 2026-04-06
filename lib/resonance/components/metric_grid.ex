defmodule Resonance.Components.MetricGrid do
  @moduledoc """
  Responsive grid of metric cards.
  """

  use Phoenix.Component

  @behaviour Resonance.Component

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:columns, fn -> assigns.props[:columns] || 3 end)

    ~H"""
    <div class="resonance-component resonance-metric-grid">
      <h3 :if={@props[:title]} class="resonance-grid-title"><%= @props.title %></h3>
      <div class="resonance-grid" style={"display: grid; grid-template-columns: repeat(#{@columns}, 1fr); gap: 1rem;"}>
        <div :for={metric <- @props[:metrics] || []} class="resonance-grid-item">
          <div class="resonance-metric-label"><%= metric[:label] || metric["label"] %></div>
          <div class="resonance-metric-value">
            <%= format_value(metric[:value] || metric["value"], metric[:format] || metric["format"]) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_value(nil, _), do: "-"
  defp format_value(val, "currency") when is_number(val), do: "$#{Resonance.Format.integer(val)}"
  defp format_value(val, "percent") when is_number(val), do: "#{Float.round(val * 100, 1)}%"

  defp format_value(val, _) when is_float(val),
    do: :erlang.float_to_binary(Float.round(val, 2), decimals: 2)

  defp format_value(val, _) when is_integer(val), do: Resonance.Format.integer(val)
  defp format_value(val, _), do: to_string(val)
end
