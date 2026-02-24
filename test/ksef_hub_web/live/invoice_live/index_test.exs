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
    test "renders invoice list page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/invoices")
      assert html =~ "Invoices"
    end

    test "shows invoices in table", %{conn: conn, company: company} do
      insert(:invoice, type: "income", invoice_number: "FV/2025/001", company: company)
      insert(:invoice, type: "expense", invoice_number: "FV/2025/002", company: company)

      {:ok, _view, html} = live(conn, ~p"/invoices")
      assert html =~ "FV/2025/001"
      assert html =~ "FV/2025/002"
    end

    test "shows empty state when no invoices", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/invoices")
      assert html =~ "No invoices found"
    end
  end

  describe "filters" do
    setup %{conn: conn, company: company} do
      income = insert(:invoice, type: "income", invoice_number: "FV/INC/001", company: company)
      expense = insert(:invoice, type: "expense", invoice_number: "FV/EXP/001", company: company)
      %{conn: conn, income: income, expense: expense}
    end

    test "filters by type", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices?type=income")
      html = render(view)
      assert html =~ "FV/INC/001"
      refute html =~ "FV/EXP/001"
    end

    test "filters by status", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices?status=pending")
      html = render(view)
      assert html =~ "FV/INC/001"
      assert html =~ "FV/EXP/001"
    end

    test "filter change updates URL via push_patch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/invoices")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"type" => "income"}})

      assert_patched(view, "/invoices?type=income")
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

      {:ok, _view, html} = live(conn, ~p"/invoices")
      assert html =~ "data-testid=\"pagination\""
      assert html =~ "Showing 1"
      assert html =~ "of 30 invoices"
    end

    test "does not render pagination controls for single page", %{conn: conn, company: company} do
      insert(:invoice, company: company)

      {:ok, _view, html} = live(conn, ~p"/invoices")
      refute html =~ "data-testid=\"pagination\""
    end

    test "navigates to page 2", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/invoices?page=2")
      html = render(view)
      assert html =~ "Showing 26"
      assert html =~ "of 30 invoices"
    end

    test "filter change resets to page 1", %{conn: conn, company: company} do
      for i <- 1..30 do
        insert(:invoice,
          company: company,
          type: "income",
          invoice_number: "FV/#{String.pad_leading("#{i}", 3, "0")}"
        )
      end

      {:ok, view, _html} = live(conn, ~p"/invoices?page=2")

      view
      |> element("form[phx-change=filter]")
      |> render_change(%{"filters" => %{"type" => "income"}})

      # Should not include page param (defaults to page 1)
      assert_patched(view, "/invoices?type=income")
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
      insert(:invoice, type: "income", invoice_number: "FV/INC/999", company: company)
      insert(:invoice, type: "expense", invoice_number: "FV/EXP/999", company: company)

      {:ok, _view, html} = live(conn, ~p"/invoices")
      refute html =~ "FV/INC/999"
      assert html =~ "FV/EXP/999"
    end

    test "reviewer cannot see income invoices via type=income URL param", %{
      conn: conn,
      company: company
    } do
      insert(:invoice, type: "income", invoice_number: "FV/INC/888", company: company)
      insert(:invoice, type: "expense", invoice_number: "FV/EXP/888", company: company)

      {:ok, _view, html} = live(conn, ~p"/invoices?type=income")
      refute html =~ "FV/INC/888"
      assert html =~ "FV/EXP/888"
    end

    test "reviewer sees locked type filter", %{conn: conn, company: company} do
      insert(:invoice, type: "expense", company: company)

      {:ok, view, _html} = live(conn, ~p"/invoices")
      assert has_element?(view, "select[disabled]")
    end
  end
end
