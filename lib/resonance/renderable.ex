defmodule Resonance.Renderable do
  @moduledoc """
  A resolved, renderable component ready for LiveView display.

  Produced by a primitive's `present/2` callback after data resolution.
  The Composer collects these and the LiveView component renders them.

  ## `render_via`

  - `:function` (default) — the `component` is a `Resonance.Component`
    function component. `Live.Report` invokes its `render/1` directly.
  - `:live` — the `component` is a `Resonance.Widget` LiveComponent.
    `Live.Report` mounts it via `<.live_component>` and routes streaming
    updates through `Phoenix.LiveView.send_update/2`.

  Presenters set `render_via` when building the Renderable, typically by
  calling `ready_live/3` instead of `ready/3`.
  """

  @type render_via :: :function | :live

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          component: module(),
          props: map(),
          status: :ready | :error | :loading,
          error: term() | nil,
          render_via: render_via(),
          result: Resonance.Result.t() | nil,
          primitive: String.t() | nil
        }

  @derive {Jason.Encoder, only: [:id, :type, :props, :status, :render_via, :result, :primitive]}
  @enforce_keys [:id, :type, :component, :status]
  defstruct [
    :id,
    :type,
    :component,
    :props,
    :status,
    :error,
    :result,
    :primitive,
    render_via: :function
  ]

  @doc """
  Build a ready-to-render Renderable backed by a function component
  (`Resonance.Component`).
  """
  def ready(type, component, props) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      component: component,
      props: props,
      status: :ready,
      render_via: :function
    }
  end

  @doc """
  Build a ready-to-render Renderable backed by a LiveComponent widget
  (`Resonance.Widget`).

  Use this from a Presenter when you want the component to be interactive.
  `Live.Report` will mount it via `<.live_component>` and deliver subsequent
  updates with `Phoenix.LiveView.send_update/2`.
  """
  def ready_live(type, widget, props) do
    %__MODULE__{
      id: generate_id(),
      type: type,
      component: widget,
      props: props,
      status: :ready,
      render_via: :live
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
      error: reason,
      render_via: :function
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
