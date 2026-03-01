defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices from KSeF sync or manual entry.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Companies.{Company, Membership}
  alias KsefHub.Files
  alias KsefHub.InvoiceClassifier.Worker, as: ClassifierWorker
  alias KsefHub.InvoiceExtractor.ContextBuilder
  alias KsefHub.Invoices.{Category, Invoice, InvoiceTag, Tag}
  alias KsefHub.Repo

  @max_per_page 100
  @default_per_page 25
  @critical_extraction_fields ~w(seller_nip seller_name invoice_number issue_date net_amount gross_amount)a

  @doc """
  Returns a list of invoices for a company matching the given filters.

  Excludes `xml_content` from results for performance. Supports pagination
  via `:page` (1-based, default 1) and `:per_page` (default 25, max 100).

  ## Filters
    * `:type` - `:income` or `:expense`
    * `:status` - `:pending`, `:approved`, or `:rejected`
    * `:date_from` - earliest issue_date (inclusive)
    * `:date_to` - latest issue_date (inclusive)
    * `:seller_nip` - filter by seller NIP
    * `:buyer_nip` - filter by buyer NIP
    * `:source` - `:ksef`, `:manual`, or `:pdf_upload`
    * `:query` - search across invoice_number, seller_name, buyer_name
    * `:page` - page number (1-based, default 1)
    * `:per_page` - results per page (default 25, max 100)
  """
  @spec list_invoices(Ecto.UUID.t(), map(), keyword()) :: [Invoice.t()]
  def list_invoices(company_id, filters \\ %{}, opts \\ []) do
    filters = scope_by_role(filters, opts[:role])
    {page, per_page} = extract_pagination(filters)
    do_list_invoices(company_id, filters, page, per_page)
  end

  @doc """
  Returns the count of invoices for a company matching the given filters.

  Uses the same filter logic as `list_invoices/2` but returns only the count.
  """
  @spec count_invoices(Ecto.UUID.t(), map(), keyword()) :: non_neg_integer()
  def count_invoices(company_id, filters \\ %{}, opts \\ []) do
    filters = scope_by_role(filters, opts[:role])

    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  @doc """
  Returns a paginated result map with entries and metadata.

  ## Return value
    %{
      entries: [Invoice.t()],
      page: integer(),
      per_page: integer(),
      total_count: integer(),
      total_pages: integer()
    }
  """
  @spec list_invoices_paginated(Ecto.UUID.t(), map(), keyword()) :: %{
          entries: [Invoice.t()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }
  def list_invoices_paginated(company_id, filters \\ %{}, opts \\ []) do
    filters = scope_by_role(filters, opts[:role])
    {page, per_page} = extract_pagination(filters)

    entries =
      company_id
      |> do_list_invoices(filters, page, per_page)
      |> Repo.preload([:category, :tags])

    total_count = count_invoices(company_id, filters, opts)
    total_pages = max(ceil(total_count / per_page), 1)

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc "Fetches an invoice by UUID scoped to a company, raising if not found."
  @spec get_invoice!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def get_invoice!(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
    |> preload([:xml_file, :pdf_file])
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with category and tags preloaded."
  @spec get_invoice_with_details!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def get_invoice_with_details!(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
    |> preload([:xml_file, :pdf_file, :category, :tags])
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with category and tags preloaded, returning nil if not found."
  @spec get_invoice_with_details(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice_with_details(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
    |> preload([:xml_file, :pdf_file, :category, :tags])
    |> Repo.one()
  end

  @doc "Fetches an invoice by UUID scoped to a company, returning nil if not found."
  @spec get_invoice(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
    |> preload([:xml_file, :pdf_file])
    |> Repo.one()
  end

  @doc "Fetches an invoice by its KSeF reference number within a company (excludes duplicates)."
  @spec get_invoice_by_ksef_number(Ecto.UUID.t(), String.t()) :: Invoice.t() | nil
  def get_invoice_by_ksef_number(company_id, ksef_number) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.ksef_number == ^ksef_number)
    |> where([i], is_nil(i.duplicate_of_id))
    |> Repo.one()
  end

  @doc """
  Creates an invoice.
  """
  @spec create_invoice(map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_invoice(attrs) do
    company_id = attrs[:company_id] || attrs["company_id"]
    {pdf_content, attrs} = Map.pop(attrs, :pdf_content)
    {xml_content, attrs} = Map.pop(attrs, :xml_content)

    Repo.transaction(fn ->
      with {:ok, attrs} <- maybe_create_xml_file(attrs, xml_content),
           {:ok, attrs} <- maybe_create_pdf_file(attrs, pdf_content) do
        case %Invoice{}
             |> Ecto.Changeset.change(%{company_id: company_id})
             |> Invoice.changeset(attrs)
             |> Repo.insert() do
          {:ok, invoice} -> invoice
          {:error, changeset} -> Repo.rollback(changeset)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Upserts an invoice by (company_id, ksef_number). Used during sync to avoid duplicates.

  Returns `{:ok, invoice, :inserted}` for new invoices or `{:ok, invoice, :updated}`
  when an existing invoice was refreshed.
  """
  @spec upsert_invoice(map()) ::
          {:ok, Invoice.t(), :inserted | :updated} | {:error, Ecto.Changeset.t()}
  def upsert_invoice(attrs) do
    company_id = attrs[:company_id] || attrs["company_id"]

    case do_upsert(company_id, attrs) do
      {:ok, invoice} ->
        action = if invoice.inserted_at == invoice.updated_at, do: :inserted, else: :updated
        if action == :inserted, do: enqueue_prediction(invoice)
        {:ok, invoice, action}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @upsert_replace_fields [
    :source,
    :xml_file_id,
    :seller_nip,
    :seller_name,
    :buyer_nip,
    :buyer_name,
    :invoice_number,
    :issue_date,
    :net_amount,
    :vat_amount,
    :gross_amount,
    :currency,
    :ksef_acquisition_date,
    :permanent_storage_date,
    :extraction_status,
    :updated_at
  ]

  @spec do_upsert(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | term()}
  defp do_upsert(company_id, attrs) do
    {xml_content, attrs} = Map.pop(attrs, :xml_content)

    Repo.transaction(fn ->
      case maybe_create_xml_file(%{}, xml_content) do
        {:ok, file_attrs} ->
          attrs = Map.merge(attrs, file_attrs)

          case %Invoice{}
               |> Ecto.Changeset.change(%{company_id: company_id})
               |> Invoice.changeset(attrs)
               |> Repo.insert(
                 on_conflict: {:replace, @upsert_replace_fields},
                 conflict_target:
                   {:unsafe_fragment,
                    ~s|("company_id","ksef_number") WHERE ksef_number IS NOT NULL AND duplicate_of_id IS NULL|},
                 returning: true
               ) do
            {:ok, invoice} -> invoice
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an invoice.
  """
  @spec update_invoice(Invoice.t(), map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice(%Invoice{} = invoice, attrs) do
    invoice
    |> Invoice.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates invoice fields from a manual edit, recalculates extraction_status,
  and enqueues prediction if status changed from :partial or :failed to :complete.
  """
  @spec update_invoice_fields(Invoice.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice_fields(%Invoice{} = invoice, attrs) do
    old_status = invoice.extraction_status
    merged = invoice |> Map.from_struct() |> Map.merge(atomize_known_keys(attrs))
    new_status = determine_extraction_status_from_attrs(merged)

    changeset =
      invoice
      |> Invoice.edit_changeset(attrs)
      |> Ecto.Changeset.put_change(:extraction_status, new_status)

    with {:ok, updated} <- Repo.update(changeset) do
      if old_status in [:partial, :failed] and updated.extraction_status == :complete,
        do: enqueue_prediction(updated)

      {:ok, updated}
    end
  end

  @doc """
  Recalculates extraction status based on the presence of critical fields.

  Merges the given `attrs` over the invoice's current values, then checks
  whether all critical fields are present. Returns updated attrs with the
  new `:extraction_status` value.
  """
  @spec recalculate_extraction_status(Invoice.t(), map()) :: map()
  def recalculate_extraction_status(%Invoice{} = invoice, attrs) do
    merged = invoice |> Map.from_struct() |> Map.merge(atomize_known_keys(attrs))
    Map.put(attrs, :extraction_status, determine_extraction_status_from_attrs(merged))
  end

  @doc """
  Determines extraction status from a plain attrs map (no struct required).

  Used during KSeF sync to set extraction_status before upsert.
  Returns `:complete` if all critical fields are present, `:partial` otherwise.
  """
  @spec determine_extraction_status_from_attrs(map()) :: :complete | :partial
  def determine_extraction_status_from_attrs(attrs) do
    if all_critical_fields_present?(attrs), do: :complete, else: :partial
  end

  @spec atomize_known_keys(map()) :: map()
  defp atomize_known_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_binary(k) -> {safe_to_existing_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  @spec safe_to_existing_atom(String.t()) :: atom() | String.t()
  defp safe_to_existing_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> str
  end

  @doc """
  Approves an expense invoice.
  """
  @spec approve_invoice(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:invalid_type, Invoice.invoice_type()}}
          | {:error, :incomplete_extraction}
  def approve_invoice(%Invoice{type: :expense, extraction_status: status})
      when status in [:partial, :failed] do
    {:error, :incomplete_extraction}
  end

  def approve_invoice(%Invoice{type: :expense} = invoice) do
    update_invoice(invoice, %{status: :approved})
  end

  def approve_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Rejects an expense invoice.
  """
  @spec reject_invoice(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:invalid_type, Invoice.invoice_type()}}
  def reject_invoice(%Invoice{type: :expense} = invoice) do
    update_invoice(invoice, %{status: :rejected})
  end

  def reject_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Creates a manual invoice, optionally detecting duplicates by ksef_number.

  Forces `source: :manual` and strips KSeF-only fields. If a `ksef_number` is
  provided and an existing non-duplicate invoice with the same (company_id, ksef_number)
  exists, the new invoice is marked as a suspected duplicate.
  """
  @spec create_manual_invoice(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_manual_invoice(company_id, attrs) do
    attrs =
      attrs
      |> Map.drop([:ksef_acquisition_date, :permanent_storage_date])
      |> Map.drop(["ksef_acquisition_date", "permanent_storage_date"])
      |> Map.merge(%{source: :manual, company_id: company_id})

    case create_or_retry_duplicate(company_id, attrs) do
      {:ok, invoice} ->
        enqueue_prediction(invoice)
        {:ok, invoice}

      error ->
        error
    end
  end

  @spec create_or_retry_duplicate(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp create_or_retry_duplicate(company_id, attrs) do
    attrs = detect_duplicate(company_id, attrs)

    case create_invoice(attrs) do
      {:ok, invoice} ->
        {:ok, invoice}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ksef_number_conflict?(changeset),
          do: retry_as_duplicate(company_id, attrs),
          else: {:error, changeset}
    end
  end

  @spec retry_as_duplicate(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp retry_as_duplicate(company_id, attrs) do
    attrs
    |> Map.merge(%{
      duplicate_of_id: find_original_id(company_id, attrs),
      duplicate_status: :suspected
    })
    |> create_invoice()
  end

  @doc """
  Creates an invoice from an uploaded PDF via the InvoiceExtractor sidecar.

  Calls the extraction sidecar to parse the PDF, maps extracted fields to invoice
  attrs, determines extraction status based on which critical fields are present,
  and creates the invoice. Missing fields result in `extraction_status: :partial`
  rather than validation errors.

  Automatically builds a domain context string from the company to improve
  extraction accuracy.

  ## Parameters
    * `company` - the company struct (used for context building)
    * `pdf_binary` - raw PDF file content
    * `opts` - must include `:type` (`:income` or `:expense`), optionally `:filename`
  """
  @spec create_pdf_upload_invoice(Company.t(), binary(), map()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def create_pdf_upload_invoice(%Company{} = company, pdf_binary, opts) do
    type = opts[:type]
    filename = opts[:filename]
    context = ContextBuilder.build(company)

    extract_opts = [filename: filename || "invoice.pdf", context: context]

    case invoice_extractor().extract(pdf_binary, extract_opts) do
      {:ok, extracted} ->
        do_create_pdf_upload(company.id, pdf_binary, type, filename, extracted)

      {:error, _reason} ->
        Logger.warning("PDF extraction failed for file: #{filename || "invoice.pdf"}")
        do_create_pdf_upload_failed(company.id, pdf_binary, type, filename)
    end
  end

  @doc """
  Creates an expense invoice from an email attachment with pre-extracted fields.

  Accepts extraction results from the unstructured service or `:extraction_failed`
  when extraction could not be performed. Always sets `source: :email` and `type: :expense`.

  ## Parameters
    * `company_id` - the company UUID
    * `pdf_binary` - raw PDF file content
    * `extracted_or_failure` - extraction results map or `:extraction_failed`
    * `opts` - keyword list with optional `:filename`
  """
  @spec create_email_invoice(Ecto.UUID.t(), binary(), map() | :extraction_failed, keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def create_email_invoice(company_id, pdf_binary, :extraction_failed, opts) do
    do_create_pdf_failed(company_id, pdf_binary, :expense, opts[:filename], :email)
  end

  def create_email_invoice(company_id, pdf_binary, extracted, opts) when is_map(extracted) do
    do_create_pdf_extracted(company_id, pdf_binary, :expense, opts[:filename], extracted, :email)
  end

  @spec do_create_pdf_upload(Ecto.UUID.t(), binary(), atom(), String.t() | nil, map()) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_upload(company_id, pdf_binary, type, filename, extracted) do
    do_create_pdf_extracted(company_id, pdf_binary, type, filename, extracted, :pdf_upload)
  end

  @spec do_create_pdf_upload_failed(Ecto.UUID.t(), binary(), atom(), String.t() | nil) ::
          {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_upload_failed(company_id, pdf_binary, type, filename) do
    do_create_pdf_failed(company_id, pdf_binary, type, filename, :pdf_upload)
  end

  # Shared: create invoice from extracted fields with duplicate detection + prediction
  @spec do_create_pdf_extracted(
          Ecto.UUID.t(),
          binary(),
          atom(),
          String.t() | nil,
          map(),
          Invoice.invoice_source()
        ) :: {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_extracted(company_id, pdf_binary, type, filename, extracted, source) do
    extraction_status = determine_extraction_status(extracted)

    invoice_attrs =
      build_pdf_upload_attrs(extracted, company_id, pdf_binary, type, filename, extraction_status)
      |> Map.put(:source, source)

    case create_or_retry_duplicate(company_id, invoice_attrs) do
      {:ok, invoice} ->
        maybe_enqueue_prediction(extraction_status, invoice)
        {:ok, invoice}

      error ->
        error
    end
  end

  # Shared: create invoice when extraction failed
  @spec do_create_pdf_failed(
          Ecto.UUID.t(),
          binary(),
          atom(),
          String.t() | nil,
          Invoice.invoice_source()
        ) :: {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_failed(company_id, pdf_binary, type, filename, source) do
    attrs = %{
      source: source,
      type: type,
      company_id: company_id,
      pdf_content: pdf_binary,
      original_filename: filename,
      extraction_status: :failed
    }

    create_invoice(attrs)
  end

  @spec maybe_enqueue_prediction(atom(), Invoice.t()) :: :ok | :skip | :enqueue_failed
  defp maybe_enqueue_prediction(:complete, invoice), do: enqueue_prediction(invoice)
  defp maybe_enqueue_prediction(_status, _invoice), do: :ok

  @spec determine_extraction_status(map()) :: :complete | :partial
  defp determine_extraction_status(extracted),
    do: determine_extraction_status_from_attrs(extracted)

  @spec all_critical_fields_present?(map()) :: boolean()
  defp all_critical_fields_present?(map) do
    Enum.all?(@critical_extraction_fields, fn field ->
      value = Map.get(map, field) || Map.get(map, Atom.to_string(field))
      present_value?(value)
    end)
  end

  @spec present_value?(term()) :: boolean()
  defp present_value?(nil), do: false
  defp present_value?(s) when is_binary(s), do: String.trim(s) != ""
  defp present_value?(_), do: true

  @spec build_pdf_upload_attrs(
          map(),
          Ecto.UUID.t(),
          binary(),
          String.t(),
          String.t() | nil,
          atom()
        ) ::
          map()
  defp build_pdf_upload_attrs(
         extracted,
         company_id,
         pdf_binary,
         type,
         filename,
         extraction_status
       ) do
    %{
      source: :pdf_upload,
      type: type,
      company_id: company_id,
      pdf_content: pdf_binary,
      original_filename: filename,
      extraction_status: extraction_status,
      ksef_number: get_extracted_string(extracted, "ksef_number"),
      seller_nip: get_extracted_nip(extracted, "seller_nip"),
      seller_name: get_extracted_string(extracted, "seller_name"),
      buyer_nip: get_extracted_nip(extracted, "buyer_nip"),
      buyer_name: get_extracted_string(extracted, "buyer_name"),
      invoice_number: get_extracted_string(extracted, "invoice_number"),
      issue_date: get_extracted_date(extracted, "issue_date"),
      net_amount: get_extracted_decimal(extracted, "net_amount"),
      vat_amount: get_extracted_decimal(extracted, "vat_amount"),
      gross_amount: get_extracted_decimal(extracted, "gross_amount"),
      currency: get_extracted_string(extracted, "currency") || "PLN"
    }
  end

  @spec get_extracted_string(map(), String.t()) :: String.t() | nil
  defp get_extracted_string(data, key) do
    value = data[key]
    if is_binary(value) && value != "", do: value, else: nil
  end

  @spec get_extracted_nip(map(), String.t()) :: String.t() | nil
  defp get_extracted_nip(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> normalize_nip(value)
    end
  end

  # Strips PL prefix, dashes, spaces and validates 10-digit Polish NIP.
  # Returns the original value unchanged for foreign tax IDs (e.g. "DE123456789").
  @spec normalize_nip(String.t()) :: String.t()
  defp normalize_nip(value) do
    trimmed = String.trim(value)

    stripped =
      trimmed
      |> String.replace(~r/^PL/i, "")
      |> String.replace(~r/[\s\-]/, "")

    if Regex.match?(~r/^\d{10}$/, stripped), do: stripped, else: trimmed
  end

  @spec get_extracted_date(map(), String.t()) :: Date.t() | nil
  defp get_extracted_date(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> parse_date(value)
    end
  end

  @spec parse_date(String.t()) :: Date.t() | nil
  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  @spec get_extracted_decimal(map(), String.t()) :: Decimal.t() | nil
  defp get_extracted_decimal(data, key) do
    case data[key] do
      nil -> nil
      value when is_integer(value) -> Decimal.new(value)
      value when is_float(value) -> Decimal.from_float(value)
      value when is_binary(value) -> parse_decimal(value)
      _ -> nil
    end
  end

  @spec parse_decimal(String.t()) :: Decimal.t() | nil
  defp parse_decimal(value) do
    case value |> String.trim() |> Decimal.parse() do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  @spec maybe_create_xml_file(map(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  defp maybe_create_xml_file(attrs, nil), do: {:ok, attrs}

  defp maybe_create_xml_file(attrs, xml_content) do
    case Files.create_file(%{content: xml_content, content_type: "application/xml"}) do
      {:ok, file} -> {:ok, Map.put(attrs, :xml_file_id, file.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec maybe_create_pdf_file(map(), binary() | nil) :: {:ok, map()} | {:error, term()}
  defp maybe_create_pdf_file(attrs, nil), do: {:ok, attrs}

  defp maybe_create_pdf_file(attrs, pdf_content) do
    filename = attrs[:original_filename]

    case Files.create_file(%{
           content: pdf_content,
           content_type: "application/pdf",
           filename: filename
         }) do
      {:ok, file} -> {:ok, Map.put(attrs, :pdf_file_id, file.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec invoice_extractor() :: module()
  defp invoice_extractor do
    Application.get_env(:ksef_hub, :invoice_extractor, KsefHub.InvoiceExtractor.Client)
  end

  @doc """
  Confirms a suspected duplicate invoice.

  Only valid when `duplicate_of_id` is set and `duplicate_status` is `:suspected`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not `:suspected`.
  """
  @spec confirm_duplicate(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def confirm_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def confirm_duplicate(%Invoice{duplicate_status: :suspected} = invoice) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :confirmed})
    |> Repo.update()
  end

  def confirm_duplicate(%Invoice{}), do: {:error, :invalid_status}

  @doc """
  Dismisses a duplicate invoice.

  Valid when `duplicate_of_id` is set and `duplicate_status` is `:suspected` or `:confirmed`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not dismissable.
  """
  @spec dismiss_duplicate(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def dismiss_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def dismiss_duplicate(%Invoice{duplicate_status: status} = invoice)
      when status in [:suspected, :confirmed] do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :dismissed})
    |> Repo.update()
  end

  def dismiss_duplicate(%Invoice{}), do: {:error, :invalid_status}

  @doc """
  Returns invoice counts grouped by type and status for a company.
  """
  @spec count_by_type_and_status(Ecto.UUID.t()) :: %{
          {Invoice.invoice_type(), Invoice.invoice_status()} => non_neg_integer()
        }
  def count_by_type_and_status(company_id) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> group_by([i], [i.type, i.status])
    |> select([i], {i.type, i.status, count(i.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {type, status, count}, acc ->
      Map.put(acc, {type, status}, count)
    end)
  end

  # --- Categories ---

  @doc "Returns all categories for a company, ordered by sort_order then name."
  @spec list_categories(Ecto.UUID.t()) :: [Category.t()]
  def list_categories(company_id) do
    Category
    |> where([c], c.company_id == ^company_id)
    |> order_by([c], asc: c.sort_order, asc: c.name)
    |> Repo.all()
  end

  @doc "Fetches a category by ID scoped to a company."
  @spec get_category(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Category.t()} | {:error, :not_found}
  def get_category(company_id, id) do
    company_id
    |> category_query(id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      category -> {:ok, category}
    end
  end

  @doc "Fetches a category by ID scoped to a company, raising if not found."
  @spec get_category!(Ecto.UUID.t(), Ecto.UUID.t()) :: Category.t()
  def get_category!(company_id, id) do
    company_id |> category_query(id) |> Repo.one!()
  end

  @doc "Creates a category for a company."
  @spec create_category(Ecto.UUID.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create_category(company_id, attrs) do
    %Category{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a category."
  @spec update_category(Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a category. Associated invoices get category_id nilified."
  @spec delete_category(Category.t()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  # --- Tags ---

  @doc "Returns all tags for a company with usage counts, ordered by count desc then name."
  @spec list_tags(Ecto.UUID.t()) :: [Tag.t()]
  def list_tags(company_id) do
    Tag
    |> where([t], t.company_id == ^company_id)
    |> join(:left, [t], it in InvoiceTag, on: it.tag_id == t.id)
    |> group_by([t, _it], t.id)
    |> select_merge([t, it], %{usage_count: count(it.id)})
    |> order_by([t, it], desc: count(it.id), asc: t.name)
    |> Repo.all()
  end

  @doc "Fetches a tag by ID scoped to a company, with usage count from invoice_tags join."
  @spec get_tag_with_usage_count(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Tag.t()} | {:error, :not_found}
  def get_tag_with_usage_count(company_id, id) do
    Tag
    |> where([t], t.company_id == ^company_id and t.id == ^id)
    |> join(:left, [t], it in InvoiceTag, on: it.tag_id == t.id)
    |> group_by([t, _it], t.id)
    |> select_merge([t, it], %{usage_count: count(it.id)})
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc "Fetches a tag by ID scoped to a company."
  @spec get_tag(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Tag.t()} | {:error, :not_found}
  def get_tag(company_id, id) do
    company_id
    |> tag_query(id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      tag -> {:ok, tag}
    end
  end

  @doc "Fetches a tag by ID scoped to a company, raising if not found."
  @spec get_tag!(Ecto.UUID.t(), Ecto.UUID.t()) :: Tag.t()
  def get_tag!(company_id, id) do
    company_id |> tag_query(id) |> Repo.one!()
  end

  @doc "Creates a tag for a company."
  @spec create_tag(Ecto.UUID.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def create_tag(company_id, attrs) do
    %Tag{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a tag."
  @spec update_tag(Tag.t(), map()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc "Deletes a tag. Associated join records are cascade deleted."
  @spec delete_tag(Tag.t()) :: {:ok, Tag.t()} | {:error, Ecto.Changeset.t()}
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  @doc "Checks whether all given tag IDs belong to a company."
  @spec tags_belong_to_company?([Ecto.UUID.t()], Ecto.UUID.t()) :: boolean()
  def tags_belong_to_company?([], _company_id), do: true

  def tags_belong_to_company?(tag_ids, company_id) do
    count =
      Tag
      |> where([t], t.company_id == ^company_id and t.id in ^tag_ids)
      |> Repo.aggregate(:count)

    count == length(Enum.uniq(tag_ids))
  end

  # --- Invoice-Category Assignment ---

  @doc """
  Assigns or clears a category on an invoice.

  When `category_id` is not nil, verifies the category belongs to the same
  company as the invoice before updating.
  """
  @spec set_invoice_category(Invoice.t(), Ecto.UUID.t() | nil) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :category_not_in_company}
  def set_invoice_category(%Invoice{} = invoice, nil) do
    invoice
    |> Invoice.category_changeset(%{category_id: nil})
    |> Repo.update()
  end

  def set_invoice_category(%Invoice{} = invoice, category_id) do
    category_exists? =
      Category
      |> where([c], c.id == ^category_id and c.company_id == ^invoice.company_id)
      |> Repo.exists?()

    if category_exists? do
      invoice
      |> Invoice.category_changeset(%{category_id: category_id})
      |> Repo.update()
    else
      {:error, :category_not_in_company}
    end
  end

  @doc """
  Marks an invoice's prediction status as `:manual`, indicating the user
  overrode or manually set the category/tags.
  """
  @spec mark_prediction_manual(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def mark_prediction_manual(%Invoice{} = invoice) do
    invoice
    |> Invoice.prediction_changeset(%{prediction_status: :manual})
    |> Repo.update()
  end

  # --- Invoice-Tag Associations ---

  @doc """
  Adds a tag to an invoice. Idempotent — duplicate associations are silently ignored.

  Verifies the tag belongs to the same company as the invoice before inserting.
  """
  @spec add_invoice_tag(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, InvoiceTag.t()} | {:error, Ecto.Changeset.t() | :tag_not_in_company}
  def add_invoice_tag(invoice_id, tag_id) do
    company_id =
      Invoice
      |> where([i], i.id == ^invoice_id)
      |> select([i], i.company_id)
      |> Repo.one!()

    add_invoice_tag(invoice_id, tag_id, company_id)
  end

  @doc """
  Adds a tag to an invoice with a known company_id, skipping the per-tag
  company lookup. Use when company ownership is already validated by the caller.
  """
  @spec add_invoice_tag(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, InvoiceTag.t()} | {:error, Ecto.Changeset.t() | :tag_not_in_company}
  def add_invoice_tag(invoice_id, tag_id, company_id) do
    tag_in_company? =
      Tag
      |> where([t], t.id == ^tag_id and t.company_id == ^company_id)
      |> Repo.exists?()

    if tag_in_company? do
      invoice_id
      |> InvoiceTag.changeset(tag_id)
      |> Repo.insert(on_conflict: :nothing)
    else
      {:error, :tag_not_in_company}
    end
  end

  @doc """
  Creates a tag and adds it to an invoice in a single transaction.

  Both the tag creation and the invoice association succeed or both roll back.
  """
  @spec create_and_add_tag(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Tag.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_and_add_tag(invoice_id, company_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, tag} <- create_tag(company_id, attrs),
           {:ok, _it} <- add_invoice_tag(invoice_id, tag.id, company_id) do
        tag
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Removes a tag from an invoice."
  @spec remove_invoice_tag(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, InvoiceTag.t()} | {:error, :not_found}
  def remove_invoice_tag(invoice_id, tag_id) do
    InvoiceTag
    |> where([it], it.invoice_id == ^invoice_id and it.tag_id == ^tag_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      invoice_tag -> Repo.delete(invoice_tag)
    end
  end

  @doc "Lists tags for an invoice, ordered by name."
  @spec list_invoice_tags(Ecto.UUID.t()) :: [Tag.t()]
  def list_invoice_tags(invoice_id) do
    Tag
    |> join(:inner, [t], it in InvoiceTag, on: it.tag_id == t.id)
    |> where([_t, it], it.invoice_id == ^invoice_id)
    |> order_by([t, _it], asc: t.name)
    |> Repo.all()
  end

  @doc "Replaces all tags on an invoice with the given tag IDs."
  @spec set_invoice_tags(Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, [Tag.t()]} | {:error, Ecto.Changeset.t()}
  def set_invoice_tags(invoice_id, tag_ids) do
    unique_tag_ids = Enum.uniq(tag_ids)

    Repo.transaction(fn ->
      InvoiceTag
      |> where([it], it.invoice_id == ^invoice_id)
      |> Repo.delete_all()

      Enum.each(unique_tag_ids, &insert_invoice_tag!(invoice_id, &1))
      list_invoice_tags(invoice_id)
    end)
  end

  @spec insert_invoice_tag!(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  defp insert_invoice_tag!(invoice_id, tag_id) do
    case invoice_id |> InvoiceTag.changeset(tag_id) |> Repo.insert() do
      {:ok, _} -> :ok
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  # --- Private ---

  @spec detect_duplicate(Ecto.UUID.t(), map()) :: map()
  defp detect_duplicate(company_id, attrs) do
    case find_original_id(company_id, attrs) do
      nil ->
        attrs

      original_id ->
        Map.merge(attrs, %{duplicate_of_id: original_id, duplicate_status: :suspected})
    end
  end

  @spec find_original_id(Ecto.UUID.t(), map()) :: Ecto.UUID.t() | nil
  defp find_original_id(company_id, attrs) do
    ksef_number = attrs[:ksef_number] || attrs["ksef_number"]

    if ksef_number && ksef_number != "" do
      Invoice
      |> where([i], i.company_id == ^company_id and i.ksef_number == ^ksef_number)
      |> where([i], is_nil(i.duplicate_of_id))
      |> select([i], i.id)
      |> Repo.one()
    else
      nil
    end
  end

  @spec unique_ksef_number_conflict?(Ecto.Changeset.t()) :: boolean()
  defp unique_ksef_number_conflict?(changeset) do
    Enum.any?(changeset.errors, fn
      {:company_id, {_, [constraint: :unique, constraint_name: name]}} ->
        name == "invoices_company_id_ksef_number_unique_non_duplicate"

      _ ->
        false
    end)
  end

  @spec scope_by_role(map(), Membership.role() | nil) :: map()
  defp scope_by_role(filters, :reviewer), do: Map.put(filters, :type, :expense)
  defp scope_by_role(filters, _role), do: filters

  @spec maybe_scope_type_by_role(Ecto.Queryable.t(), Membership.role() | nil) :: Ecto.Query.t()
  defp maybe_scope_type_by_role(query, :reviewer), do: where(query, [i], i.type == :expense)
  defp maybe_scope_type_by_role(query, _role), do: query

  @spec do_list_invoices(Ecto.UUID.t(), map(), pos_integer(), pos_integer()) :: [Invoice.t()]
  defp do_list_invoices(company_id, filters, page, per_page) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> order_by([i], desc: i.issue_date, desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Query.t()
  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:type, type}, q when type in [:income, :expense] ->
        where(q, [i], i.type == ^type)

      {:status, status}, q when status in [:pending, :approved, :rejected] ->
        where(q, [i], i.status == ^status)

      {:date_from, %Date{} = date}, q ->
        where(q, [i], i.issue_date >= ^date)

      {:date_to, %Date{} = date}, q ->
        where(q, [i], i.issue_date <= ^date)

      {:seller_nip, nip}, q when is_binary(nip) and nip != "" ->
        where(q, [i], i.seller_nip == ^nip)

      {:buyer_nip, nip}, q when is_binary(nip) and nip != "" ->
        where(q, [i], i.buyer_nip == ^nip)

      {:query, search}, q when is_binary(search) and search != "" ->
        escaped =
          search
          |> String.replace("\\", "\\\\")
          |> String.replace("%", "\\%")
          |> String.replace("_", "\\_")

        pattern = "%" <> escaped <> "%"

        where(
          q,
          [i],
          fragment("? ILIKE ? ESCAPE '\\'", i.invoice_number, ^pattern) or
            fragment("? ILIKE ? ESCAPE '\\'", i.seller_name, ^pattern) or
            fragment("? ILIKE ? ESCAPE '\\'", i.buyer_name, ^pattern)
        )

      {:source, source}, q when source in [:ksef, :manual, :pdf_upload, :email] ->
        where(q, [i], i.source == ^source)

      {:category_id, category_id}, q when is_binary(category_id) and category_id != "" ->
        where(q, [i], i.category_id == ^category_id)

      {:tag_ids, tag_ids}, q when is_list(tag_ids) and tag_ids != [] ->
        q
        |> join(:inner, [i], it in InvoiceTag, on: it.invoice_id == i.id)
        |> where([..., it], it.tag_id in ^tag_ids)
        |> distinct(true)

      _, q ->
        q
    end)
  end

  @spec extract_pagination(map()) :: {pos_integer(), pos_integer()}
  defp extract_pagination(filters) do
    page = filters |> Map.get(:page, 1) |> clamp(1, 1_000_000)
    per_page = filters |> Map.get(:per_page, @default_per_page) |> clamp(1, @max_per_page)
    {page, per_page}
  end

  @spec clamp(term(), integer(), integer()) :: integer()
  defp clamp(value, min_val, max_val) when is_integer(value) do
    value |> max(min_val) |> min(max_val)
  end

  defp clamp(_, min_val, _max_val), do: min_val

  @spec category_query(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  defp category_query(company_id, id) do
    where(Category, [c], c.company_id == ^company_id and c.id == ^id)
  end

  @spec tag_query(Ecto.UUID.t(), Ecto.UUID.t()) :: Ecto.Query.t()
  defp tag_query(company_id, id) do
    where(Tag, [t], t.company_id == ^company_id and t.id == ^id)
  end

  @spec enqueue_prediction(Invoice.t()) :: :ok | :skip | :enqueue_failed
  defp enqueue_prediction(invoice) do
    case ClassifierWorker.maybe_enqueue(invoice) do
      {:ok, _job} ->
        :ok

      :skip ->
        :skip

      {:error, reason} ->
        Logger.warning(
          "Failed to enqueue prediction for invoice #{invoice.id}: #{inspect(reason)}"
        )

        :enqueue_failed
    end
  end
end
