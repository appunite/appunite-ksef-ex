defmodule KsefHubWeb.InvoicePdfController do
  @moduledoc """
  Controller for session-authenticated invoice file downloads (PDF and XML).
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]
  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]

  alias KsefHub.Invoices

  @doc "Downloads the raw FA(3) XML of the invoice."
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    with_invoice(conn, id, fn conn, invoice ->
      if invoice.xml_file do
        send_attachment(
          conn,
          "application/xml",
          "#{invoice.invoice_number}.xml",
          invoice.xml_file.content
        )
      else
        conn
        |> put_flash(:error, "No XML content available for this invoice.")
        |> redirect(to: ~p"/invoices/#{invoice.id}")
      end
    end)
  end

  def xml(conn, _params), do: redirect_unauthenticated(conn)

  @doc "Downloads a PDF for the invoice — serves the stored PDF for pdf_upload invoices, or generates one from XML."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    with_invoice(conn, id, fn conn, invoice ->
      send_pdf(conn, invoice)
    end)
  end

  def show(conn, _params), do: redirect_unauthenticated(conn)

  @spec with_invoice(Plug.Conn.t(), String.t(), (Plug.Conn.t(), map() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  defp with_invoice(conn, id, fun) do
    user_id = conn.assigns[:current_user] && conn.assigns.current_user.id

    with {:company, company_id} when not is_nil(company_id) <-
           {:company, get_session(conn, :current_company_id)},
         role <- resolve_role(user_id, company_id),
         {:invoice, %{} = invoice} <-
           {:invoice, Invoices.get_invoice_with_details(company_id, id, role: role)} do
      fun.(conn, invoice)
    else
      {:company, nil} ->
        conn
        |> put_flash(:error, "Please select a company first.")
        |> redirect(to: ~p"/companies")

      {:invoice, nil} ->
        conn
        |> put_flash(:error, "Invoice not found.")
        |> redirect(to: ~p"/invoices")
    end
  end

  @spec redirect_unauthenticated(Plug.Conn.t()) :: Plug.Conn.t()
  defp redirect_unauthenticated(conn) do
    conn
    |> put_flash(:error, "You must be logged in to download invoices.")
    |> redirect(to: ~p"/invoices")
  end

  @spec send_pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp send_pdf(conn, %{pdf_file: %{content: content}} = invoice) when is_binary(content) do
    send_attachment(conn, "application/pdf", "#{invoice.invoice_number}.pdf", content)
  end

  defp send_pdf(conn, %{xml_file: %{}} = invoice) do
    generate_and_send_pdf(conn, invoice)
  end

  defp send_pdf(conn, invoice) do
    conn
    |> put_flash(:error, "No PDF or XML content available for this invoice.")
    |> redirect(to: ~p"/invoices/#{invoice.id}")
  end

  @spec generate_and_send_pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp generate_and_send_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_file.content, metadata) do
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
