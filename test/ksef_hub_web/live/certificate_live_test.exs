defmodule KsefHubWeb.CertificateLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Credentials

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-cert-1", email: "test@example.com", name: "Test"})

    company = insert(:company)

    conn = conn |> init_test_session(%{user_id: user.id, current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders certificate page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/certificates")
      assert html =~ "Certificates"
      assert html =~ "Upload New Certificate"
    end

    test "shows active credential when exists", %{conn: conn, company: company} do
      insert(:credential, company: company, nip: company.nip, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")
      assert has_element?(view, "#active-certificate")
      assert render(view) =~ company.nip
    end
  end

  describe "form validation" do
    test "validates on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("form[phx-change=validate]")
      |> render_change(%{credential: %{password: "pass"}})

      # Form should still render (validation is server-side on submit)
      assert render(view) =~ "Certificates"
    end
  end

  describe "deactivate" do
    test "deactivates a credential", %{conn: conn, company: company} do
      cred = insert(:credential, company: company, nip: company.nip, is_active: true)

      {:ok, view, _html} = live(conn, ~p"/certificates")

      view
      |> element("button", "Deactivate")
      |> render_click()

      updated = Credentials.get_credential!(cred.id)
      refute updated.is_active
    end
  end
end
