defmodule CrossroadWeb.PageController do
  use CrossroadWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
