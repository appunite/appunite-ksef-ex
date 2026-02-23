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
  alias KsefHub.Invoices.Invoice
  alias KsefHubWeb.Schemas
  alias OpenApiSpex.Schema

  @create_allowed_keys ~w(type ksef_number seller_nip seller_name buyer_nip buyer_name
    invoice_number issue_date net_amount vat_amount gross_amount currency)

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
      200 => {"Invoice list", "application/json", Schemas.InvoiceListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Lists invoices for the token's company with optional filters and pagination."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @doc "Creates a manual invoice, auto-detecting duplicates by ksef_number."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    company_id = conn.assigns.current_company.id

    case Invoices.create_manual_invoice(company_id, atomize_keys(params, @create_allowed_keys)) do
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

  @doc "Returns a single invoice by UUID with category and tags preloaded."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id

    invoice =
      Invoices.get_invoice_with_details!(company_id, id, role: conn.assigns[:current_role])

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

  @doc "Approves an expense invoice."
  @spec approve(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @doc "Rejects an expense invoice."
  @spec reject(Plug.Conn.t(), map()) :: Plug.Conn.t()
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

  @doc "Confirms a suspected duplicate invoice."
  @spec confirm_duplicate(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Not a duplicate", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Dismisses the duplicate flag on an invoice."
  @spec dismiss_duplicate(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"No XML content", "application/json", Schemas.ErrorResponse},
      500 => {"Generation failed", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Generates an HTML rendering of the invoice from its FA(3) XML."
  @spec html(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"No XML content", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Returns the raw FA(3) XML content of the invoice."
  @spec xml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def xml(conn, %{"id" => id}) do
    company_id = conn.assigns.current_company.id
    invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    if is_nil(invoice.xml_content) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invoice has no XML content"})
    else
      send_attachment(
        conn,
        "application/xml",
        "#{invoice.invoice_number}.xml",
        invoice.xml_content
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
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"No XML content", "application/json", Schemas.ErrorResponse},
      500 => {"Generation failed", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Generates a PDF rendering of the invoice from its FA(3) XML."
  @spec pdf(Plug.Conn.t(), map()) :: Plug.Conn.t()
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
      200 => {"Updated invoice", "application/json", Schemas.InvoiceResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Sets or clears the category on an invoice."
  @spec set_category(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_category(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id
    role = conn.assigns[:current_role]
    invoice = Invoices.get_invoice!(company_id, id, role: role)
    category_id = params["category_id"]

    with :ok <- validate_category_company(category_id, company_id),
         {:ok, _updated} <- Invoices.set_invoice_category(invoice, category_id) do
      invoice = Invoices.get_invoice_with_details!(company_id, id, role: role)
      json(conn, %{data: invoice_json(invoice)})
    else
      {:error, :invalid_uuid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid UUID format"})

      {:error, :category_not_found} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Category not found in this company"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:add_tags,
    summary: "Add tags to invoice",
    description: "Adds one or more tags to an invoice without removing existing tags.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Tags to add", "application/json", Schemas.InvoiceTagsRequest},
    responses: %{
      200 => {"Invoice tags", "application/json", Schemas.TagListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Adds tags to an invoice."
  @spec add_tags(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def add_tags(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id
    _invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    with {:ok, tag_ids} <- validate_tag_ids(params["tag_ids"]),
         true <- Invoices.tags_belong_to_company?(tag_ids, company_id) do
      Enum.each(tag_ids, fn tag_id -> Invoices.add_invoice_tag(id, tag_id) end)
      tags = Invoices.list_invoice_tags(id)
      json(conn, %{data: Enum.map(tags, &tag_json/1)})
    else
      {:error, :invalid_tag_ids} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid tag_ids payload"})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "One or more tags not found in this company"})
    end
  end

  operation(:set_tags,
    summary: "Set invoice tags",
    description: "Replaces all tags on an invoice with the given list.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    request_body: {"Tags to set", "application/json", Schemas.InvoiceTagsRequest},
    responses: %{
      200 => {"Invoice tags", "application/json", Schemas.TagListResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Replaces all tags on an invoice."
  @spec set_tags(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def set_tags(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_company.id
    _invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    with {:ok, tag_ids} <- validate_tag_ids(params["tag_ids"]),
         true <- Invoices.tags_belong_to_company?(tag_ids, company_id),
         {:ok, tags} <- Invoices.set_invoice_tags(id, tag_ids) do
      json(conn, %{data: Enum.map(tags, &tag_json/1)})
    else
      {:error, :invalid_tag_ids} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid tag_ids payload"})

      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "One or more tags not found in this company"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: changeset_errors(changeset)})
    end
  end

  operation(:remove_tag,
    summary: "Remove tag from invoice",
    description: "Removes a single tag from an invoice.",
    parameters: [
      id: [
        in: :path,
        description: "Invoice UUID.",
        schema: %Schema{type: :string, format: :uuid}
      ],
      tag_id: [
        in: :path,
        description: "Tag UUID to remove.",
        schema: %Schema{type: :string, format: :uuid}
      ]
    ],
    responses: %{
      200 => {"Tag removed", "application/json", Schemas.MessageResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      404 => {"Not found", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc "Removes a tag from an invoice."
  @spec remove_tag(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def remove_tag(conn, %{"id" => id, "tag_id" => tag_id}) do
    company_id = conn.assigns.current_company.id
    _invoice = Invoices.get_invoice!(company_id, id, role: conn.assigns[:current_role])

    if valid_uuid?(tag_id) do
      case Invoices.remove_invoice_tag(id, tag_id) do
        {:ok, _} ->
          json(conn, %{message: "Tag removed"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Tag not associated with this invoice"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "Invalid UUID format"})
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
      vat_amount: invoice.vat_amount,
      gross_amount: invoice.gross_amount,
      currency: invoice.currency,
      status: invoice.status,
      source: invoice.source,
      category_id: invoice.category_id,
      duplicate_of_id: invoice.duplicate_of_id,
      duplicate_status: invoice.duplicate_status,
      ksef_acquisition_date: invoice.ksef_acquisition_date,
      permanent_storage_date: invoice.permanent_storage_date,
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
