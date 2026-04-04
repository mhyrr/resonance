defmodule Resonance.Format do
  @moduledoc false

  def integer(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def integer(n) when is_float(n), do: integer(round(n))
end
