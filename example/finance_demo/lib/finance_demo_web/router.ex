defmodule FinanceDemoWeb.Router do
  use FinanceDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FinanceDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FinanceDemoWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/explore", ExploreLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", FinanceDemoWeb do
  #   pipe_through :api
  # end
end
