defmodule FinanceDemoWeb.PageController do
  use FinanceDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
