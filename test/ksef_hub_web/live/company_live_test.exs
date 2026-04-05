defmodule KsefHubWeb.CompanyLiveTest do
  use KsefHubWeb.ConnCase, async: false

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  import Mox

  alias KsefHub.Accounts
  alias KsefHub.Companies
  alias KsefHub.Credentials

  setup :set_mox_from_context
  setup :verify_on_exit!

  defp setup_user_with_company(_context) do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-inbound-1",
        email: "owner@example.com",
        name: "Owner"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)
    %{user: user, company: company}
  end

  describe "CompanyLive.Index — create new company" do
    test "user with no companies sees New Company button and can create one", %{conn: conn} do
      user = insert(:user)

      # Index page shows button
      {:ok, view, html} =
        conn
        |> log_in_user(user)
        |> live("/companies")

      assert html =~ "New Company"
      assert has_element?(view, ~s(a[href="/companies/new"]), "New Company")

      # Can navigate to /companies/new and submit
      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live("/companies/new")

      view
      |> form("form[phx-submit=save]", company: %{name: "First Corp", nip: "1122334455"})
      |> render_submit()

      companies = Companies.list_companies_for_user(user.id)
      new_company = Enum.find(companies, &(&1.name == "First Corp"))
      assert new_company

      membership = Companies.get_membership(user.id, new_company.id)
      assert membership.role == :owner
    end

    test "creating a company auto-creates owner membership", %{conn: conn} do
      user = insert(:user)
      # User needs at least one company to not be redirected to /companies/new
      existing = insert(:company)
      insert(:membership, user: user, company: existing, role: :owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: existing.id})
        |> live("/companies/new")

      view
      |> form("form[phx-submit=save]", company: %{name: "New Corp", nip: "9876543210"})
      |> render_submit()

      # Verify the company was created with owner membership
      companies = Companies.list_companies_for_user(user.id)
      new_company = Enum.find(companies, &(&1.name == "New Corp"))
      assert new_company

      membership = Companies.get_membership(user.id, new_company.id)
      assert membership.role == :owner
    end

    test "auto-creates credential when user has certificate", %{conn: conn} do
      user = insert(:user)
      existing = insert(:company)
      insert(:membership, user: user, company: existing, role: :owner)
      insert(:user_certificate, user: user, is_active: true)

      # Stub KSeF mocks so inline AuthWorker doesn't fail
      stub(KsefHub.KsefClient.Mock, :get_challenge, fn ->
        {:ok, %{challenge: "stub-challenge", timestamp: "2025-01-01T00:00:00Z"}}
      end)

      stub(KsefHub.XadesSigner.Mock, :sign_challenge, fn _, _, _, _ ->
        {:ok, "<StubSignedXML/>"}
      end)

      stub(KsefHub.KsefClient.Mock, :authenticate_xades, fn _ ->
        {:ok,
         %{
           reference_number: "stub-ref",
           auth_token: "stub-auth",
           auth_token_valid_until: DateTime.add(DateTime.utc_now(), 300)
         }}
      end)

      stub(KsefHub.KsefClient.Mock, :poll_auth_status, fn _, _ -> {:ok, :success} end)

      stub(KsefHub.KsefClient.Mock, :redeem_tokens, fn _ ->
        {:ok,
         %{
           access_token: "stub-access",
           refresh_token: "stub-refresh",
           access_valid_until: DateTime.add(DateTime.utc_now(), 900),
           refresh_valid_until: DateTime.add(DateTime.utc_now(), 48 * 24 * 3600)
         }}
      end)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: existing.id})
        |> live("/companies/new")

      view
      |> form("form[phx-submit=save]", company: %{name: "Auto Cred Corp", nip: "5566778899"})
      |> render_submit()

      new_company =
        user.id
        |> Companies.list_companies_for_user()
        |> Enum.find(&(&1.name == "Auto Cred Corp"))

      assert new_company
      assert Credentials.get_active_credential(new_company.id)
    end

    test "does not create credential when user has no certificate", %{conn: conn} do
      user = insert(:user)
      existing = insert(:company)
      insert(:membership, user: user, company: existing, role: :owner)
      # No certificate uploaded

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: existing.id})
        |> live("/companies/new")

      view
      |> form("form[phx-submit=save]", company: %{name: "No Cert Corp", nip: "1122334456"})
      |> render_submit()

      new_company =
        user.id
        |> Companies.list_companies_for_user()
        |> Enum.find(&(&1.name == "No Cert Corp"))

      assert new_company
      refute Credentials.get_active_credential(new_company.id)
    end

    test "lists only user's companies", %{conn: conn} do
      user = insert(:user)
      company = insert(:company, name: "My Visible Co")
      _other = insert(:company, name: "Someone Else Co")
      insert(:membership, user: user, company: company, role: :owner)

      {:ok, view, _html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live("/companies")

      assert has_element?(view, "[data-testid='company-name']", "My Visible Co")
      refute has_element?(view, "[data-testid='company-name']", "Someone Else Co")
    end
  end

  describe "CompanyLive.Index — inbound email" do
    setup [:setup_user_with_company]

    defp live_edit(conn, user, company) do
      conn
      |> log_in_user(user, %{current_company_id: company.id})
      |> live("/companies/#{company.id}/edit")
    end

    test "shows disabled state and enable button when no token", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, view, _html} = live_edit(conn, user, company)

      assert has_element?(view, "button", "Enable Inbound Email")
      refute has_element?(view, "button", "Regenerate Address")
      refute has_element?(view, "button", "Disable")
    end

    test "enable_inbound_email shows address and action buttons", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:ksef_hub, :inbound_email_domain, "inbound.test.com")
      on_exit(fn -> Application.delete_env(:ksef_hub, :inbound_email_domain) end)

      {:ok, view, _html} = live_edit(conn, user, company)

      view |> element("button", "Enable Inbound Email") |> render_click()

      assert has_element?(view, "#inbound-email-display")
      assert has_element?(view, ~s([data-testid="inbound-email-address"]))
      assert has_element?(view, "button", "Regenerate Address")
      assert has_element?(view, "button", "Disable")
      refute has_element?(view, "button", "Enable Inbound Email")
    end

    test "address is always visible when token exists", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:ksef_hub, :inbound_email_domain, "inbound.test.com")
      on_exit(fn -> Application.delete_env(:ksef_hub, :inbound_email_domain) end)

      {:ok, _} = Companies.enable_inbound_email(company)
      {:ok, view, _html} = live_edit(conn, user, company)

      assert has_element?(view, "#inbound-email-display")
      assert has_element?(view, ~s([data-testid="inbound-email-address"]))
    end

    test "disable_inbound_email clears the token", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, _} = Companies.enable_inbound_email(company)
      {:ok, view, _html} = live_edit(conn, user, company)

      assert has_element?(view, "button", "Disable")

      view
      |> element(~s(button[phx-click="disable_inbound_email"]))
      |> render_click()

      assert has_element?(view, "button", "Enable Inbound Email")
      refute has_element?(view, "button", "Regenerate Address")
      refute has_element?(view, "#inbound-email-display")
    end

    test "regenerate_inbound_email updates the address", %{
      conn: conn,
      user: user,
      company: company
    } do
      Application.put_env(:ksef_hub, :inbound_email_domain, "inbound.test.com")
      on_exit(fn -> Application.delete_env(:ksef_hub, :inbound_email_domain) end)

      {:ok, enabled} = Companies.enable_inbound_email(company)
      {:ok, view, _html} = live_edit(conn, user, company)

      view
      |> element(~s(button[phx-click="regenerate_inbound_email"]))
      |> render_click()

      assert has_element?(view, "#inbound-email-display")
      assert has_element?(view, ~s([data-testid="inbound-email-address"]))

      # Verify the token actually changed
      refreshed = Companies.get_company!(company.id)
      assert refreshed.inbound_email_token != enabled.inbound_email_token
    end

    test "save_inbound_settings persists allowed domain and cc email", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, view, _html} = live_edit(conn, user, company)

      view
      |> form(~s(form[phx-submit="save_inbound_settings"]),
        company: %{
          inbound_allowed_sender_domain: "acme.com",
          inbound_cc_email: "invoices@acme.com"
        }
      )
      |> render_submit()

      updated = Companies.get_company!(company.id)
      assert updated.inbound_allowed_sender_domain == "acme.com"
      assert updated.inbound_cc_email == "invoices@acme.com"
    end

    test "auto-approve toggle is visible and saves via main company form", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, view, _html} = live_edit(conn, user, company)

      assert has_element?(view, "#company_auto_approve_trusted_invoices")

      view
      |> form("#company-form", company: %{auto_approve_trusted_invoices: true})
      |> render_submit()

      updated = Companies.get_company!(company.id)
      assert updated.auto_approve_trusted_invoices == true
    end

    test "validates invalid domain format in settings", %{
      conn: conn,
      user: user,
      company: company
    } do
      {:ok, view, _html} = live_edit(conn, user, company)

      html =
        view
        |> form(~s(form[phx-submit="save_inbound_settings"]),
          company: %{inbound_allowed_sender_domain: "not valid!"}
        )
        |> render_submit()

      assert html =~ "must be a valid domain"
    end
  end
end
