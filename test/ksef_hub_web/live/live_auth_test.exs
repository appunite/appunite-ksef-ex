defmodule KsefHubWeb.LiveAuthTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  describe "LiveAuth on_mount" do
    test "redirects to / when session has no user_id", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{})
        |> live("/dashboard")
    end

    test "redirects to / when session user_id is not a valid UUID", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_id: "not-a-uuid"})
        |> live("/dashboard")
    end

    test "redirects to / when user_id does not match any user", %{conn: conn} do
      {:error, {:redirect, %{to: "/"}}} =
        conn
        |> init_test_session(%{user_id: Ecto.UUID.generate()})
        |> live("/dashboard")
    end

    test "assigns current_user for valid session", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)

      {:ok, _view, html} =
        conn
        |> init_test_session(%{user_id: user.id, current_company_id: company.id})
        |> live("/dashboard")

      assert html =~ "Dashboard"
    end
  end
end
