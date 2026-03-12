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

    test "shows invoices in table", %{conn: conn, company: company} do
      insert(:invoice, type: :income, seller_name: "Alpha Sp. z o.o.", company: company)
      insert(:invoice, type: :expense, seller_name: "Beta Sp. z o.o.", company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "Alpha Sp. z o.o."
      assert html =~ "Beta Sp. z o.o."
    end

    test "shows empty state when no invoices", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "No invoices found"
    end
  end

  describe "category and tag columns" do
    test "shows category name in table", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "finance:invoices", emoji: "💰")
      insert(:invoice, company: company, category: category)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "finance:invoices"
      assert html =~ "💰"
    end

    test "shows tag names in table", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "monthly")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "monthly"
    end

    test "shows needs review badge when prediction_status is needs_review", %{
      conn: conn,
      company: company
    } do
      insert(:invoice, company: company, prediction_status: :needs_review)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "needs review"
    end

    test "does not show needs review badge for predicted status", %{conn: conn, company: company} do
      insert(:invoice, company: company, prediction_status: :predicted)

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
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?status=pending")
      html = render(view)
      assert html =~ "Income Seller"
      assert html =~ "Expense Seller"
    end

    test "filter change updates URL via push_patch", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"type" => "income"}})

      assert_patched(view, "/c/#{company.id}/invoices?type=income")
    end

    test "remove_filter clears a single filter", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?type=income&status=pending")

      # Verify both chips are rendered
      html = render(view)
      assert html =~ "Type: Income"
      assert html =~ "Status: Pending"

      # Remove the type filter via chip
      view
      |> element("button[phx-click=remove_filter][phx-value-key=type]")
      |> render_click()

      assert_patched(view, "/c/#{company.id}/invoices?status=pending")
    end
  end

  describe "category and tag filters" do
    test "filters by category", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:hosting")

      insert(:invoice,
        company: company,
        seller_name: "Categorized Seller",
        category: category
      )

      insert(:invoice, company: company, seller_name: "Uncategorized Seller")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?category_id=#{category.id}")
      html = render(view)
      assert html =~ "Categorized Seller"
      refute html =~ "Uncategorized Seller"
    end

    test "filters by tag", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "quarterly")
      tagged = insert(:invoice, company: company, seller_name: "Tagged Seller")
      insert(:invoice_tag, invoice: tagged, tag: tag)
      insert(:invoice, company: company, seller_name: "Untagged Seller")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?tag_id=#{tag.id}")
      html = render(view)
      assert html =~ "Tagged Seller"
      refute html =~ "Untagged Seller"
    end

    test "category filter change updates URL", %{conn: conn, company: company} do
      category = insert(:category, company: company, name: "ops:filter-test")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"category_id" => category.id}})

      assert_patched(view, "/c/#{company.id}/invoices?category_id=#{category.id}")
    end

    test "tag filter change updates URL", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "filter-tag")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"tag_id" => tag.id}})

      assert_patched(view, "/c/#{company.id}/invoices?tag_id=#{tag.id}")
    end

    test "renders category and tag filter dropdowns", %{conn: conn, company: company} do
      insert(:category, company: company, name: "ops:dropdown-test")
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
      insert(:invoice, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert html =~ "data-testid=\"pagination\""
      assert html =~ "Showing 1"
      assert html =~ "of 1 invoices"
      assert html =~ "Previous"
      assert html =~ "Page 1 of 1"
      assert html =~ "Next"
    end

    test "navigates to page 2", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
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
          type: :income,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices?page=2")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"type" => "income"}})

      # Should not include page param (defaults to page 1)
      assert_patched(view, "/c/#{company.id}/invoices?type=income")
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

    test "reviewer sees only expense invoices", %{conn: conn, company: company} do
      insert(:invoice,
        type: :income,
        seller_name: "Hidden Income Seller",
        company: company
      )

      insert(:invoice,
        type: :expense,
        seller_name: "Visible Expense Seller",
        company: company
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices")
      refute html =~ "Hidden Income Seller"
      assert html =~ "Visible Expense Seller"
    end

    test "reviewer cannot see income invoices via type=income URL param", %{
      conn: conn,
      company: company
    } do
      insert(:invoice,
        type: :income,
        seller_name: "Secret Income Seller",
        company: company
      )

      insert(:invoice,
        type: :expense,
        seller_name: "Allowed Expense Seller",
        company: company
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices?type=income")
      refute html =~ "Secret Income Seller"
      assert html =~ "Allowed Expense Seller"
    end

    test "reviewer sees locked type filter", %{conn: conn, company: company} do
      insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices")
      assert has_element?(view, "select[disabled]")
    end
  end
end
