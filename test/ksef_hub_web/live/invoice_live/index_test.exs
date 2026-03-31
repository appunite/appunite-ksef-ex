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
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "KSeF sync not configured"
      assert html =~ ~s|/c/#{company.id}/settings/certificates|
    end

    test "hides warning when company has a certificate", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:user_certificate, user: user)
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute html =~ "KSeF sync not configured"
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
      tag = insert(:tag, company: company, name: "monthly")
      invoice = insert(:invoice, company: company, type: :expense)
      insert(:invoice_tag, invoice: invoice, tag: tag)

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
        insert(:invoice, type: :income, seller_name: "Income Seller", company: company)

      expense =
        insert(:invoice, type: :expense, seller_name: "Expense Seller", company: company)

      %{conn: conn, income: income, expense: expense}
    end

    test "filters by type", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      html = render(view)
      assert html =~ "Income Seller"
      refute html =~ "Expense Seller"
    end

    test "filters by status", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense&status=pending")
      html = render(view)
      refute html =~ "Income Seller"
      assert html =~ "Expense Seller"
    end

    test "filter change updates URL via push_patch", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"status" => "pending"}})

      assert_patched(view, "/c/#{company.id}/invoices?status=pending&type=expense")
    end

    test "clear_filters preserves type param", %{conn: conn, company: company} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/c/#{company.id}/invoices?type=income&status=pending"
        )

      html = render(view)
      assert html =~ "Status: Pending"

      view
      |> element("button", "Clear all filters")
      |> render_click()

      assert_patched(view, "/c/#{company.id}/invoices?type=income")
    end

    test "remove_filter clears a single filter", %{conn: conn, company: company} do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/c/#{company.id}/invoices?type=expense&status=pending&category_id=00000000-0000-0000-0000-000000000000"
        )

      # Verify chip is rendered
      html = render(view)
      assert html =~ "Status: Pending"

      # Remove the status filter via chip
      view
      |> element("button[phx-click=remove_filter][phx-value-key=status]")
      |> render_click()

      assert_patched(
        view,
        "/c/#{company.id}/invoices?category_id=00000000-0000-0000-0000-000000000000&type=expense"
      )
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
      insert(:invoice, type: :income, seller_name: "Alpha Vendor", company: company)
      insert(:invoice, type: :expense, seller_name: "Beta Vendor", company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      view
      |> element(~s{a[href*="type=income"]}, "Income")
      |> render_click()

      html = render(view)
      assert html =~ "Alpha Vendor"
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
        live(conn, ~p"/c/#{company.id}/invoices?category_id=#{category.id}")

      html = render(view)
      assert html =~ "Categorized Seller"
      refute html =~ "Uncategorized Seller"
    end

    test "filters by tag", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "quarterly")
      tagged = insert(:invoice, company: company, type: :expense, seller_name: "Tagged Seller")
      insert(:invoice_tag, invoice: tagged, tag: tag)
      insert(:invoice, company: company, type: :expense, seller_name: "Untagged Seller")

      {:ok, view, _html} =
        live(conn, ~p"/c/#{company.id}/invoices?type=expense&tag_id=#{tag.id}")

      html = render(view)
      assert html =~ "Tagged Seller"
      refute html =~ "Untagged Seller"
    end

    test "category filter change updates URL", %{conn: conn, company: company} do
      category = insert(:category, company: company, identifier: "ops:filter-test")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"category_id" => category.id}})

      assert_patched(view, "/c/#{company.id}/invoices?category_id=#{category.id}&type=expense")
    end

    test "tag filter change updates URL", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "filter-tag")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=expense")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"tag_id" => tag.id}})

      assert_patched(view, "/c/#{company.id}/invoices?tag_id=#{tag.id}&type=expense")
    end

    test "renders category and tag filter dropdowns", %{conn: conn, company: company} do
      insert(:category, company: company, identifier: "ops:dropdown-test", name: nil)
      insert(:tag, company: company, name: "dropdown-tag")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "ops:dropdown-test"
      assert html =~ "dropdown-tag"
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
      |> render_change(%{"filters" => %{"status" => "pending"}})

      # Should not include page param (defaults to page 1)
      assert_patched(view, "/c/#{company.id}/invoices?status=pending&type=expense")
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
        seller_name: "Hidden Income Seller",
        company: company,
        access_restricted: true
      )

      insert(:invoice,
        type: :income,
        seller_name: "Visible Income Seller",
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
      refute html =~ "Hidden Income Seller"
      assert html =~ "Visible Income Seller"

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
        seller_name: "Secret Income Seller",
        company: company,
        access_restricted: true
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      refute html =~ "Secret Income Seller"
    end

    test "reviewer sees both Expense and Income tabs", %{conn: conn, company: company} do
      insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Expense"
      assert html =~ "Income"
    end
  end
end
