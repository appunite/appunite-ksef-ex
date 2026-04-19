defmodule KsefHubWeb.InvoiceLive.PublicShowTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup :set_mox_from_context
  setup :verify_on_exit!

  defp create_invoice_with_token(_context) do
    company = insert(:company)
    invoice = insert(:invoice, company: company)
    user = insert(:user)
    {:ok, pt, _} = Invoices.ensure_public_token(invoice, user.id)

    %{company: company, invoice: invoice, token: pt.token}
  end

  defp stub_pdf(_context) do
    stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
    :ok
  end

  describe "public show with valid token" do
    setup [:create_invoice_with_token, :stub_pdf]

    test "renders public page for unauthenticated user", %{
      conn: conn,
      invoice: invoice,
      token: token
    } do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      assert html =~ invoice.invoice_number
      assert html =~ invoice.seller_name
      assert html =~ invoice.buyer_name
    end

    test "does not show approve/reject buttons", %{conn: conn, invoice: invoice, token: token} do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute html =~ "Approve"
      refute html =~ "Reject"
    end

    test "does not show edit button", %{conn: conn, invoice: invoice, token: token} do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute html =~ "toggle_edit"
    end

    test "does not show notes section", %{conn: conn, invoice: invoice, token: token} do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute html =~ "Note"
    end

    test "does not show comments section", %{conn: conn, invoice: invoice, token: token} do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute html =~ "Comments"
    end

    test "does not show classification section", %{conn: conn, invoice: invoice, token: token} do
      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute html =~ "Classification"
    end

    test "does not show 'Added by' row", %{conn: conn, invoice: invoice, token: token} do
      {:ok, view, _html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      refute has_element?(view, "#added-by-row")
    end
  end

  describe "public show with invalid/missing token" do
    setup :stub_pdf

    test "redirects when token is missing", %{conn: conn} do
      invoice = insert(:invoice)

      {:error, {:redirect, %{to: "/", flash: %{"error" => "Invoice not found."}}}} =
        live(conn, ~p"/public/invoices/#{invoice.id}")
    end

    test "redirects when token is wrong", %{conn: conn} do
      invoice = insert(:invoice)

      {:error, {:redirect, %{to: "/", flash: %{"error" => "Invoice not found."}}}} =
        live(conn, ~p"/public/invoices/#{invoice.id}?token=invalid-token")
    end

    test "redirects when token belongs to a different invoice", %{conn: conn} do
      company = insert(:company)
      invoice1 = insert(:invoice, company: company)
      invoice2 = insert(:invoice, company: company)
      user = insert(:user)
      {:ok, pt2, _} = Invoices.ensure_public_token(invoice2, user.id)

      {:error, {:redirect, %{to: "/", flash: %{"error" => "Invoice not found."}}}} =
        live(conn, ~p"/public/invoices/#{invoice1.id}?token=#{pt2.token}")
    end
  end

  describe "logged-in user behavior" do
    setup [:create_invoice_with_token, :stub_pdf]

    test "redirects member to authenticated page", %{
      conn: conn,
      invoice: invoice,
      token: token,
      company: company
    } do
      {:ok, user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-public-member",
          email: "member@example.com",
          name: "Member"
        })

      insert(:membership, user: user, company: company, role: :approver)

      conn = conn |> log_in_user(user, %{current_company_id: company.id})

      {:error, {:redirect, %{to: redirect_path}}} =
        live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      assert redirect_path =~ "/c/#{company.id}/invoices/#{invoice.id}"
    end

    test "non-member sees public page", %{conn: conn, invoice: invoice, token: token} do
      {:ok, user} =
        Accounts.get_or_create_google_user(%{
          uid: "g-public-nonmember",
          email: "outsider@example.com",
          name: "Outsider"
        })

      conn = conn |> log_in_user(user)

      {:ok, _view, html} = live(conn, ~p"/public/invoices/#{invoice.id}?token=#{token}")

      assert html =~ invoice.invoice_number
    end
  end
end
