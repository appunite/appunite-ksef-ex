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
  import KsefHubWeb.JsonHelpers, only: [category_json: 1, tag_json: 1, atomize_keys: 2]

  alias KsefHub.Invoices
  alias KsefHub.Invoices.{CostLine, Invoice}
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  plug KsefHubWeb.Plugs.RequirePermission, :create_invoice when action in [:create, :upload]

  plug KsefHubWeb.Plugs.RequirePermission,
       :update_invoice when action in [:update, :confirm_duplicate, :dismiss_duplicate]

  plug KsefHubWeb.Plugs.RequirePermission,
       :approve_invoice when action in [:approve, :reject, :reset_status]

  plug KsefHubWeb.Plugs.RequirePermission, :set_invoice_category when action == :set_category
  plug KsefHubWeb.Plugs.RequirePermission, :set_invoice_tags when action == :set_tags

  plug KsefHubWeb.Plugs.RequirePermission,
       :set_invoice_tags when action in [:set_project_tag, :list_project_tags]

  plug KsefHubWeb.Plugs.RequirePermission,
       :manage_team when action in [:get_access, :set_access, :grant_access, :revoke_access]

  @create_allowed_keys ~w(type ksef_number seller_nip seller_name buyer_nip buyer_name
    invoice_number issue_date net_amount gross_amount currency purchase_order
    sales_date due_date billing_date_from billing_date_to iban)

  @max_pdf_size 10_000_000

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
        schema: %Schema{type: :string, enum: ["ksef", "manual", "pdf_upload"]}
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
      billing_date_from: [
        in: :query,
        description:
          "Filter invoices whose billing period overlaps on or after this date (ISO 8601). Uses overlap semantics: returns invoices where billing_date_to >= this value.",
        schema: %Schema{type: :string, format: :date}
      ],
      billing_date_to: [
        in: :query,
        description:
          "Filter invoices whose billing period overlaps on or before this date (ISO 8601). Uses overlap semantics: returns invoices where billing_date_from <= this value.",
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
      ],
      category_id: [
        in: :query,
        description: "Filter by category UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ],
      "tag_ids[]": [
        in: :query,
        description: "Filter by one or more tag UUIDs.",
        schema: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
      ]
    ],
    responses: %{
      200 =>
        {"Paginated invoice list with metadata", "application/json", Schemas.InvoiceListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists invoices for the token's company with optional filters and pagination."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    company_id = conn.assigns.current_company.id
    role = conn.assigns[:current_role]
    filters = build_filters(params)

    result =
      Invoices.list_invoices_paginated(company_id, filters,
        role: role,
        user_id: conn.assigns.api_token.created_by_id
      )

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — missing required fields or invalid values", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Creates a manual invoice, auto-detecting duplicates by ksef_number."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id

    attrs =
      params
      |> atomize_keys(@create_allowed_keys)
      |> Map.put(:created_by_id, conn.assigns.api_token.created_by_id)

    case Invoices.create_manual_invoice(company_id, attrs) do
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

  operation(:upload,
    summary: "Upload PDF invoice",
    description:
      "Uploads a PDF invoice file for automatic data extraction via the au-ksef-unstructured service. If extraction is incomplete, the invoice is created with extraction_status 'partial' and can be completed via PATCH.",
    request_body: {"PDF invoice upload", "multipart/form-data", Schemas.UploadInvoiceRequest},
    responses: %{
      201 =>
        {"Created invoice — check extraction_status (complete, partial, or failed)",
         "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      413 => {"File too large — maximum 10 MB", "application/json", Schemas.ErrorResponse},
      415 =>
        {"Unsupported content type — only PDF files are accepted", "application/json",
         Schemas.ErrorResponse},
      422 =>
        {"Validation error — missing file or type parameter, or invalid values",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Uploads a PDF invoice for automatic data extraction."
  @spec upload(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def upload(conn, params) do
    company = conn.assigns.current_company

    with {:ok, upload} <- validate_file_present(params),
         {:ok, _type} <- validate_type_present(params),
         :ok <- validate_content_type(upload),
         :ok <- validate_file_size(upload) do
      pdf_binary = File.read!(upload.path)
      type = params["type"]
      filename = upload.filename

      case Invoices.create_pdf_upload_invoice(company, pdf_binary, %{
             type: type,
             filename: filename,
             created_by_id: conn.assigns.api_token.created_by_id
           }) do
        {:ok, invoice} ->
          conn
          |> put_status(:created)
          |> json(%{data: invoice_json(invoice)})

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: changeset_errors(changeset)})

        {:error, reason} ->
          Logger.error("PDF upload failed: #{inspect(reason)}")

          conn
          |> put_status(:bad_gateway)
          |> json(%{error: "Extraction service error"})
      end
    else
      {:error, :missing_file} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Missing required file parameter"})

      {:error, :missing_type} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Missing or invalid type parameter (must be 'income' or 'expense')"})

      {:error, :invalid_content_type} ->
        conn
        |> put_status(:unsupported_media_type)
        |> json(%{error: "File must be a PDF (application/pdf)"})

      {:error, :file_too_large} ->
        conn
        |> put_status(413)
        |> json(%{error: "File too large (max 10MB)"})
    end
  end

  operation(:update,
    summary: "Update invoice",
    description:
      "Updates data fields on a non-KSeF invoice. KSeF invoices are legally immutable and cannot be updated. Recalculates extraction_status after update.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Invoice fields to update", "application/json", Schemas.UpdateInvoiceRequest},
    responses: %{
      200 => {"Updated invoice", "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — KSeF invoices cannot be updated, or invalid field values",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Updates data fields on a non-KSeF invoice."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    do_update(conn, invoice, params)
  end

  @spec do_update(Plug.Conn.t(), Invoice.t(), map()) :: Plug.Conn.t()
  defp do_update(conn, %Invoice{} = invoice, params) do
    case Invoices.update_invoice_fields(invoice, params) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :ksef_not_editable} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "KSeF invoices cannot be updated"})

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
      200 => {"Invoice with category and tags", "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns a single invoice by UUID with category and tags preloaded."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice_with_details!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Only expense invoices can be approved, or extraction is incomplete", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Approves an expense invoice."
  @spec approve(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def approve(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    case Invoices.approve_invoice(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :incomplete_extraction} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error:
            "Cannot approve invoice with incomplete extraction. Fill in missing fields first."
        })

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 => {"Only expense invoices can be rejected", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Rejects an expense invoice."
  @spec reject(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def reject(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

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

  operation(:reset_status,
    summary: "Reset expense invoice status",
    description:
      "Resets an approved or rejected expense invoice back to pending. Only expense invoices can be reset.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Reset invoice", "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Invoice is already pending or not an expense invoice", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Resets an expense invoice status back to pending."
  @spec reset_status(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def reset_status(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    case Invoices.reset_invoice_status(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :already_pending} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invoice is already pending"})

      {:error, {:invalid_type, _type}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Only expense invoices can be reset"})

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Invoice is not flagged as a suspected duplicate", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Confirms a suspected duplicate invoice."
  @spec confirm_duplicate(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def confirm_duplicate(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    case Invoices.confirm_duplicate(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :not_a_duplicate} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invoice is not a duplicate"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Duplicate can only be confirmed from suspected status"})

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Invoice is not a duplicate, or has already been dismissed", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Dismisses the duplicate flag on an invoice."
  @spec dismiss_duplicate(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def dismiss_duplicate(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    case Invoices.dismiss_duplicate(invoice) do
      {:ok, updated} ->
        json(conn, %{data: invoice_json(updated)})

      {:error, :not_a_duplicate} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invoice is not a duplicate"})

      {:error, :invalid_status} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Duplicate has already been dismissed"})

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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Invoice has no XML content (e.g. pdf_upload without FA(3) XML)", "application/json",
         Schemas.ErrorResponse},
      500 =>
        {"HTML generation failed — pdf-renderer sidecar error", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Generates an HTML rendering of the invoice from its FA(3) XML."
  @spec html(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def html(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice_with_details!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    if is_nil(invoice.xml_file) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      do_html(conn, id, invoice)
    end
  end

  @spec do_html(Plug.Conn.t(), String.t(), Invoice.t()) :: Plug.Conn.t()
  defp do_html(conn, id, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_html(invoice.xml_file.content, metadata) do
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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 => {"Invoice has no XML content", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns the raw FA(3) XML content of the invoice."
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice_with_details!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    if is_nil(invoice.xml_file) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      send_attachment(
        conn,
        "application/xml",
        "#{invoice.invoice_number}.xml",
        invoice.xml_file.content
      )
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
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Invoice has no XML content and no uploaded PDF", "application/json",
         Schemas.ErrorResponse},
      500 =>
        {"PDF generation failed — pdf-renderer sidecar error", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Generates a PDF rendering of the invoice from its FA(3) XML, or returns the original uploaded PDF."
  @spec pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def pdf(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice_with_details!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    serve_pdf(conn, invoice)
  end

  @spec serve_pdf(Plug.Conn.t(), Invoice.t()) :: Plug.Conn.t()
  defp serve_pdf(conn, %Invoice{source: source, pdf_file: %{content: content}} = invoice)
       when source in [:pdf_upload, :email] do
    filename = invoice.original_filename || "#{invoice.invoice_number || "invoice"}.pdf"
    send_attachment(conn, "application/pdf", filename, content)
  end

  defp serve_pdf(conn, %Invoice{xml_file: %{content: xml}} = invoice) when not is_nil(xml) do
    do_pdf(conn, invoice)
  end

  defp serve_pdf(conn, _invoice) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invoice has no downloadable content"})
  end

  @spec do_pdf(Plug.Conn.t(), Invoice.t()) :: Plug.Conn.t()
  defp do_pdf(conn, invoice) do
    pdf_mod = Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer)

    metadata = %{ksef_number: invoice.ksef_number}

    case pdf_mod.generate_pdf(invoice.xml_file.content, metadata) do
      {:ok, pdf_binary} ->
        send_attachment(conn, "application/pdf", "#{invoice.invoice_number}.pdf", pdf_binary)

      {:error, reason} ->
        Logger.error("PDF generation failed for invoice #{invoice.id}: #{sanitize_error(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "PDF generation failed"})
    end
  end

  operation(:set_category,
    summary: "Set invoice category",
    description: "Assigns or clears the category on an invoice.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Category assignment", "application/json", Schemas.SetCategoryRequest},
    responses: %{
      200 => {"Updated invoice with category", "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Validation error — invalid UUID, category not in company, or invoice is not an expense",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Sets or clears the category on an invoice."
  @spec set_category(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_category(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id
    role = conn.assigns[:current_role]
    user_id = conn.assigns.api_token.created_by_id
    invoice = Invoices.get_invoice!(company_id, id, role: role, user_id: user_id)
    category_id = params["category_id"]

    with {:ok, cost_line} <- cast_cost_line_param(params),
         :ok <- validate_category_company(category_id, company_id),
         {:ok, updated} <- Invoices.set_invoice_category(invoice, category_id),
         {:ok, updated} <- maybe_set_api_cost_line(updated, cost_line),
         {:ok, _} <- Invoices.mark_prediction_manual(updated) do
      invoice = Invoices.get_invoice_with_details!(company_id, id, role: role, user_id: user_id)
      json(conn, %{data: invoice_json(invoice)})
    else
      {:error, :invalid_cost_line} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid cost_line value"})

      {:error, :invalid_uuid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid UUID format"})

      {:error, :expense_only} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Categories can only be assigned to expense invoices"})

      {:error, reason} when reason in [:category_not_found, :category_not_in_company] ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Category not found in this company"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:set_tags,
    summary: "Set invoice tags",
    description:
      "Replaces all tags on an invoice with the given list. Pass an empty list to clear all tags.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Tags to set", "application/json", Schemas.InvoiceTagsRequest},
    responses: %{
      200 => {"Updated list of tags on the invoice", "application/json", Schemas.TagListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"One or more tags not found in this company, or invalid UUID format", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Replaces all tags on an invoice."
  @spec set_tags(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_tags(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    with {:ok, tag_ids} <- validate_tag_ids(params["tag_ids"]),
         true <- Invoices.tags_belong_to_company?(tag_ids, company_id),
         {:ok, tags} <- Invoices.set_invoice_tags(id, tag_ids),
         {:ok, _} <- Invoices.mark_prediction_manual(invoice) do
      json(conn, %{data: Enum.map(tags, &tag_json/1)})
    else
      error -> render_tag_error(conn, id, error)
    end
  end

  # --- Project Tags ---

  operation(:set_project_tag,
    summary: "Set invoice project tag",
    description:
      "Sets or clears the project tag on an invoice. Works for both income and expense invoices.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Project tag assignment", "application/json", Schemas.SetProjectTagRequest},
    responses: %{
      200 => {"Updated invoice", "application/json", Schemas.InvoiceResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Sets or clears the project tag on an invoice."
  @spec set_project_tag(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_project_tag(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id
    role = conn.assigns[:current_role]
    user_id = conn.assigns.api_token.created_by_id
    invoice = Invoices.get_invoice!(company_id, id, role: role, user_id: user_id)

    project_tag = params["project_tag"]

    with {:ok, updated} <- Invoices.set_invoice_project_tag(invoice, project_tag),
         {:ok, _} <- Invoices.mark_prediction_manual(updated) do
      invoice = Invoices.get_invoice_with_details!(company_id, id, role: role, user_id: user_id)
      json(conn, %{data: invoice_json(invoice)})
    else
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:list_project_tags,
    summary: "List available project tags",
    description:
      "Returns distinct project tag values used on invoices in the last year, ordered by most recently used.",
    responses: %{
      200 => {"List of project tags", "application/json", Schemas.ProjectTagListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists distinct project tag values for the company."
  @spec list_project_tags(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def list_project_tags(conn, _params) do
    company_id = conn.assigns.current_company.id
    tags = Invoices.list_project_tags(company_id)
    json(conn, %{data: tags})
  end

  # --- Access Control ---

  operation(:get_access,
    summary: "Get invoice access control",
    description:
      "Returns the access restriction status and list of access grants for an invoice. Requires manage_team permission.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 =>
        {"Access control status and grants", "application/json", Schemas.AccessGrantListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns access restriction status and grants for an invoice."
  @spec get_access(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def get_access(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    grants = Invoices.list_access_grants(invoice.id)

    json(conn, %{
      data: %{
        access_restricted: invoice.access_restricted,
        grants: Enum.map(grants, &access_grant_json/1)
      }
    })
  end

  operation(:set_access,
    summary: "Set invoice access restriction",
    description:
      "Toggles whether the invoice is restricted to only granted reviewers. Owners, admins, and accountants always have access regardless. Requires manage_team permission.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"Access restriction setting", "application/json",
       %Schema{
         type: :object,
         properties: %{
           access_restricted: %Schema{type: :boolean, description: "Whether to restrict access."}
         },
         required: [:access_restricted]
       }},
    responses: %{
      200 =>
        {"Updated access control status", "application/json", Schemas.AccessGrantListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Unprocessable Entity — access_restricted (boolean) is required", "application/json",
         Schemas.ErrorResponse}
    }
  )

  @doc "Sets the access_restricted flag on an invoice."
  @spec set_access(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_access(conn, %{"id" => id, "access_restricted" => restricted})
      when is_boolean(restricted) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice!(company_id, id,
        role: conn.assigns[:current_role],
        user_id: conn.assigns.api_token.created_by_id
      )

    case Invoices.set_access_restricted(invoice, restricted) do
      {:ok, updated} ->
        grants = Invoices.list_access_grants(updated.id)

        json(conn, %{
          data: %{
            access_restricted: updated.access_restricted,
            grants: Enum.map(grants, &access_grant_json/1)
          }
        })

      {:error, :income_always_restricted} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Income invoices cannot be unrestricted"})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to update access restriction"})
    end
  end

  def set_access(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "access_restricted (boolean) is required"})
  end

  operation(:grant_access,
    summary: "Grant invoice access",
    description:
      "Grants a user access to a restricted invoice. Idempotent — duplicate grants are silently accepted. Requires manage_team permission.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body:
      {"User to grant access to", "application/json",
       %Schema{
         type: :object,
         properties: %{
           user_id: %Schema{
             type: :string,
             format: :uuid,
             description: "UUID of the user to grant access to."
           }
         },
         required: [:user_id]
       }},
    responses: %{
      200 => {"Updated access grants list", "application/json", Schemas.AccessGrantListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice not found", "application/json", Schemas.ErrorResponse},
      422 => {"Invalid user_id", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Grants a user access to a restricted invoice."
  @spec grant_access(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def grant_access(conn, %{"id" => id, "user_id" => user_id}) when is_binary(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, _} ->
        company_id = conn.assigns.current_company.id
        granted_by_id = conn.assigns.api_token.created_by_id

        invoice =
          Invoices.get_invoice!(company_id, id,
            role: conn.assigns[:current_role],
            user_id: granted_by_id
          )

        case Invoices.grant_access(invoice.id, user_id, granted_by_id) do
          {:ok, _grant} ->
            grants = Invoices.list_access_grants(invoice.id)

            json(conn, %{
              data: %{
                access_restricted: invoice.access_restricted,
                grants: Enum.map(grants, &access_grant_json/1)
              }
            })

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to grant access"})
        end

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid user_id format"})
    end
  end

  def grant_access(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid or missing user_id"})
  end

  operation(:revoke_access,
    summary: "Revoke invoice access",
    description:
      "Revokes a user's access to a restricted invoice. Requires manage_team permission.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ],
      user_id: [
        in: :path,
        description: "UUID of the user whose access to revoke.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Updated access grants list", "application/json", Schemas.AccessGrantListResponse},
      401 =>
        {"Unauthorized — missing or invalid API token", "application/json", Schemas.ErrorResponse},
      403 => {"Forbidden — insufficient permissions", "application/json", Schemas.ErrorResponse},
      404 => {"Invoice or grant not found", "application/json", Schemas.ErrorResponse},
      422 =>
        {"Unprocessable Entity — invalid request parameters (e.g. invalid UUID)",
         "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Revokes a user's access to a restricted invoice."
  @spec revoke_access(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def revoke_access(conn, %{"id" => id, "user_id" => user_id}) do
    case Ecto.UUID.cast(user_id) do
      {:ok, _} ->
        company_id = conn.assigns.current_company.id

        invoice =
          Invoices.get_invoice!(company_id, id,
            role: conn.assigns[:current_role],
            user_id: conn.assigns.api_token.created_by_id
          )

        case Invoices.revoke_access(invoice.id, user_id) do
          {:ok, _} ->
            grants = Invoices.list_access_grants(invoice.id)

            json(conn, %{
              data: %{
                access_restricted: invoice.access_restricted,
                grants: Enum.map(grants, &access_grant_json/1)
              }
            })

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Access grant not found"})
        end

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid user_id format"})
    end
  end

  @spec access_grant_json(KsefHub.Invoices.InvoiceAccessGrant.t()) :: map()
  defp access_grant_json(grant) do
    %{
      id: grant.id,
      invoice_id: grant.invoice_id,
      user_id: grant.user_id,
      user_name: grant.user.name,
      user_email: grant.user.email,
      granted_by_id: grant.granted_by_id,
      inserted_at: grant.inserted_at
    }
  end

  # --- Private ---

  @spec cast_enum_param(String.t() | nil, module(), atom()) :: atom() | nil
  defp cast_enum_param(nil, _schema, _field), do: nil
  defp cast_enum_param("", _schema, _field), do: nil

  defp cast_enum_param(value, schema, field) when is_binary(value) do
    type = schema.__schema__(:type, field)

    case Ecto.Type.cast(type, value) do
      {:ok, atom} -> atom
      :error -> nil
    end
  end

  @spec build_filters(map()) :: map()
  defp build_filters(params) do
    %{}
    |> maybe_put(:type, cast_enum_param(params["type"], Invoice, :type))
    |> maybe_put(:status, cast_enum_param(params["status"], Invoice, :status))
    |> maybe_put(:source, cast_enum_param(params["source"], Invoice, :source))
    |> maybe_put(:seller_nip, params["seller_nip"])
    |> maybe_put(:buyer_nip, params["buyer_nip"])
    |> maybe_put(:query, params["query"])
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_date(:billing_date_from, params["billing_date_from"])
    |> maybe_put_date(:billing_date_to, params["billing_date_to"])
    |> maybe_put_integer(:page, params["page"])
    |> maybe_put_integer(:per_page, params["per_page"])
    |> maybe_put(:category_id, params["category_id"])
    |> maybe_put_list(:tag_ids, params["tag_ids[]"] || params["tag_ids"])
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

  @spec maybe_put_list(map(), atom(), list() | String.t() | nil) :: map()
  defp maybe_put_list(map, _key, nil), do: map
  defp maybe_put_list(map, _key, []), do: map
  defp maybe_put_list(map, key, values) when is_list(values), do: Map.put(map, key, values)
  defp maybe_put_list(map, key, value) when is_binary(value), do: Map.put(map, key, [value])
  defp maybe_put_list(map, _key, _invalid), do: map

  @spec validate_tag_ids(term()) :: {:ok, [String.t()]} | {:error, :invalid_tag_ids}
  defp validate_tag_ids(nil), do: {:ok, []}

  defp validate_tag_ids(ids) when is_list(ids) do
    if Enum.all?(ids, &valid_uuid?/1), do: {:ok, ids}, else: {:error, :invalid_tag_ids}
  end

  defp validate_tag_ids(_), do: {:error, :invalid_tag_ids}

  @spec render_tag_error(Plug.Conn.t(), Ecto.UUID.t(), term()) :: Plug.Conn.t()
  defp render_tag_error(conn, _id, {:error, :invalid_tag_ids}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid tag_ids payload"})
  end

  defp render_tag_error(conn, _id, false) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "One or more tags not found in this company"})
  end

  defp render_tag_error(conn, _id, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: changeset_errors(changeset)})
  end

  defp render_tag_error(conn, id, {:error, reason}) do
    Logger.warning("Tag operation failed for invoice #{id}: #{inspect(reason)}")

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Tag operation failed"})
  end

  @spec validate_category_company(String.t() | nil, Ecto.UUID.t()) ::
          :ok | {:error, :category_not_found | :invalid_uuid}
  defp validate_category_company(nil, _company_id), do: :ok

  defp validate_category_company(category_id, company_id) do
    if valid_uuid?(category_id) do
      case Invoices.get_category(company_id, category_id) do
        {:ok, _} -> :ok
        {:error, :not_found} -> {:error, :category_not_found}
      end
    else
      {:error, :invalid_uuid}
    end
  end

  @spec valid_uuid?(term()) :: boolean()
  defp valid_uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp valid_uuid?(_), do: false

  @spec cast_cost_line_param(map()) ::
          {:ok, atom() | nil | :not_provided} | {:error, :invalid_cost_line}
  defp cast_cost_line_param(%{"cost_line" => value}) do
    case CostLine.cast(value) do
      {:ok, cost_line} -> {:ok, cost_line}
      :error -> {:error, :invalid_cost_line}
    end
  end

  defp cast_cost_line_param(_params), do: {:ok, :not_provided}

  @spec maybe_set_api_cost_line(Invoice.t(), atom() | nil | :not_provided) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp maybe_set_api_cost_line(invoice, :not_provided), do: {:ok, invoice}

  defp maybe_set_api_cost_line(invoice, cost_line),
    do: Invoices.set_invoice_cost_line(invoice, cost_line)

  @spec validate_file_present(map()) :: {:ok, Plug.Upload.t()} | {:error, :missing_file}
  defp validate_file_present(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}

  defp validate_file_present(_params) do
    {:error, :missing_file}
  end

  @spec validate_type_present(map()) :: {:ok, String.t()} | {:error, :missing_type}
  defp validate_type_present(%{"type" => type}) when type in ~w(income expense), do: {:ok, type}
  defp validate_type_present(_params), do: {:error, :missing_type}

  @pdf_magic_bytes <<0x25, 0x50, 0x44, 0x46>>

  @spec validate_content_type(Plug.Upload.t()) :: :ok | {:error, :invalid_content_type}
  defp validate_content_type(%Plug.Upload{path: path}) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        header = IO.binread(io, 4)
        File.close(io)
        if header == @pdf_magic_bytes, do: :ok, else: {:error, :invalid_content_type}

      _ ->
        {:error, :invalid_content_type}
    end
  end

  @spec validate_file_size(Plug.Upload.t()) :: :ok | {:error, :file_too_large}
  defp validate_file_size(%Plug.Upload{path: path}) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @max_pdf_size -> :ok
      {:ok, _} -> {:error, :file_too_large}
      _ -> {:error, :file_too_large}
    end
  end

  @spec invoice_json(Invoice.t()) :: map()
  defp invoice_json(invoice) do
    base = %{
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
      gross_amount: invoice.gross_amount,
      currency: invoice.currency,
      status: invoice.status,
      source: invoice.source,
      category_id: invoice.category_id,
      duplicate_of_id: invoice.duplicate_of_id,
      duplicate_status: invoice.duplicate_status,
      ksef_acquisition_date: invoice.ksef_acquisition_date,
      permanent_storage_date: invoice.permanent_storage_date,
      prediction_status: invoice.prediction_status,
      prediction_category_name: invoice.prediction_category_name,
      prediction_tag_name: invoice.prediction_tag_name,
      prediction_category_confidence: invoice.prediction_category_confidence,
      prediction_tag_confidence: invoice.prediction_tag_confidence,
      prediction_model_version: invoice.prediction_model_version,
      prediction_predicted_at: invoice.prediction_predicted_at,
      extraction_status: invoice.extraction_status,
      original_filename: invoice.original_filename,
      purchase_order: invoice.purchase_order,
      sales_date: invoice.sales_date,
      due_date: invoice.due_date,
      billing_date_from: invoice.billing_date_from,
      billing_date_to: invoice.billing_date_to,
      iban: invoice.iban,
      seller_address: invoice.seller_address,
      buyer_address: invoice.buyer_address,
      cost_line: invoice.cost_line,
      project_tag: invoice.project_tag,
      access_restricted: invoice.access_restricted,
      inserted_at: invoice.inserted_at,
      updated_at: invoice.updated_at
    }

    base
    |> maybe_add_category(invoice)
    |> maybe_add_tags(invoice)
  end

  @spec maybe_add_category(map(), Invoice.t()) :: map()
  defp maybe_add_category(json, %{category: %Ecto.Association.NotLoaded{}}), do: json
  defp maybe_add_category(json, %{category: nil}), do: Map.put(json, :category, nil)

  defp maybe_add_category(json, %{category: category}),
    do: Map.put(json, :category, category_json(category))

  @spec maybe_add_tags(map(), Invoice.t()) :: map()
  defp maybe_add_tags(json, %{tags: %Ecto.Association.NotLoaded{}}), do: json
  defp maybe_add_tags(json, %{tags: tags}), do: Map.put(json, :tags, Enum.map(tags, &tag_json/1))
end
