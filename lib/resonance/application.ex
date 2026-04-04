defmodule Resonance.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Resonance.Registry
    ]

    opts = [strategy: :one_for_one, name: Resonance.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Resonance.Registry.register_defaults()

    {:ok, pid}
  end
end
