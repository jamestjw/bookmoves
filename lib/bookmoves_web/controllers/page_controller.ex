defmodule BookmovesWeb.PageController do
  use BookmovesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
