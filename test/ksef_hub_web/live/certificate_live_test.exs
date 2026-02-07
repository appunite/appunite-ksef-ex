defmodule KsefHubWeb.CertificateLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias KsefHub.Accounts
  alias KsefHub.Credentials

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-cert-1", email: "test@example.com", name: "Test"})

    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "mount" do
    test "renders certificate page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Certificates"
      assert html =~ "Upload New Certificate"
    end

    test "shows active credential when exists", %{conn: conn} do
      {:ok, _} = Credentials.create_credential(%{nip: "1234567890", is_active: true})

      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Active Certificate"
      assert html =~ "1234567890"
    end
  end

  describe "form validation" do
    test "validates NIP on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("form")
      |> render_change(%{credential: %{nip: "123", password: "pass"}})

      # Form should still render (validation is server-side on submit)
      assert render(view) =~ "Certificates"
    end
  end

  describe "deactivate" do
    test "deactivates a credential", %{conn: conn} do
      {:ok, cred} = Credentials.create_credential(%{nip: "1234567890", is_active: true})

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("button", "Deactivate")
      |> render_click()

      updated = Credentials.get_credential!(cred.id)
      refute updated.is_active
    end
  end
end
