defmodule KsefHubWeb.InvoicePdfController do
  @moduledoc """
  Controller for session-authenticated invoice file downloads (PDF and XML).
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Invoices

  @doc "Downloads the raw FA(3) XML of the invoice."
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    with_invoice(conn, id, fn conn, invoice ->
      send_attachment(
        conn,
        "application/xml",
        "#{invoice.invoice_number}.xml",
        invoice.xml_content
      )
    end)
  end

  def xml(conn, _params), do: redirect_unauthenticated(conn)

  @doc "Downloads a PDF rendering of the invoice's FA(3) XML."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    with_invoice(conn, id, fn conn, invoice ->
      generate_and_send_pdf(conn, invoice)
    end)
  end

  def show(conn, _params), do: redirect_unauthenticated(conn)

  @spec with_invoice(Plug.Conn.t(), String.t(), (Plug.Conn.t(), map() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  defp with_invoice(conn, id, fun) do
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
            |> put_flash(:error, "No XML content available for this invoice.")
            |> redirect(to: ~p"/invoices/#{invoice.id}")

          invoice ->
            fun.(conn, invoice)
        end
    end
  end

  @spec redirect_unauthenticated(Plug.Conn.t()) :: Plug.Conn.t()
  defp redirect_unauthenticated(conn) do
    conn
    |> put_flash(:error, "You must be logged in to download invoices.")
    |> redirect(to: ~p"/invoices")
  end

  @spec generate_and_send_pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp generate_and_send_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_content, metadata) do
      {:ok, pdf_binary} ->
        send_attachment(conn, "application/pdf", "#{invoice.invoice_number}.pdf", pdf_binary)

      {:error, reason} ->
        Logger.error("PDF generation failed for invoice #{invoice.id}: #{sanitize_error(reason)}")

        conn
        |> put_flash(:error, "PDF generation failed.")
        |> redirect(to: ~p"/invoices/#{invoice.id}")
    end
  end
end
