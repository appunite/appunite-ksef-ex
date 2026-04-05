defmodule KsefHubWeb.InvoiceLive.IndexTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-inv-1",
        email: "test@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders invoice list page", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Invoices"
    end

    test "defaults to expense tab", %{conn: conn, company: company} do
      insert(:invoice, type: :income, seller_name: "Alpha Sp. z o.o.", company: company)
      insert(:invoice, type: :expense, seller_name: "Beta Sp. z o.o.", company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute html =~ "Alpha Sp. z o.o."
      assert html =~ "Beta Sp. z o.o."
    end

    test "shows empty state when no invoices", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "No invoices found"
    end
  end

  describe "certificate warning banner" do
    test "shows warning when company has no certificate", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      assert has_element?(view, "[data-testid=certificate-warning-banner]")

      assert has_element?(
               view,
               ~s{a[href="/c/#{company.id}/settings/certificates"]}
             )
    end

    test "hides warning when company has a certificate", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate, user: user, is_active: true)
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute has_element?(view, "[data-testid=certificate-warning-banner]")
    end
  end

  describe "certificate expiry alerts" do
    test "shows expired banner when certificate has expired", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate,
        user: user,
        is_active: true,
        not_after: Date.add(Date.utc_today(), -1)
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert has_element?(view, "[data-testid='certificate-expired-banner']")
      assert render(view) =~ "Certificate expired"
      refute has_element?(view, "[data-testid='certificate-warning-banner']")
    end

    test "shows expiring soon banner when certificate expires within 7 days", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate,
        user: user,
        is_active: true,
        not_after: Date.add(Date.utc_today(), 5)
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert has_element?(view, "[data-testid='certificate-expiring-banner']")
      assert render(view) =~ "Certificate expiring soon"
      assert render(view) =~ "5 days"
    end

    test "does not show expiry banners when certificate is valid", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate,
        user: user,
        is_active: true,
        not_after: Date.add(Date.utc_today(), 30)
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute has_element?(view, "[data-testid='certificate-expired-banner']")
      refute has_element?(view, "[data-testid='certificate-expiring-banner']")
    end

    test "does not show no-certificate warning when certificate exists but expiring", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate,
        user: user,
        is_active: true,
        not_after: Date.add(Date.utc_today(), 3)
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute has_element?(view, "[data-testid='certificate-warning-banner']")
      assert has_element?(view, "[data-testid='certificate-expiring-banner']")
    end
  end

  describe "category and tag columns" do
    test "shows category name in table", %{conn: conn, company: company} do
      category =
        insert(:category,
          company: company,
          identifier: "finance:invoices",
          name: "Invoices",
          emoji: "💰"
        )

      insert(:invoice, company: company, type: :expense, category: category)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Invoices"
      assert html =~ "💰"
    end

    test "shows tag names in table", %{conn: conn, company: company} do
      insert(:invoice, company: company, type: :expense, tags: ["monthly"])

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "monthly"
    end

    test "shows needs review badge when prediction_status is needs_review", %{
      conn: conn,
      company: company
    } do
      insert(:invoice, company: company, type: :expense, prediction_status: :needs_review)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "needs review"
    end

    test "does not show needs review badge for predicted status", %{conn: conn, company: company} do
      insert(:invoice, company: company, type: :expense, prediction_status: :predicted)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute html =~ "needs review"
    end
  end

  describe "filters" do
    setup %{conn: conn, company: company} do
      income =
        insert(:invoice, type: :income, buyer_name: "Income Buyer", company: company)

      expense =
        insert(:invoice, type: :expense, seller_name: "Expense Seller", company: company)

      %{conn: conn, income: income, expense: expense}
    end

    test "filters by type", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      html = render(view)
      assert html =~ "Income Buyer"
      refute html =~ "Expense Seller"
      assert has_element?(view, "th", "Buyer")
      refute has_element?(view, "th", "Seller")
    end

    test "filters by status", %{conn: conn, company: company} do
      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/invoices?type=expense&statuses=pending")

      html = render(view)
      refute html =~ "Income Buyer"
      assert html =~ "Expense Seller"
      assert has_element?(view, "th", "Seller")
      refute has_element?(view, "th", "Buyer")
    end

    test "filter change updates URL via push_patch", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"date_from" => "2026-01-01"}})

      assert_patched(view, "/c/#{company.id}/invoices?date_from=2026-01-01&type=expense")
    end

    test "clear_filters preserves type param", %{conn: conn, company: company} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/c/#{company.id}/invoices?type=income&statuses=pending"
        )

      html = render(view)
      assert html =~ "Status: Pending"

      view
      |> element("button", "Reset")
      |> render_click()

      assert_patched(view, "/c/#{company.id}/invoices?type=income")
    end
  end

  describe "type tabs" do
    test "renders type tabs for owner", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ ~r/>\s*Income\s*<\/a>/
      assert html =~ ~r/>\s*Expense\s*<\/a>/
    end

    test "expense tab is active by default", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert has_element?(view, ~s{a.border-shad-primary}, "Expense")
    end

    test "clicking Income tab filters to income invoices", %{conn: conn, company: company} do
      insert(:invoice, type: :income, buyer_name: "Alpha Buyer", company: company)
      insert(:invoice, type: :expense, seller_name: "Beta Vendor", company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      view
      |> element(~s{a[href*="type=income"]}, "Income")
      |> render_click()

      html = render(view)
      assert html =~ "Alpha Buyer"
      refute html =~ "Beta Vendor"
    end
  end

  describe "category and tag filters" do
    test "filters by category", %{conn: conn, company: company} do
      category = insert(:category, company: company, identifier: "ops:hosting")

      insert(:invoice,
        company: company,
        type: :expense,
        seller_name: "Categorized Seller",
        category: category
      )

      insert(:invoice, company: company, type: :expense, seller_name: "Uncategorized Seller")

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/invoices?category_ids=#{category.id}")

      html = render(view)
      assert html =~ "Categorized Seller"
      refute html =~ "Uncategorized Seller"
    end

    test "filters by tag", %{conn: conn, company: company} do
      insert(:invoice,
        company: company,
        type: :expense,
        seller_name: "Tagged Seller",
        tags: ["quarterly"]
      )

      insert(:invoice, company: company, type: :expense, seller_name: "Untagged Seller")

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/invoices?type=expense&tags=quarterly")

      html = render(view)
      assert html =~ "Tagged Seller"
      refute html =~ "Untagged Seller"
    end

    test "filters by multiple statuses", %{conn: conn, company: company} do
      insert(:invoice,
        company: company,
        type: :expense,
        seller_name: "Pending Seller",
        status: :pending
      )

      insert(:invoice,
        company: company,
        type: :expense,
        seller_name: "Approved Seller",
        status: :approved
      )

      insert(:invoice,
        company: company,
        type: :expense,
        seller_name: "Rejected Seller",
        status: :rejected
      )

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/invoices?type=expense&statuses=pending,approved")

      html = render(view)
      assert html =~ "Pending Seller"
      assert html =~ "Approved Seller"
      refute html =~ "Rejected Seller"
    end

    test "renders multi-select filter components", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert has_element?(view, "#status-filter-popover")
      assert has_element?(view, "#tag-filter-popover")
    end
  end

  describe "pagination" do
    test "renders pagination controls when more than one page", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          type: :expense,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "data-testid=\"pagination\""
      assert html =~ "Showing 1"
      assert html =~ "of 30 invoices"
    end

    test "shows pagination footer with disabled nav for single page", %{
      conn: conn,
      company: company
    } do
      insert(:invoice, company: company, type: :expense)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "data-testid=\"pagination\""
      assert html =~ "Showing 1"
      assert html =~ "of 1 invoices"
      assert html =~ "Page 1 of 1"

      # Previous and Next should be rendered as disabled spans (not links)
      assert html =~ "pointer-events-none"
      refute html =~ ~r/<a[^>]*>Previous<\/a>/
      refute html =~ ~r/<a[^>]*>Next<\/a>/
    end

    test "navigates to page 2", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          type: :expense,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?page=2")
      html = render(view)
      assert html =~ "Showing 26"
      assert html =~ "of 30 invoices"
    end

    test "filter change resets to page 1", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          type: :expense,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense&page=2")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"date_from" => "2020-01-01"}})

      # Should not include page param (defaults to page 1)
      assert_patched(view, "/c/#{company.id}/invoices?date_from=2020-01-01&type=expense")
    end
  end

  describe "access-restricted indicator" do
    test "shows lock icon for restricted invoices", %{conn: conn, company: company} do
      insert(:invoice,
        type: :expense,
        seller_name: "Restricted Seller",
        company: company,
        access_restricted: true
      )

      insert(:invoice,
        type: :expense,
        seller_name: "Open Seller",
        company: company,
        access_restricted: false
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      # The restricted invoice row should contain the lock icon title
      assert html =~ "Access restricted to invited reviewers"
    end

    test "does not show lock icon for unrestricted invoices", %{conn: conn, company: company} do
      insert(:invoice,
        type: :expense,
        seller_name: "Open Seller",
        company: company,
        access_restricted: false
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute html =~ "Access restricted to invited reviewers"
    end
  end

  describe "reviewer role" do
    setup %{conn: _conn} do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-rev-1",
          email: "reviewer@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      %{conn: conn, company: company}
    end

    test "reviewer sees only expense invoices (income is access-restricted)", %{
      conn: conn,
      company: company
    } do
      insert(:invoice,
        type: :income,
        buyer_name: "Hidden Income Buyer",
        company: company,
        access_restricted: true
      )

      insert(:invoice,
        type: :income,
        buyer_name: "Visible Income Buyer",
        company: company,
        access_restricted: false
      )

      insert(:invoice,
        type: :expense,
        seller_name: "Visible Expense Seller",
        company: company
      )

      # Verify income view filters out restricted invoices
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      refute html =~ "Hidden Income Buyer"
      assert html =~ "Visible Income Buyer"

      # Verify expense view still works
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Visible Expense Seller"
    end

    test "reviewer cannot see restricted income invoices via type=income URL param", %{
      conn: conn,
      company: company
    } do
      insert(:invoice,
        type: :income,
        buyer_name: "Secret Income Buyer",
        company: company,
        access_restricted: true
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      refute html =~ "Secret Income Buyer"
    end

    test "reviewer sees both Expense and Income tabs", %{conn: conn, company: company} do
      insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Expense"
      assert html =~ "Income"
    end
  end
end
