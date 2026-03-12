defmodule KsefHubWeb.PageControllerTest do
  use KsefHubWeb.ConnCase

  test "GET / redirects to login", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
