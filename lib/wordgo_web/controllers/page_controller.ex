defmodule WordgoWeb.PageController do
  use WordgoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
