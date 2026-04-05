defmodule Resonance.Test.ComponentHelpers do
  @moduledoc """
  Helpers for testing LiveComponents without a full Phoenix endpoint.

  Builds minimal socket structs and invokes component callbacks directly.
  """

  alias Phoenix.LiveView.Socket

  @doc """
  Build a socket suitable for LiveComponent callback testing.

  Returns a bare `%Phoenix.LiveView.Socket{}` with an empty assigns map
  that includes the `__changed__` tracking key LiveView expects.
  """
  def build_socket(extra_assigns \\ %{}) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, extra_assigns),
      private: %{live_temp: %{}}
    }
  end

  @doc """
  Run a LiveComponent's mount/1 callback and return the resulting socket.
  """
  def mount_component(module) do
    {:ok, socket} = module.mount(build_socket())
    socket
  end

  @doc """
  Run a LiveComponent's update/2 callback with the given assigns.
  """
  def update_component(module, assigns, socket \\ nil) do
    socket = socket || mount_component(module)
    {:ok, socket} = module.update(assigns, socket)
    socket
  end

  @doc """
  Run a LiveComponent's handle_event/3 callback.
  """
  def handle_event(module, event, params, socket) do
    module.handle_event(event, params, socket)
  end
end
