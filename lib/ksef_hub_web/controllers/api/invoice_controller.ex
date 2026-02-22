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
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  tags(["Invoices"])
  security([%{"bearer" => []}])

  operation(:index,
    summary: "List invoices",
    description:
      "Returns a paginated list of invoices for the company associated with the API token, with optional filtering.",
    parameters: [
      type: [
        in: :query,
        description: "Filter by invoice type.",
        schema: %Schema{type: :string, enum: ["income", "expense"]}
      ],
      source: [
        in: :query,
        description: "Filter by invoice source.",
        schema: %Schema{type: :string, enum: ["ksef", "manual"]}
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
      ],
      page: [
        in: :query,
        description: "Page number (1-based, default 1).",
        schema: %Schema{type: :integer, minimum: 1, default: 1}
      ],
      per_page: [
        in: :query,
        description: "Results per page (default 25, max 100).",
        schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 25}
      ]
    ],
    responses: %{
      200 => {"Invoice list", "application/json", Schemas.InvoiceListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  def index(conn, params) do
    company_id = conn.assigns.current_company.id
    role = conn.assigns[:current_role]
    filters = build_filters(params)
    result = Invoices.list_invoices_paginated(company_id, filters, role: role)

    json(conn, %{
      data: Enum.map(result.entries, &invoice_json/1),
      meta: %{
        page: result.page,
        per_page: result.per_page,
        total_count: result.total_count,
        total_pages: result.total_pages
      }
    })
  end

  operation(:create,
    summary: "Create manual invoice",
    description:
      "Creates a manual invoice for the company. If a ksef_number is provided and matches an existing invoice, the new invoice is flagged as a suspected duplicate.",
    request_body: {"Invoice to create", "application/json", Schemas.CreateInvoiceRequest},
    responses: %{
      201 => {"Created invoice", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  def create(conn, params) do
    company_id = conn.assigns.current_company.id

    case Invoices.create_manual_invoice(company_id, atomize_keys(params)) do
      {:ok, invoice} ->
        conn
        |> put_status(:created)
        |> json(%{data: invoice_json(invoice)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
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
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])
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
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

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
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

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

  operation(:confirm_duplicate,
    summary: "Confirm duplicate invoice",
    description: "Confirms that this invoice is a duplicate of the referenced original.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Confirmed duplicate", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Not a duplicate", "application/json", Schemas.ErrorResponse}
    }
  )

  def confirm_duplicate(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    case Invoices.confirm_duplicate(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :not_a_duplicate} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invoice is not a duplicate"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:dismiss_duplicate,
    summary: "Dismiss duplicate invoice",
    description: "Dismisses the duplicate flag on this invoice.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Dismissed duplicate", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Not a duplicate", "application/json", Schemas.ErrorResponse}
    }
  )

  def dismiss_duplicate(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    case Invoices.dismiss_duplicate(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :not_a_duplicate} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invoice is not a duplicate"})

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
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    if is_nil(invoice.xml_content) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      do_html(conn, id, invoice)
    end
  end

  @spec do_html(Plug.Conn.t(), String.t(), Invoice.t()) :: Plug.Conn.t()
  defp do_html(conn, id, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_html(invoice.xml_content, metadata) do
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

  operation(:xml,
    summary: "Download invoice XML",
    description: "Returns the raw FA(3) XML content of the invoice.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"XML file", "application/xml", %Schema{type: :string}},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Download invoice XML.

  Returns the raw FA(3) XML content of the invoice identified by the `id` path
  parameter (UUID).
  """
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    if is_nil(invoice.xml_content) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      send_attachment(conn, "application/xml", "#{invoice.invoice_number}.xml", invoice.xml_content)
    end
  end

  operation(:pdf,
    summary: "Download invoice PDF",
    description: "Generates a PDF rendering of the invoice from its FA(3) XML.",
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
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    if is_nil(invoice.xml_content) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      do_pdf(conn, id, invoice)
    end
  end

  @spec do_pdf(Plug.Conn.t(), String.t(), Invoice.t()) :: Plug.Conn.t()
  defp do_pdf(conn, id, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_generator, KsefHub.Pdf)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_content, metadata) do
      {:ok, pdf_binary} ->
        send_attachment(conn, "application/pdf", "#{invoice.invoice_number}.pdf", pdf_binary)

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
    |> maybe_put(:source, params["source"])
    |> maybe_put(:seller_nip, params["seller_nip"])
    |> maybe_put(:buyer_nip, params["buyer_nip"])
    |> maybe_put(:query, params["query"])
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_integer(:page, params["page"])
    |> maybe_put_integer(:per_page, params["per_page"])
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

  @spec maybe_put_integer(map(), atom(), String.t() | integer() | nil) :: map()
  defp maybe_put_integer(map, _key, nil), do: map
  defp maybe_put_integer(map, _key, ""), do: map

  defp maybe_put_integer(map, key, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> Map.put(map, key, int)
      _ -> map
    end
  end

  defp maybe_put_integer(map, key, value) when is_integer(value) do
    Map.put(map, key, value)
  end

  @spec invoice_json(Invoice.t()) :: map()
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
      source: invoice.source,
      duplicate_of_id: invoice.duplicate_of_id,
      duplicate_status: invoice.duplicate_status,
      ksef_acquisition_date: invoice.ksef_acquisition_date,
      permanent_storage_date: invoice.permanent_storage_date,
      inserted_at: invoice.inserted_at,
      updated_at: invoice.updated_at
    }
  end

  @create_allowed_keys ~w(type ksef_number seller_nip seller_name buyer_nip buyer_name
    invoice_number issue_date net_amount vat_amount gross_amount currency)

  @spec atomize_keys(map()) :: map()
  defp atomize_keys(params) do
    for {key, value} <- params,
        key in @create_allowed_keys,
        into: %{} do
      {String.to_existing_atom(key), value}
    end
  end
end
