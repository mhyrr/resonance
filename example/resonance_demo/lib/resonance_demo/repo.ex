defmodule ResonanceDemo.Repo do
  use Ecto.Repo,
    otp_app: :resonance_demo,
    adapter: Ecto.Adapters.SQLite3
end
