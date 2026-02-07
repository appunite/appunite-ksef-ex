defmodule KsefHubWeb.InvoicePdfController do
  @moduledoc """
  Controller for session-authenticated PDF downloads of invoices.
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]

  alias KsefHub.Invoices

  def show(conn, %{"id" => id}) do
    case Invoices.get_invoice(id) do
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

  defp generate_and_send_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    with {:ok, html} <- pdf_mod.generate_html(invoice.xml_content),
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

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.slice(0, 200)
  end
end
