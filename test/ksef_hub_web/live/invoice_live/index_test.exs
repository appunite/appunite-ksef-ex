defmodule KsefHubWeb.InvoiceLive.IndexTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.find_or_create_user(%{uid: "g-inv-1", email: "test@example.com", name: "Test"})

    conn = conn |> init_test_session(%{user_id: user.id})
    %{conn: conn, user: user}
  end

  describe "mount" do
    test "renders invoice list page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/invoices")
      assert html =~ "Invoices"
    end

    test "shows invoices in table", %{conn: conn} do
      insert(:invoice, type: "income", invoice_number: "FV/2025/001")
      insert(:invoice, type: "expense", invoice_number: "FV/2025/002")

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
    setup %{conn: conn} do
      income = insert(:invoice, type: "income", invoice_number: "FV/INC/001")
      expense = insert(:invoice, type: "expense", invoice_number: "FV/EXP/001")
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
      |> element("form")
      |> render_change(%{"type" => "income"})

      assert_patched(view, "/invoices?type=income")
    end
  end
end
