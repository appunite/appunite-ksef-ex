defmodule KsefHubWeb.Api.InvoiceController do
  use KsefHubWeb, :controller

  require Logger

  alias KsefHub.Invoices

  def index(conn, params) do
    filters = build_filters(params)
    invoices = Invoices.list_invoices(filters)
    json(conn, %{data: Enum.map(invoices, &invoice_json/1)})
  end

  def show(conn, %{"id" => id}) do
    invoice = Invoices.get_invoice!(id)
    json(conn, %{data: invoice_json(invoice)})
  end

  def approve(conn, %{"invoice_id" => id}) do
    invoice = Invoices.get_invoice!(id)

    case Invoices.approve_invoice(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, {:invalid_type, _type}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Only expense invoices can be approved"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  def reject(conn, %{"invoice_id" => id}) do
    invoice = Invoices.get_invoice!(id)

    case Invoices.reject_invoice(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, {:invalid_type, _type}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Only expense invoices can be rejected"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  def html(conn, %{"invoice_id" => id}) do
    invoice = Invoices.get_invoice!(id)
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    case pdf_mod.generate_html(invoice.xml_content) do
      {:ok, html_content} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html_content)

      {:error, reason} ->
        Logger.error("HTML generation failed for invoice #{id}: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "HTML generation failed"})
    end
  end

  def pdf(conn, %{"invoice_id" => id}) do
    invoice = Invoices.get_invoice!(id)
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    with {:ok, html_content} <- pdf_mod.generate_html(invoice.xml_content),
         {:ok, pdf_binary} <- pdf_mod.generate_pdf(html_content) do
      filename = sanitize_filename("#{invoice.invoice_number}.pdf")

      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, pdf_binary)
    else
      {:error, reason} ->
        Logger.error("PDF generation failed for invoice #{id}: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "PDF generation failed"})
    end
  end

  # --- Private ---

  defp build_filters(params) do
    %{}
    |> maybe_put(:type, params["type"])
    |> maybe_put(:status, params["status"])
    |> maybe_put(:seller_nip, params["seller_nip"])
    |> maybe_put(:buyer_nip, params["buyer_nip"])
    |> maybe_put(:query, params["query"])
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  defp invoice_json(invoice) do
    %{
      id: invoice.id,
      ksef_number: invoice.ksef_number,
      type: invoice.type,
      seller_nip: invoice.seller_nip,
      seller_name: invoice.seller_name,
      buyer_nip: invoice.buyer_nip,
      buyer_name: invoice.buyer_name,
      invoice_number: invoice.invoice_number,
      issue_date: invoice.issue_date,
      net_amount: invoice.net_amount,
      vat_amount: invoice.vat_amount,
      gross_amount: invoice.gross_amount,
      currency: invoice.currency,
      status: invoice.status,
      ksef_acquisition_date: invoice.ksef_acquisition_date,
      permanent_storage_date: invoice.permanent_storage_date,
      inserted_at: invoice.inserted_at,
      updated_at: invoice.updated_at
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[^\w\.\-]/, "_")
    |> String.slice(0, 200)
  end
end
