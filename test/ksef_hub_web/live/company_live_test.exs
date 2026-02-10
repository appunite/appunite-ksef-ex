defmodule KsefHubWeb.CompanyLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory
  import Phoenix.LiveViewTest

  alias KsefHub.Companies

  describe "CompanyLive.Index — create new company" do
    test "creating a company auto-creates owner membership", %{conn: conn} do
      user = insert(:user)
      # User needs at least one company to not be redirected to /companies/new
      existing = insert(:company)
      insert(:membership, user: user, company: existing, role: "owner")

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
      assert membership.role == "owner"
    end

    test "lists only user's companies", %{conn: conn} do
      user = insert(:user)
      company = insert(:company, name: "My Visible Co")
      _other = insert(:company, name: "Someone Else Co")
      insert(:membership, user: user, company: company, role: "owner")

      {:ok, _view, html} =
        conn
        |> log_in_user(user, %{current_company_id: company.id})
        |> live("/companies")

      assert html =~ "My Visible Co"
      refute html =~ "Someone Else Co"
    end
  end
end
