defmodule Resonance.Components.ErrorDisplay do
  @moduledoc """
  Error display component for failed primitive resolution.
  """

  use Phoenix.Component

  @behaviour Resonance.Component

  def render(assigns) do
    ~H"""
    <div class="resonance-component resonance-error">
      <p class="resonance-error-message">
        Failed to load component: <%= inspect(@error) %>
      </p>
    </div>
    """
  end
end
