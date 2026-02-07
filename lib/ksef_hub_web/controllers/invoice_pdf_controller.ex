defmodule KsefHubWeb.InvoicePdfController do
  use KsefHubWeb, :controller

  alias KsefHub.Invoices

  def show(conn, %{"id" => id}) do
    invoice = Invoices.get_invoice!(id)
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
        conn
        |> put_flash(:error, "PDF generation failed: #{inspect(reason)}")
        |> redirect(to: ~p"/invoices/#{invoice.id}")
    end
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.slice(0, 200)
  end
end
