defmodule KsefHubWeb.PageController do
  use KsefHubWeb, :controller

  def home(conn, _params) do
    # Use a minimal layout for the public landing page
    conn
    |> put_layout(false)
    |> render(:home)
  end
end
