defmodule Resonance.Renderable do
  @moduledoc """
  A composed UI component ready to mount.

  Produced by a `Resonance.Presenter` from a `Resonance.Result`. Carries
  everything `Resonance.Live.Report` needs to mount the component plus the
  initial assigns the component should be mounted with.

  ## `render_via`

  - `:function` (default) — `component` is a `Resonance.Component` function
    component. `Live.Report` invokes its `render/1` directly.
  - `:live` — `component` is a `Resonance.Widget` LiveComponent. `Live.Report`
    mounts it via `<.live_component>`.

  Presenters set `render_via` by calling `ready/3` (function components) or
  `ready_live/3` (widgets).

  ## `result` (introspection only)

  The underlying `Resonance.Result` that produced this Renderable is kept on
  the struct as a paper trail for **developer introspection** — for example,
  inspecting it from IEx while debugging a custom resolver. **Widgets must
  not read it at runtime**: their contract is "receive `:renderable`, work
  with `:props`." Reading `:result` from a widget is going off the documented
  contract and will couple the widget to internals that may change.
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
          result: Resonance.Result.t() | nil
        }

  @derive {Jason.Encoder, only: [:id, :type, :props, :status, :render_via]}
  @enforce_keys [:id, :type, :component, :status]
  defstruct [
    :id,
    :type,
    :component,
    :props,
    :status,
    :error,
    :result,
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
  Build a ready-to-render Renderable backed by a `Resonance.Widget`
  LiveComponent.

  Use this from a Presenter when you want the component to be interactive.
  `Live.Report` will mount it via `<.live_component>`. Once mounted, the
  widget is a normal Phoenix LiveComponent — it calls your app contexts
  from `handle_event/3`, subscribes to PubSub, etc. Resonance is no longer
  in the runtime path.
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
