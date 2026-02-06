defmodule KsefHubWeb.PageController do
  use KsefHubWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
