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
            <td :for={col <- @columns}><%= format_cell(row, col) %></td>
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

  defp format_cell(row, col) when is_map(row) do
    val = row[col] || row[String.to_existing_atom(col)]
    format_value(val)
  rescue
    ArgumentError -> row[col] || ""
  end

  defp format_value(nil), do: ""

  defp format_value(val) when is_float(val),
    do: :erlang.float_to_binary(Float.round(val, 2), decimals: 2)

  defp format_value(val), do: to_string(val)
end
