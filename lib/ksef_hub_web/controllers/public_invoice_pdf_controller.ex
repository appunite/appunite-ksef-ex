defmodule KsefHubWeb.PublicInvoicePdfController do
  @moduledoc """
  Controller for public invoice PDF downloads via shareable token.
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [send_inline: 4, send_inline_error: 3]

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  @doc "Serves the invoice PDF inline for iframe preview, validated by public token."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id, "token" => token}) do
    with %Invoice{} = invoice <- Invoices.get_invoice_by_public_token(token),
         true <- invoice.id == id do
      send_pdf(conn, invoice)
    else
      _ -> send_inline_error(conn, 404, "Not found.")
    end
  end

  def show(conn, _params), do: send_inline_error(conn, 404, "Not found.")

  @spec send_pdf(Plug.Conn.t(), Invoice.t()) :: Plug.Conn.t()
  defp send_pdf(conn, %{pdf_file: %{content: content}} = invoice)
       when is_binary(content) and content != "" do
    send_inline(conn, "application/pdf", "#{invoice.invoice_number}.pdf", content)
  end

  defp send_pdf(conn, %{xml_file: %{content: content}} = invoice)
       when is_binary(content) and content != "" do
    generate_and_send_pdf(conn, invoice)
  end

  defp send_pdf(conn, _invoice) do
    send_inline_error(conn, 422, "No PDF or XML content available.")
  end

  @spec generate_and_send_pdf(Plug.Conn.t(), Invoice.t()) :: Plug.Conn.t()
  defp generate_and_send_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)
    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_file.content, metadata) do
      {:ok, pdf_binary} when is_binary(pdf_binary) and pdf_binary != "" ->
        send_inline(conn, "application/pdf", "#{invoice.invoice_number}.pdf", pdf_binary)

      {:ok, _empty} ->
        Logger.error("PDF generation returned empty content for public invoice #{invoice.id}")
        send_inline_error(conn, 422, "PDF generation failed.")

      {:error, reason} ->
        Logger.error(
          "PDF generation failed for public invoice #{invoice.id}: #{sanitize_error(reason)}"
        )

        send_inline_error(conn, 422, "PDF generation failed.")
    end
  end
end
