defmodule KsefHubWeb.PageControllerTest do
  use KsefHubWeb.ConnCase

  test "GET / shows sign in page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Sign in with Google"
  end
end
