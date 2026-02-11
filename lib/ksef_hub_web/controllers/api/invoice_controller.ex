defmodule KsefHubWeb.Api.InvoiceController do
  @moduledoc """
  REST API controller for invoice operations.

  All actions are scoped to the company associated with the authenticated API token.
  """

  use KsefHubWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  import KsefHubWeb.ChangesetHelpers
  import KsefHubWeb.ErrorHelpers, only: [sanitize_error: 1]
  import KsefHubWeb.FilenameHelpers, only: [sanitize_filename: 1]

  alias KsefHub.Invoices
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  tags(["Invoices"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List invoices",
    description:
      "Returns invoices for the company associated with the API token, with optional filtering.",
    parameters: [
      type: [
        in: :query,
        description: "Filter by invoice type.",
        schema: %Schema{type: :string, enum: ["income", "expense"]}
      ],
      status: [
        in: :query,
        description: "Filter by approval status.",
        schema: %Schema{type: :string, enum: ["pending", "approved", "rejected"]}
      ],
      seller_nip: [
        in: :query,
        description: "Filter by seller NIP.",
        schema: %Schema{type: :string}
      ],
      buyer_nip: [
        in: :query,
        description: "Filter by buyer NIP.",
        schema: %Schema{type: :string}
      ],
      query: [
        in: :query,
        description: "Free-text search across invoice fields.",
        schema: %Schema{type: :string}
      ],
      date_from: [
        in: :query,
        description: "Filter invoices issued on or after this date (ISO 8601).",
        schema: %Schema{type: :string, format: :date}
      ],
      date_to: [
        in: :query,
        description: "Filter invoices issued on or before this date (ISO 8601).",
        schema: %Schema{type: :string, format: :date}
      ]
    ],
    responses: %{
      200 => {"Invoice list", "application/json", Schemas.InvoiceListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  def index(conn, params) do
    company_id = conn.assigns.current_company.id
    filters = build_filters(params)
    invoices = Invoices.list_invoices(company_id, filters)
    json(conn, %{data: Enum.map(invoices, &invoice_json/1)})
  end

  operation(:show,
    summary: "Get invoice",
    description: "Returns a single invoice by ID from the token's company.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Invoice", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id)
    json(conn, %{data: invoice_json(invoice)})
  end

  operation(:approve,
    summary: "Approve expense invoice",
    description: "Marks an expense invoice as approved. Only expense invoices can be approved.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Approved invoice", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Unprocessable entity", "application/json", Schemas.ErrorResponse}
    }
  )

  def approve(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id)

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

  operation(:reject,
    summary: "Reject expense invoice",
    description: "Marks an expense invoice as rejected. Only expense invoices can be rejected.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Rejected invoice", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Unprocessable entity", "application/json", Schemas.ErrorResponse}
    }
  )

  def reject(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id)

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

  operation(:html,
    summary: "Get invoice HTML preview",
    description:
      "Generates an HTML rendering of the invoice from its FA(3) XML using the gov.pl stylesheet.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"HTML content", "text/html", %Schema{type: :string}},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      500 => {"Generation failed", "application/json", Schemas.ErrorResponse}
    }
  )

  def html(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id)
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    case pdf_mod.generate_html(invoice.xml_content) do
      {:ok, html_content} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html_content)

      {:error, reason} ->
        Logger.error("HTML generation failed for invoice #{id}: #{sanitize_error(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "HTML generation failed"})
    end
  end

  operation(:pdf,
    summary: "Download invoice PDF",
    description:
      "Generates a PDF rendering of the invoice from its FA(3) XML via xsltproc and Gotenberg.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"PDF file", "application/pdf", %Schema{type: :string, format: :binary}},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      500 => {"Generation failed", "application/json", Schemas.ErrorResponse}
    }
  )

  def pdf(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id)
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
        Logger.error("PDF generation failed for invoice #{id}: #{sanitize_error(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "PDF generation failed"})
    end
  end

  # --- Private ---

  @spec build_filters(map()) :: map()
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

  @spec maybe_put(map(), atom(), String.t() | nil) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_date(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  @spec invoice_json(KsefHub.Invoices.Invoice.t()) :: map()
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
end
