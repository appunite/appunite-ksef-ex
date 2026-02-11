defmodule KsefHubWeb.InvoicePdfController do
  @moduledoc """
  Controller for session-authenticated PDF downloads of invoices.
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [sanitize_filename: 1]

  alias KsefHub.Invoices

  @doc "Downloads a PDF rendering of the invoice's FA(3) XML."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    case get_session(conn, :current_company_id) do
      nil ->
        conn
        |> put_flash(:error, "Please select a company first.")
        |> redirect(to: ~p"/companies")

      company_id ->
        case Invoices.get_invoice(company_id, id) do
          nil ->
            conn
            |> put_flash(:error, "Invoice not found.")
            |> redirect(to: ~p"/invoices")

          %{xml_content: nil} = invoice ->
            conn
            |> put_flash(:error, "No XML content available for PDF generation.")
            |> redirect(to: ~p"/invoices/#{invoice.id}")

          invoice ->
            generate_and_send_pdf(conn, invoice)
        end
    end
  end

  def show(conn, _params) do
    conn
    |> put_flash(:error, "You must be logged in to download invoices.")
    |> redirect(to: ~p"/invoices")
  end

  @spec generate_and_send_pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp generate_and_send_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    metadata = %{ksef_number: invoice.ksef_number}

    with {:ok, html} <- pdf_mod.generate_html(invoice.xml_content, metadata),
         {:ok, pdf_binary} <- pdf_mod.generate_pdf(html) do
      filename = sanitize_filename("#{invoice.invoice_number}.pdf")

      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, pdf_binary)
    else
      {:error, reason} ->
        Logger.error("PDF generation failed for invoice #{invoice.id}: #{sanitize_error(reason)}")

        conn
        |> put_flash(:error, "PDF generation failed.")
        |> redirect(to: ~p"/invoices/#{invoice.id}")
    end
  end
end
