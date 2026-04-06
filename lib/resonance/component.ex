defmodule Resonance.Component do
  @moduledoc """
  Behaviour for presentation components.

  All components must implement `render/1` (a standard Phoenix function component).
  Chart components that support live data push should also implement `chart_dom_id/1`.
  """

  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()
  @callback chart_dom_id(renderable_id :: String.t()) :: String.t()

  @optional_callbacks [chart_dom_id: 1]
end
