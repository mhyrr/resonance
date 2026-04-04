defmodule ResonanceDemoWeb.PageController do
  use ResonanceDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
