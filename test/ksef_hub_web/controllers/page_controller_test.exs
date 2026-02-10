defmodule KsefHubWeb.PageControllerTest do
  use KsefHubWeb.ConnCase

  test "GET / shows landing page with login/register links", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    assert response =~ "Log in"
    assert response =~ "Create an account"
  end
end
