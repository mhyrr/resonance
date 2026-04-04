import Config

if config_env() == :test do
  config :resonance,
    provider: :test
end
