defmodule KsefHubWeb.InvoicePdfController do
  @moduledoc """
  Controller for session-authenticated invoice file downloads (PDF and XML).
  """
  use KsefHubWeb, :controller

  require Logger

  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4, send_inline: 4]
  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]

  alias KsefHub.Invoices

  @doc "Downloads the raw FA(3) XML of the invoice."
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id}) do
    with_invoice(conn, id, fn conn, invoice ->
      case invoice do
        %{xml_file: %{content: content}} when is_binary(content) and content != "" ->
          send_attachment(conn, "application/xml", "#{invoice.invoice_number}.xml", content)

        _ ->
          conn
          |> put_flash(:error, "No XML content available for this invoice.")
          |> redirect(to: ~p"/invoices/#{invoice.id}")
      end
    end)
  end

  def xml(conn, _params), do: redirect_unauthenticated(conn)

  @doc "Downloads a PDF for the invoice — serves the stored PDF for pdf_upload invoices, or generates one from XML. Pass `?inline=1` to use Content-Disposition: inline (for iframe previews)."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(%{assigns: %{current_user: %{id: _}}} = conn, %{"id" => id} = params) do
    inline? = params["inline"] == "1"

    with_invoice(conn, id, inline?, fn conn, invoice ->
      send_pdf(conn, invoice, inline?)
    end)
  end

  def show(conn, _params), do: redirect_unauthenticated(conn)

  @spec with_invoice(Plug.Conn.t(), String.t(), boolean(), (Plug.Conn.t(), map() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  defp with_invoice(conn, id, inline? \\ false, fun) do
    user = conn.assigns[:current_user]
    user_id = user && user.id

    with {:company, company_id} when not is_nil(company_id) <-
           {:company, get_session(conn, :current_company_id) || first_company_id(user_id)},
         role <- resolve_role(user_id, company_id),
         {:invoice, %{} = invoice} <-
           {:invoice, Invoices.get_invoice_with_details(company_id, id, role: role)} do
      fun.(conn, invoice)
    else
      {:company, nil} ->
        if inline? do
          send_inline_error(conn, "Please select a company first.")
        else
          conn
          |> put_flash(:error, "Please select a company first.")
          |> redirect(to: ~p"/companies")
        end

      {:invoice, nil} ->
        if inline? do
          send_inline_error(conn, "Invoice not found.")
        else
          conn
          |> put_flash(:error, "Invoice not found.")
          |> redirect(to: ~p"/invoices")
        end
    end
  end

  @spec redirect_unauthenticated(Plug.Conn.t()) :: Plug.Conn.t()
  defp redirect_unauthenticated(conn) do
    conn
    |> put_flash(:error, "You must be logged in to download invoices.")
    |> redirect(to: ~p"/invoices")
  end

  @spec send_pdf(Plug.Conn.t(), map(), boolean()) :: Plug.Conn.t()
  defp send_pdf(conn, %{pdf_file: %{content: content}} = invoice, inline?)
       when is_binary(content) and content != "" do
    send_fn = if inline?, do: &send_inline/4, else: &send_attachment/4
    send_fn.(conn, "application/pdf", "#{invoice.invoice_number}.pdf", content)
  end

  defp send_pdf(conn, %{xml_file: %{content: content}} = invoice, inline?)
       when is_binary(content) and content != "" do
    generate_and_send_pdf(conn, invoice, inline?)
  end

  defp send_pdf(conn, invoice, inline?) do
    if inline? do
      send_inline_error(conn, "No PDF or XML content available.")
    else
      conn
      |> put_flash(:error, "No PDF or XML content available for this invoice.")
      |> redirect(to: ~p"/invoices/#{invoice.id}")
    end
  end

  @spec generate_and_send_pdf(Plug.Conn.t(), map(), boolean()) :: Plug.Conn.t()
  defp generate_and_send_pdf(conn, invoice, inline?) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_file.content, metadata) do
      {:ok, pdf_binary} when is_binary(pdf_binary) and pdf_binary != "" ->
        send_fn = if inline?, do: &send_inline/4, else: &send_attachment/4
        send_fn.(conn, "application/pdf", "#{invoice.invoice_number}.pdf", pdf_binary)

      {:ok, _empty} ->
        Logger.error("PDF generation returned empty content for invoice #{invoice.id}")
        pdf_error_response(conn, invoice, inline?, "PDF generation failed.")

      {:error, reason} ->
        Logger.error("PDF generation failed for invoice #{invoice.id}: #{sanitize_error(reason)}")
        pdf_error_response(conn, invoice, inline?, "PDF generation failed.")
    end
  end

  @spec pdf_error_response(Plug.Conn.t(), map(), boolean(), String.t()) :: Plug.Conn.t()
  defp pdf_error_response(conn, _invoice, true, message), do: send_inline_error(conn, message)

  defp pdf_error_response(conn, invoice, false, message) do
    conn
    |> put_flash(:error, message)
    |> redirect(to: ~p"/invoices/#{invoice.id}")
  end

  @spec first_company_id(String.t() | nil) :: String.t() | nil
  defp first_company_id(nil), do: nil

  defp first_company_id(user_id) do
    case KsefHub.Companies.list_companies_for_user(user_id) do
      [%{id: id} | _] -> id
      _ -> nil
    end
  end

  @spec send_inline_error(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp send_inline_error(conn, message) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, """
    <html><body style="display:flex;align-items:center;justify-content:center;height:100%;margin:0;font-family:sans-serif;color:#666;">
    <p>#{message}</p>
    </body></html>
    """)
  end
end
