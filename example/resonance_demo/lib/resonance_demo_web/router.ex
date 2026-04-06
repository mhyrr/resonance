defmodule ResonanceDemoWeb.Router do
  use ResonanceDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ResonanceDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ResonanceDemoWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/explore", ExploreLive
  end

  scope "/" do
    pipe_through :browser

    live_session :playground, on_mount: ResonanceDemoWeb.PlaygroundContext do
      live "/resonance/playground", Resonance.Live.Playground
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", ResonanceDemoWeb do
  #   pipe_through :api
  # end
end
