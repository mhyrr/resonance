defmodule ResonanceDemoWeb.PlaygroundContext do
  @moduledoc """
  `on_mount` hook that wires app handles into the Resonance widget playground.

  Drops the following into the playground's socket assigns:

  - `:widget_assigns` — the map merged into every mounted widget. Contains
    handles to app contexts (`deals_ctx`) and any developer-provided context
    the widgets need (e.g. `current_user`).
  - `:simulate_fn` / `:simulate_label` — a no-arg function the playground
    invokes when the user clicks the simulate button. Here it calls
    `ResonanceDemo.Deals.simulate_batch/0`, which broadcasts on the
    `"deals"` PubSub topic.
  - `:pubsub` and `:subscribe_topics` — the playground subscribes to these
    topics on mount. When a message arrives, the playground re-resolves the
    currently-displayed widget so it picks up the new data. This is how
    "auto-refresh on data change" works without putting any subscription
    logic inside the LiveComponent (LiveComponents share their parent's
    process and can't subscribe directly).
  """

  import Phoenix.Component, only: [assign: 3]

  alias ResonanceDemo.Deals

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:widget_assigns, %{
       deals_ctx: Deals,
       current_user: nil
     })
     |> assign(:simulate_label, "Simulate New Deals")
     |> assign(:simulate_fn, &Deals.simulate_batch/0)
     |> assign(:pubsub, Deals.pubsub())
     |> assign(:subscribe_topics, [Deals.topic()])}
  end
end
