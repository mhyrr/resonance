defmodule Resonance.Renderable do
  @moduledoc """
  A resolved, renderable component ready for LiveView display.

  Produced by a primitive's `present/2` callback after data resolution.
  The Composer collects these and the LiveView component renders them.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          component: module(),
          props: map(),
          status: :ready | :error | :loading,
          error: term() | nil
        }

  @enforce_keys [:id, :type, :component, :status]
  defstruct [:id, :type, :component, :props, :status, :error]

  @doc """
  Build a ready-to-render Renderable.
  """
  def ready(type, component, props) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      component: component,
      props: props,
      status: :ready
    }
  end

  @doc """
  Build an error Renderable.
  """
  def error(type, reason) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      component: Resonance.Components.ErrorDisplay,
      props: %{},
      status: :error,
      error: reason
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
