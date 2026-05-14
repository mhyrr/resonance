defmodule Resonance.Components.DataTable do
  @moduledoc """
  Sortable data table component. Server-rendered, no JS hook needed.
  """

  use Phoenix.Component

  @behaviour Resonance.Component

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:columns, fn -> infer_columns(assigns.props[:data] || []) end)
      |> assign_new(:sortable, fn -> assigns.props[:sortable] || false end)
      |> assign_new(:format, fn -> assigns.props[:format] || %{} end)

    ~H"""
    <div class="resonance-component resonance-data-table">
      <h3 :if={@props[:title]} class="resonance-table-title"><%= @props.title %></h3>
      <table class="resonance-table">
        <thead>
          <tr>
            <th :for={col <- @columns}><%= col %></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @props[:data] || []}>
            <td :for={col <- @columns}><%= format_cell(row, col, @format) %></td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp infer_columns([first | _]) when is_map(first) do
    first
    |> Map.keys()
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp infer_columns(_), do: []

  defp format_cell(row, col, format) when is_map(row) do
    val = cell_value(row, col)
    format_value(val, field_format(format, col))
  end

  defp cell_value(row, col) do
    row[col] || row[String.to_existing_atom(col)]
  rescue
    ArgumentError -> row[col]
  end

  defp field_format(format, col) when is_map(format) do
    Map.get(format, col) || existing_atom_format(format, col)
  end

  defp field_format(_format, _col), do: nil

  defp existing_atom_format(format, col) do
    Map.get(format, String.to_existing_atom(col))
  rescue
    ArgumentError -> nil
  end

  defp format_value(nil, _), do: ""

  defp format_value(val, format) when format in ["currency", :currency] and is_number(val),
    do: "$#{Resonance.Format.integer(val)}"

  defp format_value(val, format) when format in ["percent", :percent] and is_number(val),
    do: "#{Float.round(val * 100, 1)}%"

  defp format_value(val, _) when is_float(val),
    do: :erlang.float_to_binary(Float.round(val, 2), decimals: 2)

  defp format_value(val, _), do: to_string(val)
end
