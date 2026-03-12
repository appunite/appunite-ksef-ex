defmodule KsefHubWeb.PageController do
  use KsefHubWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/users/log-in")
  end
end
