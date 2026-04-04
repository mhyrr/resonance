defmodule Resonance.Components.MetricCard do
  @moduledoc """
  Single KPI metric card with optional trend indicator.
  """

  use Phoenix.Component

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:trend, fn -> compute_trend(assigns.props) end)

    ~H"""
    <div class="resonance-component resonance-metric-card">
      <div class="resonance-metric-label"><%= @props[:label] || "" %></div>
      <div class="resonance-metric-value"><%= format_value(@props[:value], @props[:format]) %></div>
      <div :if={@trend} class={"resonance-metric-trend #{trend_class(@trend)}"}>
        <%= trend_arrow(@trend) %> <%= format_trend(@trend) %>
      </div>
    </div>
    """
  end

  defp format_value(nil, _), do: "-"
  defp format_value(val, "currency") when is_number(val), do: "$#{Resonance.Format.integer(val)}"
  defp format_value(val, "percent") when is_number(val), do: "#{Float.round(val * 100, 1)}%"

  defp format_value(val, _) when is_float(val),
    do: :erlang.float_to_binary(Float.round(val, 2), decimals: 2)

  defp format_value(val, _) when is_integer(val), do: format_integer(val)
  defp format_value(val, _), do: to_string(val)

  defp format_integer(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_integer(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_integer(n), do: Integer.to_string(n)

  defp compute_trend(%{comparison_value: prev, value: current})
       when is_number(prev) and is_number(current) and prev != 0 do
    Float.round((current - prev) / prev * 100, 1)
  end

  defp compute_trend(_), do: nil

  defp trend_class(pct) when pct > 0, do: "resonance-trend-up"
  defp trend_class(pct) when pct < 0, do: "resonance-trend-down"
  defp trend_class(_), do: "resonance-trend-flat"

  defp trend_arrow(pct) when pct > 0, do: "↑"
  defp trend_arrow(pct) when pct < 0, do: "↓"
  defp trend_arrow(_), do: "→"

  defp format_trend(pct), do: "#{abs(pct)}%"
end
