defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices from KSeF sync or manual entry.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Accounts.User
  alias KsefHub.Authorization
  alias KsefHub.Companies
  alias KsefHub.Companies.{Company, Membership}
  alias KsefHub.Files
  alias KsefHub.InvoiceClassifier.Worker, as: ClassifierWorker
  alias KsefHub.InvoiceExtractor.ContextBuilder

  alias KsefHub.ActivityLog.Events
  alias KsefHub.ActivityLog.TrackedRepo

  alias KsefHub.Invoices.{
    AutoApproval,
    Category,
    DuplicateDetector,
    Invoice,
    InvoiceAccessGrant,
    InvoiceComment,
    NipVerifier,
    Parser,
    PurchaseOrder
  }

  alias KsefHub.Repo

  @max_per_page 100
  @default_per_page 25
  @critical_extraction_fields ~w(seller_nip seller_name invoice_number issue_date net_amount gross_amount)a

  @extraction_placeholders KsefHub.InvoiceExtractor.Placeholders.values()

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
    * `:query` - search across invoice_number, seller_name, buyer_name, purchase_order, iban
    * `:billing_date_from` - filter invoices whose billing range overlaps on or after this date
    * `:billing_date_to` - filter invoices whose billing range overlaps on or before this date
    * `:page` - page number (1-based, default 1)
    * `:per_page` - results per page (default 25, max 100)
  """
  @spec list_invoices(Ecto.UUID.t(), map(), keyword()) :: [Invoice.t()]
  def list_invoices(company_id, filters \\ %{}, opts \\ []) do
    {page, per_page} = extract_pagination(filters)
    do_list_invoices(company_id, filters, page, per_page, opts)
  end

  @doc """
  Returns the count of invoices for a company matching the given filters.

  Uses the same filter logic as `list_invoices/2` but returns only the count.
  """
  @spec count_invoices(Ecto.UUID.t(), map(), keyword()) :: non_neg_integer()
  def count_invoices(company_id, filters \\ %{}, opts \\ []) do
    do_count_invoices(company_id, filters, opts)
  end

  @spec do_count_invoices(Ecto.UUID.t(), map(), keyword()) :: non_neg_integer()
  defp do_count_invoices(company_id, filters, opts) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> maybe_filter_by_access(opts)
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
    {page, per_page} = extract_pagination(filters)

    entries =
      company_id
      |> do_list_invoices(filters, page, per_page, opts)
      |> Repo.preload([:category])

    total_count = do_count_invoices(company_id, filters, opts)
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
    |> maybe_filter_by_access(opts)
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with associations preloaded."
  @spec get_invoice_with_details!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def get_invoice_with_details!(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_filter_by_access(opts)
    |> preload([:xml_file, :pdf_file, :category, :created_by, :inbound_email])
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with associations preloaded, returning nil if not found."
  @spec get_invoice_with_details(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice_with_details(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_filter_by_access(opts)
    |> preload([:xml_file, :pdf_file, :category, :created_by, :inbound_email])
    |> Repo.one()
  end

  @doc "Fetches an invoice by UUID scoped to a company, returning nil if not found."
  @spec get_invoice(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_filter_by_access(opts)
    |> Repo.one()
  end

  @doc "Fetches an invoice by its public sharing token, with details preloaded. Returns nil if not found or token is invalid."
  @spec get_invoice_by_public_token(String.t()) :: Invoice.t() | nil
  def get_invoice_by_public_token(token) when is_binary(token) and byte_size(token) in 20..100 do
    Invoice
    |> where([i], i.public_token == ^token)
    |> preload([:company, :xml_file, :pdf_file, :category])
    |> Repo.one()
  end

  def get_invoice_by_public_token(_), do: nil

  @doc """
  Atomically generates a public sharing token for an invoice.

  Uses `WHERE public_token IS NULL` so only the first write wins — concurrent
  calls won't rotate an existing token. Returns `{:ok, invoice}` with the token
  on success, or `{:error, :already_has_token}` if one already exists.
  """
  @spec generate_public_token(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, :already_has_token | Ecto.Changeset.t()}
  def generate_public_token(%Invoice{} = invoice) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    {count, _} =
      Invoice
      |> where([i], i.id == ^invoice.id and is_nil(i.public_token))
      |> Repo.update_all(set: [public_token: token])

    case count do
      1 -> {:ok, %{invoice | public_token: token}}
      0 -> {:error, :already_has_token}
    end
  end

  @doc """
  Ensures an invoice has a public token, generating one if absent. Idempotent.

  Uses an atomic DB update so concurrent callers cannot race: only the first
  write sets the token, subsequent calls reload and return the existing one.
  """
  @spec ensure_public_token(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def ensure_public_token(%Invoice{public_token: token} = invoice) when is_binary(token) do
    {:ok, invoice}
  end

  def ensure_public_token(%Invoice{} = invoice) do
    case generate_public_token(invoice) do
      {:ok, _} = ok -> ok
      {:error, :already_has_token} -> {:ok, Repo.reload!(invoice)}
    end
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
  Computes a default billing_date from the given attrs map.

  Returns the first day of the month of `sales_date` (falling back to
  `issue_date`), or `nil` if neither is present.
  """
  @spec compute_billing_date(map()) :: Date.t() | nil
  def compute_billing_date(attrs) do
    date = get_attr(attrs, :sales_date) || get_attr(attrs, :issue_date)
    first_of_month(date)
  end

  @spec first_of_month(term()) :: Date.t() | nil
  defp first_of_month(%Date{year: y, month: m}), do: Date.new!(y, m, 1)

  defp first_of_month(str) when is_binary(str) do
    case Date.from_iso8601(str) do
      {:ok, date} ->
        first_of_month(date)

      _ ->
        case DateTime.from_iso8601(str) do
          {:ok, dt, _} -> first_of_month(DateTime.to_date(dt))
          _ -> nil
        end
    end
  end

  defp first_of_month(_), do: nil

  @spec has_attr?(map(), atom()) :: boolean()
  defp has_attr?(attrs, key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key))
  end

  @spec get_attr(map(), atom()) :: term()
  defp get_attr(attrs, key) do
    attrs[key] || attrs[Atom.to_string(key)]
  end

  @spec maybe_restrict_access(map()) :: map()
  defp maybe_restrict_access(attrs) do
    type = attrs[:type] || attrs["type"]
    purchase_order = attrs[:purchase_order] || attrs["purchase_order"]

    cond do
      type in [:income, "income"] -> Map.put(attrs, :access_restricted, true)
      purchase_order not in [nil, ""] -> Map.put(attrs, :access_restricted, true)
      true -> attrs
    end
  end

  @spec maybe_default_billing_date(map()) :: map()
  defp maybe_default_billing_date(attrs) do
    if has_attr?(attrs, :billing_date_from) or has_attr?(attrs, :billing_date_to) do
      attrs
    else
      case compute_billing_date(attrs) do
        nil -> attrs
        date -> attrs |> Map.put(:billing_date_from, date) |> Map.put(:billing_date_to, date)
      end
    end
  end

  # Like maybe_default_billing_date/1, but for updates — only fills in billing dates
  # when the existing invoice doesn't already have them set (preserves manual edits).
  @spec maybe_default_billing_date_for_update(map(), Invoice.t()) :: map()
  defp maybe_default_billing_date_for_update(attrs, %Invoice{} = invoice) do
    if is_nil(invoice.billing_date_from) and is_nil(invoice.billing_date_to) do
      maybe_default_billing_date(attrs)
    else
      attrs
    end
  end

  @doc """
  Creates an invoice.
  """
  @spec create_invoice(map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_invoice(attrs, opts \\ []) do
    company_id = attrs[:company_id] || attrs["company_id"]
    {pdf_content, attrs} = Map.pop(attrs, :pdf_content)
    {xml_content, attrs} = Map.pop(attrs, :xml_content)
    attrs = attrs |> maybe_default_billing_date() |> maybe_restrict_access()

    Repo.transaction(fn ->
      with {:ok, attrs} <- maybe_create_xml_file(attrs, xml_content),
           {:ok, attrs} <- maybe_create_pdf_file(attrs, pdf_content),
           {:ok, invoice} <- do_insert_invoice(company_id, attrs, opts) do
        invoice
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
    attrs = attrs |> maybe_default_billing_date() |> maybe_restrict_access()

    case do_upsert(company_id, attrs) do
      {:ok, invoice} ->
        action = if invoice.inserted_at == invoice.updated_at, do: :inserted, else: :updated
        if action == :inserted, do: enqueue_prediction(invoice)
        invoice = maybe_mark_business_field_duplicate(invoice, action)
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
    :gross_amount,
    :currency,
    :ksef_acquisition_date,
    :ksef_permanent_storage_date,
    :extraction_status,
    :purchase_order,
    :sales_date,
    :due_date,
    :billing_date_from,
    :billing_date_to,
    :iban,
    :seller_address,
    :buyer_address,
    :updated_at
  ]

  @spec do_upsert(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | term()}
  defp do_upsert(company_id, attrs) do
    {xml_content, attrs} = Map.pop(attrs, :xml_content)

    Repo.transaction(fn ->
      with {:ok, file_attrs} <- maybe_create_xml_file(%{}, xml_content),
           attrs = Map.merge(attrs, file_attrs),
           {:ok, invoice} <- do_upsert_invoice(company_id, attrs) do
        invoice
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an invoice.
  """
  @spec update_invoice(Invoice.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice(%Invoice{} = invoice, attrs, opts \\ []) do
    invoice
    |> Invoice.changeset(attrs)
    |> TrackedRepo.update(opts)
  end

  @doc """
  Dismisses the extraction warning by marking extraction_status as :complete.

  Used when the user has reviewed the invoice and confirmed the data is
  acceptable despite missing fields (e.g. foreign seller with no NIP).
  Enqueues prediction if not already done.
  """
  @spec dismiss_extraction_warning(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def dismiss_extraction_warning(invoice, opts \\ [])

  def dismiss_extraction_warning(%Invoice{extraction_status: :complete} = invoice, _opts),
    do: {:ok, invoice}

  def dismiss_extraction_warning(%Invoice{} = invoice, opts) do
    with {:ok, updated} <-
           invoice
           |> Ecto.Changeset.change(extraction_status: :complete)
           |> Repo.update() do
      Events.invoice_extraction_dismissed(updated, opts)
      maybe_enqueue_prediction(:complete, updated)
      {:ok, updated}
    end
  end

  @doc """
  Updates invoice fields from a manual edit, recalculates extraction_status
  (when the invoice has one), and enqueues prediction if status changed from
  :partial or :failed to :complete.
  """
  @spec update_invoice_fields(Invoice.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :ksef_not_editable}
  def update_invoice_fields(%Invoice{} = invoice, attrs, opts \\ []) do
    Repo.transaction(fn ->
      fresh_invoice =
        Invoice
        |> where(id: ^invoice.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      unless Invoice.data_editable?(fresh_invoice), do: Repo.rollback(:ksef_not_editable)

      case do_update_invoice_fields(fresh_invoice, attrs, opts) do
        {:ok, updated} -> updated
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @spec do_update_invoice_fields(Invoice.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_update_invoice_fields(%Invoice{} = invoice, attrs, opts) do
    old_status = invoice.extraction_status

    # Only consider fields that edit_changeset will actually apply (excludes company-side fields)
    allowed_attrs =
      attrs
      |> atomize_known_keys()
      |> Map.take(Invoice.editable_fields(invoice.type))

    changeset = Invoice.edit_changeset(invoice, attrs)

    changeset =
      if old_status do
        critical_changed? =
          Enum.any?(@critical_extraction_fields, &Map.has_key?(changeset.changes, &1))

        if critical_changed? do
          merged = invoice |> Map.from_struct() |> Map.merge(allowed_attrs)
          new_status = determine_extraction_status_from_attrs(merged)
          Ecto.Changeset.put_change(changeset, :extraction_status, new_status)
        else
          changeset
        end
      else
        changeset
      end

    changeset = maybe_backfill_billing_date(changeset, invoice)

    with {:ok, updated} <- TrackedRepo.update(changeset, opts) do
      if old_status in [:partial, :failed] and updated.extraction_status == :complete,
        do: enqueue_prediction(updated)

      {:ok, updated}
    end
  end

  # When issue_date or sales_date changes and billing dates are still nil,
  # backfill them from the new date.
  @spec maybe_backfill_billing_date(Ecto.Changeset.t(), Invoice.t()) :: Ecto.Changeset.t()
  defp maybe_backfill_billing_date(changeset, invoice) do
    date_changed? =
      Map.has_key?(changeset.changes, :issue_date) or
        Map.has_key?(changeset.changes, :sales_date)

    billing_missing? = is_nil(invoice.billing_date_from) and is_nil(invoice.billing_date_to)

    if date_changed? and billing_missing? do
      merged = invoice |> Map.from_struct() |> Map.merge(changeset.changes)

      case compute_billing_date(merged) do
        nil ->
          changeset

        date ->
          changeset
          |> Ecto.Changeset.put_change(:billing_date_from, date)
          |> Ecto.Changeset.put_change(:billing_date_to, date)
      end
    else
      changeset
    end
  end

  @doc """
  Re-parses an invoice from its stored FA(3) XML file.

  Loads the XML from the files table, runs it through `Parser.parse/1`, and
  updates the invoice with the freshly parsed fields. Only works for invoices
  that have a stored XML file (source: :ksef).

  Useful when the parser is improved (e.g. new field extraction) and existing
  invoices need to pick up the changes without a full KSeF re-sync.

  Returns `{:ok, updated_invoice}` on success, `{:error, reason}` on failure.
  """
  @spec reparse_from_stored_xml(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def reparse_from_stored_xml(%Invoice{} = invoice, opts \\ []) do
    with {:ok, xml_content} <- load_xml_content(invoice),
         {:ok, parsed} <- Parser.parse(xml_content) do
      attrs =
        parsed
        |> Map.drop([:line_items])
        |> Map.put(:type, invoice.type)
        |> Map.put(:currency, parsed[:currency] || invoice.currency || "PLN")
        |> maybe_default_billing_date_for_update(invoice)

      attrs = recalculate_extraction_status(invoice, attrs)

      update_invoice(invoice, attrs, opts)
    end
  end

  @spec load_xml_content(Invoice.t()) :: {:ok, binary()} | {:error, :no_xml}
  defp load_xml_content(%Invoice{xml_file: %{content: content}}) when is_binary(content),
    do: {:ok, content}

  defp load_xml_content(%Invoice{xml_file_id: xml_file_id}) when not is_nil(xml_file_id) do
    case Files.get_file(xml_file_id) do
      %{content: content} when is_binary(content) -> {:ok, content}
      _ -> {:error, :no_xml}
    end
  end

  defp load_xml_content(_invoice), do: {:error, :no_xml}

  @doc """
  Re-extracts data from an invoice's stored PDF file.

  Calls the extraction sidecar to re-parse the PDF, then updates the invoice
  with the newly extracted fields. Only works for invoices that have a stored
  PDF file (source: :pdf_upload or :email).

  Returns `{:ok, updated_invoice}` on success, `{:error, reason}` on failure.
  """
  @spec re_extract_invoice(Invoice.t(), Company.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def re_extract_invoice(%Invoice{} = invoice, %Company{} = company, opts \\ []) do
    with {:ok, pdf_binary} <- load_pdf_content(invoice),
         {:ok, extracted} <- do_re_extract(company, invoice, pdf_binary),
         :ok <- verify_nip_for_type(extracted, company.nip, invoice.type) do
      apply_extraction_results(invoice, extracted, company, opts)
    end
  end

  @spec load_pdf_content(Invoice.t()) :: {:ok, binary()} | {:error, :no_pdf}
  defp load_pdf_content(%Invoice{pdf_file: %{content: content}}) when is_binary(content),
    do: {:ok, content}

  defp load_pdf_content(%Invoice{pdf_file_id: pdf_file_id}) when not is_nil(pdf_file_id) do
    case Files.get_file(pdf_file_id) do
      %{content: content} when is_binary(content) -> {:ok, content}
      _ -> {:error, :no_pdf}
    end
  end

  defp load_pdf_content(_invoice), do: {:error, :no_pdf}

  @spec do_re_extract(Company.t(), Invoice.t(), binary()) ::
          {:ok, map()} | {:error, term()}
  defp do_re_extract(company, invoice, pdf_binary) do
    context = ContextBuilder.build(company, invoice.type)
    filename = invoice.original_filename || "invoice.pdf"
    invoice_extractor().extract(pdf_binary, filename: filename, context: context)
  end

  @spec apply_extraction_results(Invoice.t(), map(), Company.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp apply_extraction_results(invoice, extracted, company, opts) do
    extracted_attrs = extracted_to_invoice_attrs(extracted)

    # When bank_iban was present but rejected as non-IBAN (e.g. short local
    # account number), we must explicitly clear the iban field so a stale
    # value from a previous extraction doesn't persist.
    # However, values that look like truncated IBANs (start with a country
    # prefix like "PL") should NOT trigger clearing — they're partial IBANs,
    # not a signal that the account is non-IBAN.
    raw_bank_iban = get_extracted_string(extracted, "bank_iban")

    clear_iban? =
      not is_nil(raw_bank_iban) and
        is_nil(Map.get(extracted_attrs, :iban)) and
        not iban_candidate?(raw_bank_iban)

    # For re-extraction, only overwrite fields that have non-nil extracted values.
    # This preserves manually-edited data when re-extraction returns partial results.
    attrs =
      extracted_attrs
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> then(fn attrs -> if clear_iban?, do: Map.put(attrs, :iban, nil), else: attrs end)
      |> Map.put(:type, invoice.type)
      |> populate_company_fields(company)
      |> maybe_default_billing_date_for_update(invoice)

    # Preserve existing currency if extraction didn't provide one
    attrs =
      if Map.has_key?(attrs, :currency),
        do: attrs,
        else: Map.put(attrs, :currency, invoice.currency || "PLN")

    # Determine extraction status from merged invoice + new attrs so that
    # fields already present on the invoice (from prior extraction or manual
    # edit) count towards completeness.
    attrs = recalculate_extraction_status(invoice, attrs)

    with {:ok, updated} <- update_invoice(invoice, attrs, opts) do
      updated = maybe_detect_duplicate_after_extraction(updated, opts)
      maybe_enqueue_prediction(attrs.extraction_status, updated)
      {:ok, updated}
    end
  end

  # After re-extraction populates fields, check if this invoice is now a duplicate.
  # Only runs when the invoice is not already marked as a duplicate.
  @spec maybe_detect_duplicate_after_extraction(Invoice.t(), keyword()) :: Invoice.t()
  defp maybe_detect_duplicate_after_extraction(%Invoice{duplicate_of_id: id} = invoice, _opts)
       when not is_nil(id),
       do: invoice

  defp maybe_detect_duplicate_after_extraction(%Invoice{} = invoice, opts) do
    attrs = Map.from_struct(invoice)

    case DuplicateDetector.find_original_id(invoice.company_id, attrs, exclude_id: invoice.id) do
      nil -> invoice
      original_id -> mark_as_duplicate(invoice, original_id, opts)
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
  Returns the list of critical extraction fields that are missing on the invoice.
  """
  @spec missing_critical_fields(Invoice.t()) :: [atom()]
  def missing_critical_fields(%Invoice{} = invoice) do
    map = Map.from_struct(invoice)

    Enum.filter(@critical_extraction_fields, fn field ->
      not present_value?(Map.get(map, field))
    end)
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
  def approve_invoice(invoice, opts \\ [])

  def approve_invoice(%Invoice{type: :expense, extraction_status: status}, _opts)
      when status in [:partial, :failed] do
    {:error, :incomplete_extraction}
  end

  def approve_invoice(%Invoice{type: :expense} = invoice, opts) do
    invoice
    |> Invoice.changeset(%{status: :approved})
    |> TrackedRepo.update(opts)
  end

  def approve_invoice(%Invoice{type: type}, _opts), do: {:error, {:invalid_type, type}}

  # Auto-approves an invoice if the company setting and source/extraction rules allow it.
  # Delegates to approve_invoice/1 so all approval preconditions stay in one place.
  @spec maybe_auto_approve(Company.t(), Invoice.t(), keyword()) :: Invoice.t()
  defp maybe_auto_approve(company, invoice, opts \\ []) do
    if AutoApproval.should_auto_approve?(company, invoice, opts) do
      case approve_invoice(invoice, actor_label: "Auto-approval") do
        {:ok, approved} ->
          approved

        {:error, reason} ->
          Logger.error(
            "Auto-approval failed for invoice #{invoice.id} " <>
              "(company #{company.id}): #{inspect(reason)}"
          )

          invoice
      end
    else
      invoice
    end
  end

  @doc """
  Rejects an expense invoice.
  """
  @spec reject_invoice(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:invalid_type, Invoice.invoice_type()}}
  def reject_invoice(invoice, opts \\ [])

  def reject_invoice(%Invoice{type: :expense} = invoice, opts) do
    invoice
    |> Invoice.changeset(%{status: :rejected})
    |> TrackedRepo.update(opts)
  end

  def reject_invoice(%Invoice{type: type}, _opts), do: {:error, {:invalid_type, type}}

  @doc """
  Resets an expense invoice status back to pending.

  Only works for expense invoices that are currently approved or rejected.
  """
  @spec reset_invoice_status(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :already_pending}
          | {:error, {:invalid_type, Invoice.invoice_type()}}
  def reset_invoice_status(invoice, opts \\ [])

  def reset_invoice_status(%Invoice{type: :expense, status: :pending}, _opts) do
    {:error, :already_pending}
  end

  def reset_invoice_status(%Invoice{type: :expense, duplicate_status: :confirmed}, _opts) do
    {:error, :confirmed_duplicate}
  end

  def reset_invoice_status(%Invoice{type: :expense} = invoice, opts) do
    invoice
    |> Invoice.changeset(%{status: :pending})
    |> TrackedRepo.update(opts)
  end

  def reset_invoice_status(%Invoice{type: type}, _opts), do: {:error, {:invalid_type, type}}

  @doc "Marks an invoice as excluded."
  @spec exclude_invoice(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def exclude_invoice(%Invoice{} = invoice, opts \\ []) do
    invoice
    |> Invoice.changeset(%{is_excluded: true})
    |> TrackedRepo.update(opts)
  end

  @doc "Marks an invoice as included (removes exclusion)."
  @spec include_invoice(Invoice.t(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def include_invoice(%Invoice{} = invoice, opts \\ []) do
    invoice
    |> Invoice.changeset(%{is_excluded: false})
    |> TrackedRepo.update(opts)
  end

  @doc """
  Populates company-side fields on invoice attrs based on type.

  For expense invoices, sets buyer_nip and buyer_name from the company
  only when extraction didn't provide them. For income invoices, does
  the same for seller_nip and seller_name.
  """
  @spec populate_company_fields(map(), Company.t()) :: map()
  def populate_company_fields(attrs, %Company{} = company) do
    type = attrs[:type] || attrs["type"]

    case type do
      t when t in [:expense, "expense"] ->
        attrs
        |> put_if_blank(:buyer_nip, company.nip)
        |> put_if_blank(:buyer_name, company.name)

      t when t in [:income, "income"] ->
        attrs
        |> put_if_blank(:seller_nip, company.nip)
        |> put_if_blank(:seller_name, company.name)

      _ ->
        attrs
    end
  end

  @spec put_if_blank(map(), atom(), String.t() | nil) :: map()
  defp put_if_blank(attrs, key, value) do
    existing = Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

    if is_nil(existing) or existing == "" do
      Map.put(attrs, key, value)
    else
      attrs
    end
  end

  @spec maybe_put_created_by(map(), Ecto.UUID.t() | nil) :: map()
  defp maybe_put_created_by(attrs, nil), do: attrs
  defp maybe_put_created_by(attrs, id), do: Map.put(attrs, :created_by_id, id)

  @doc """
  Creates a manual invoice, optionally detecting duplicates by ksef_number.

  Forces `source: :manual` and strips KSeF-only fields. If a `ksef_number` is
  provided and an existing non-duplicate invoice with the same (company_id, ksef_number)
  exists, the new invoice is marked as a suspected duplicate.
  """
  @spec create_manual_invoice(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_manual_invoice(company_id, attrs, opts \\ []) do
    company = Companies.get_company!(company_id)

    attrs =
      attrs
      |> Map.drop([:ksef_acquisition_date, :ksef_permanent_storage_date])
      |> Map.drop(["ksef_acquisition_date", "ksef_permanent_storage_date"])
      |> Map.merge(%{source: :manual, company_id: company_id})
      |> populate_company_fields(company)

    case create_or_retry_duplicate(company_id, attrs, opts) do
      {:ok, invoice} ->
        enqueue_prediction(invoice)
        {:ok, maybe_auto_approve(company, invoice)}

      error ->
        error
    end
  end

  @spec create_or_retry_duplicate(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | term()}
  defp create_or_retry_duplicate(company_id, attrs, opts) do
    attrs = DuplicateDetector.detect(company_id, attrs)

    case create_invoice(attrs, opts) do
      {:ok, invoice} ->
        {:ok, invoice}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ksef_number_conflict?(changeset),
          do: retry_as_duplicate(company_id, attrs, opts),
          else: {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec retry_as_duplicate(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp retry_as_duplicate(company_id, attrs, opts) do
    attrs
    |> Map.merge(%{
      duplicate_of_id: DuplicateDetector.find_original_id(company_id, attrs),
      duplicate_status: :suspected
    })
    |> create_invoice(opts)
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
  @spec create_pdf_upload_invoice(Company.t(), binary(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, term()}
  def create_pdf_upload_invoice(%Company{} = company, pdf_binary, opts, event_opts \\ []) do
    case extract_and_create_pdf(company, pdf_binary, opts, event_opts) do
      {:ok, invoice, _meta} -> {:ok, invoice}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a PDF upload invoice with NIP verification.

  Rejects the invoice if the extracted buyer NIP doesn't match the company NIP.
  When buyer NIP cannot be extracted, the invoice is accepted with company fields as fallback.
  """
  @spec create_pdf_upload_invoice_with_meta(Company.t(), binary(), map(), keyword()) ::
          {:ok, Invoice.t(), keyword()} | {:error, term()}
  def create_pdf_upload_invoice_with_meta(
        %Company{} = company,
        pdf_binary,
        opts,
        event_opts \\ []
      ) do
    extract_and_create_pdf(company, pdf_binary, opts, event_opts)
  end

  @spec extract_and_create_pdf(Company.t(), binary(), map(), keyword()) ::
          {:ok, Invoice.t(), keyword()} | {:error, term()}
  defp extract_and_create_pdf(company, pdf_binary, opts, event_opts) do
    type = opts[:type]
    filename = opts[:filename]
    created_by_id = opts[:created_by_id]
    context = ContextBuilder.build(company, type)

    extract_opts = [filename: filename || "invoice.pdf", context: context]

    case invoice_extractor().extract(pdf_binary, extract_opts) do
      {:ok, extracted} ->
        create_from_extraction(
          company,
          pdf_binary,
          type,
          filename,
          extracted,
          created_by_id,
          event_opts
        )

      {:error, _reason} ->
        Logger.warning("PDF extraction failed for file: #{filename || "invoice.pdf"}")

        create_from_failed_extraction(
          company,
          pdf_binary,
          type,
          filename,
          created_by_id,
          event_opts
        )
    end
  end

  @spec create_from_extraction(
          Company.t(),
          binary(),
          atom(),
          String.t() | nil,
          map(),
          Ecto.UUID.t() | nil,
          keyword()
        ) ::
          {:ok, Invoice.t(), keyword()} | {:error, term()}
  defp create_from_extraction(
         company,
         pdf_binary,
         type,
         filename,
         extracted,
         created_by_id,
         event_opts
       ) do
    with :ok <- verify_nip_for_type(extracted, company.nip, type),
         {:ok, invoice} <-
           do_create_pdf_extracted(
             company,
             pdf_binary,
             type,
             filename,
             extracted,
             :pdf_upload,
             [created_by_id: created_by_id],
             event_opts
           ) do
      {:ok, invoice, []}
    end
  end

  @spec create_from_failed_extraction(
          Company.t(),
          binary(),
          atom(),
          String.t() | nil,
          Ecto.UUID.t() | nil,
          keyword()
        ) ::
          {:ok, Invoice.t(), keyword()} | {:error, term()}
  defp create_from_failed_extraction(
         company,
         pdf_binary,
         type,
         filename,
         created_by_id,
         event_opts
       ) do
    case do_create_pdf_failed(
           company,
           pdf_binary,
           type,
           filename,
           :pdf_upload,
           [created_by_id: created_by_id],
           event_opts
         ) do
      {:ok, invoice} -> {:ok, invoice, []}
      error -> error
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
    company = Companies.get_company!(company_id)
    event_opts = email_actor_opts(opts[:sender_email])
    do_create_pdf_failed(company, pdf_binary, :expense, opts[:filename], :email, opts, event_opts)
  end

  def create_email_invoice(company_id, pdf_binary, extracted, opts) when is_map(extracted) do
    company = Companies.get_company!(company_id)
    event_opts = email_actor_opts(opts[:sender_email])

    do_create_pdf_extracted(
      company,
      pdf_binary,
      :expense,
      opts[:filename],
      extracted,
      :email,
      opts,
      event_opts
    )
  end

  @spec email_actor_opts(String.t() | nil) :: keyword()
  defp email_actor_opts(nil), do: [actor_type: :email]
  defp email_actor_opts(sender), do: [actor_type: :email, actor_label: sender]

  # Shared: create invoice from extracted fields with duplicate detection + prediction
  @spec do_create_pdf_extracted(
          Company.t(),
          binary(),
          atom(),
          String.t() | nil,
          map(),
          Invoice.invoice_source(),
          keyword(),
          keyword()
        ) :: {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_extracted(
         company,
         pdf_binary,
         type,
         filename,
         extracted,
         source,
         opts,
         event_opts
       ) do
    extraction_status = determine_extraction_status(extracted)

    invoice_attrs =
      build_pdf_upload_attrs(extracted, company.id, pdf_binary, type, filename, extraction_status)
      |> Map.put(:source, source)
      |> maybe_put_created_by(opts[:created_by_id])
      |> populate_company_fields(company)

    case create_or_retry_duplicate(company.id, invoice_attrs, event_opts) do
      {:ok, invoice} ->
        unless opts[:skip_prediction], do: maybe_enqueue_prediction(extraction_status, invoice)
        {:ok, maybe_auto_approve(company, invoice, opts)}

      error ->
        error
    end
  end

  # Shared: create invoice when extraction failed
  @spec do_create_pdf_failed(
          Company.t(),
          binary(),
          atom(),
          String.t() | nil,
          Invoice.invoice_source(),
          keyword(),
          keyword()
        ) :: {:ok, Invoice.t()} | {:error, term()}
  defp do_create_pdf_failed(company, pdf_binary, type, filename, source, opts, event_opts) do
    attrs =
      %{
        source: source,
        type: type,
        company_id: company.id,
        pdf_content: pdf_binary,
        original_filename: filename,
        extraction_status: :failed
      }
      |> maybe_put_created_by(opts[:created_by_id])
      |> populate_company_fields(company)

    create_invoice(attrs, event_opts)
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

  defp present_value?(s) when is_binary(s) do
    trimmed = String.trim(s)
    trimmed != "" and trimmed not in @extraction_placeholders
  end

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
    attrs = extracted_to_invoice_attrs(extracted)

    attrs
    |> Map.put(:currency, attrs[:currency] || "PLN")
    |> Map.merge(%{
      source: :pdf_upload,
      type: type,
      company_id: company_id,
      pdf_content: pdf_binary,
      original_filename: filename,
      extraction_status: extraction_status
    })
  end

  # Shared mapping from extraction result (string-keyed map) to invoice attrs (atom-keyed map).
  # Used by both initial PDF upload creation and re-extraction.
  @spec extracted_to_invoice_attrs(map()) :: map()
  defp extracted_to_invoice_attrs(extracted) do
    iban = extract_iban(extracted)
    explicit_account = get_extracted_string(extracted, "bank_account_number")

    # When bank_iban contained a non-IBAN value (e.g. Indonesian local account),
    # extract_iban/1 returns nil. Fall back the raw value to account_number
    # so the data isn't lost. Explicit bank_account_number takes priority.
    account_number =
      explicit_account || non_iban_fallback(extracted, iban)

    %{
      seller_nip: get_extracted_nip(extracted, "seller_nip"),
      seller_name: get_extracted_string(extracted, "seller_name"),
      buyer_nip: get_extracted_nip(extracted, "buyer_nip"),
      buyer_name: get_extracted_string(extracted, "buyer_name"),
      invoice_number: get_extracted_string(extracted, "invoice_number"),
      issue_date: get_extracted_date(extracted, "issue_date"),
      net_amount: get_extracted_decimal(extracted, "net_amount"),
      gross_amount: get_extracted_decimal(extracted, "gross_amount"),
      currency: get_extracted_string(extracted, "currency"),
      ksef_number: get_extracted_string(extracted, "ksef_number"),
      purchase_order: get_extracted_purchase_order(extracted, "purchase_order"),
      sales_date: get_extracted_date(extracted, "sales_date"),
      due_date: get_extracted_date(extracted, "due_date"),
      iban: iban,
      swift_bic: get_extracted_string(extracted, "bank_swift_bic"),
      bank_name: get_extracted_string(extracted, "bank_name"),
      bank_address: get_extracted_string(extracted, "bank_address"),
      routing_number: get_extracted_string(extracted, "bank_routing_number"),
      account_number: account_number,
      payment_instructions: get_extracted_string(extracted, "bank_notes"),
      seller_address: get_extracted_address(extracted, "seller_address_"),
      buyer_address: get_extracted_address(extracted, "buyer_address_")
    }
  end

  @address_fields ~w(street city postal_code country)

  @spec get_extracted_address(map(), String.t()) :: map() | nil
  defp get_extracted_address(data, prefix) do
    addr =
      Map.new(@address_fields, fn field ->
        {field, get_extracted_string(data, prefix <> field)}
      end)

    cleaned =
      addr
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    if map_size(cleaned) == 0, do: nil, else: cleaned
  end

  @spec get_extracted_string(map(), String.t()) :: String.t() | nil
  defp get_extracted_string(data, key) do
    case data[key] do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "" or trimmed in @extraction_placeholders, do: nil, else: trimmed

      _ ->
        nil
    end
  end

  @spec get_extracted_nip(map(), String.t()) :: String.t() | nil
  defp get_extracted_nip(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> normalize_nip(value)
    end
  end

  defp verify_nip_for_type(extracted, company_nip, type),
    do: NipVerifier.verify_for_type(extracted, company_nip, type)

  @spec get_extracted_purchase_order(map(), String.t()) :: String.t() | nil
  defp get_extracted_purchase_order(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> PurchaseOrder.extract(value)
    end
  end

  # Returns the raw bank_iban value when it was rejected as non-IBAN
  # (i.e. extract_iban returned nil), so it can populate account_number.
  # Values that look like truncated IBANs (start with a country prefix)
  # are NOT demoted — they're partial IBANs, not local account numbers.
  @spec non_iban_fallback(map(), String.t() | nil) :: String.t() | nil
  defp non_iban_fallback(_extracted, iban) when not is_nil(iban), do: nil

  defp non_iban_fallback(extracted, nil) do
    raw = get_extracted_string(extracted, "bank_iban")
    if iban_candidate?(raw), do: nil, else: raw
  end

  # Extracts and normalizes IBAN from the extracted data.
  # Returns nil when the value is shorter than 15 chars (minimum IBAN length),
  # routing it to :account_number instead via extracted_to_invoice_attrs/1.
  @spec extract_iban(map()) :: String.t() | nil
  defp extract_iban(extracted) do
    case get_extracted_string(extracted, "bank_iban") do
      nil -> nil
      raw -> normalize_iban(raw)
    end
  end

  # IBANs are 15-34 characters. Values shorter than 15 chars are local
  # account numbers (e.g. Indonesian) that don't belong in the IBAN field.
  # Matches values that start with a 2-letter country code followed by digits,
  # indicating the value is a (possibly truncated) IBAN rather than a local
  # account number. Used to avoid demoting partial IBANs to account_number.
  @iban_prefix_pattern ~r/^[A-Za-z]{2}\d/

  @spec iban_candidate?(String.t() | nil) :: boolean()
  defp iban_candidate?(nil), do: false

  defp iban_candidate?(value) do
    stripped = value |> String.trim() |> String.replace(~r/[\s\-]/, "")
    Regex.match?(@iban_prefix_pattern, stripped)
  end

  @iban_min_length 15

  @spec normalize_iban(String.t()) :: String.t() | nil
  defp normalize_iban(value) do
    stripped = value |> String.trim() |> String.replace(~r/[\s\-]/, "")

    cond do
      String.length(stripped) < @iban_min_length -> nil
      Regex.match?(~r/^[A-Za-z]{2}\d{2}/, stripped) -> String.upcase(stripped)
      true -> stripped
    end
  end

  @spec normalize_nip(String.t()) :: String.t()
  defp normalize_nip(value), do: KsefHub.Nip.normalize(value)

  @spec get_extracted_date(map(), String.t()) :: Date.t() | nil
  defp get_extracted_date(data, key) do
    case get_extracted_string(data, key) do
      nil -> nil
      value -> parse_date(value)
    end
  end

  @spec parse_date(String.t()) :: Date.t() | nil
  defp parse_date(value) do
    with {:error, _} <- Date.from_iso8601(value),
         :error <- parse_datetime_as_date(value),
         :error <- parse_naive_datetime_as_date(value) do
      nil
    else
      {:ok, date} -> date
    end
  end

  @spec parse_datetime_as_date(String.t()) :: {:ok, Date.t()} | :error
  defp parse_datetime_as_date(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, DateTime.to_date(dt)}
      _ -> :error
    end
  end

  @spec parse_naive_datetime_as_date(String.t()) :: {:ok, Date.t()} | :error
  defp parse_naive_datetime_as_date(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, ndt} -> {:ok, NaiveDateTime.to_date(ndt)}
      _ -> :error
    end
  end

  # Returns nil for zero values since the extraction schema uses all-required fields,
  # so the LLM returns 0 for amounts not found on the invoice. Treating 0 as nil
  # ensures determine_extraction_status correctly marks these as :partial.
  @spec get_extracted_decimal(map(), String.t()) :: Decimal.t() | nil
  defp get_extracted_decimal(data, key) do
    result =
      case data[key] do
        nil -> nil
        value when is_integer(value) -> Decimal.new(value)
        value when is_float(value) -> Decimal.from_float(value)
        value when is_binary(value) -> parse_decimal(value)
        _ -> nil
      end

    if result && not Decimal.equal?(result, 0), do: result, else: nil
  end

  @spec parse_decimal(String.t()) :: Decimal.t() | nil
  defp parse_decimal(value) do
    case value |> String.trim() |> Decimal.parse() do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end

  @spec do_insert_invoice(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_insert_invoice(company_id, attrs, caller_opts) do
    {file_ids, attrs} = pop_file_ids(attrs)
    {created_by_id, attrs} = Map.pop(attrs, :created_by_id)
    {access_restricted, attrs} = Map.pop(attrs, :access_restricted)

    trusted_fields =
      file_ids
      |> Map.put(:company_id, company_id)
      |> then(fn m ->
        if created_by_id, do: Map.put(m, :created_by_id, created_by_id), else: m
      end)
      |> then(fn m ->
        if is_boolean(access_restricted),
          do: Map.put(m, :access_restricted, access_restricted),
          else: m
      end)

    opts = build_insert_opts(caller_opts, created_by_id)

    %Invoice{}
    |> Ecto.Changeset.change(trusted_fields)
    |> Invoice.changeset(attrs)
    |> TrackedRepo.insert(opts)
  end

  @spec build_insert_opts(keyword(), Ecto.UUID.t() | nil) :: keyword()
  defp build_insert_opts(caller_opts, _created_by_id) when caller_opts != [], do: caller_opts

  defp build_insert_opts(_caller_opts, nil), do: []

  defp build_insert_opts(_caller_opts, created_by_id) do
    label =
      case Repo.get(User, created_by_id) do
        %User{name: name, email: email} -> name || email
        nil -> nil
      end

    [user_id: created_by_id, actor_label: label]
  end

  @spec do_upsert_invoice(Ecto.UUID.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_upsert_invoice(company_id, attrs) do
    {file_ids, attrs} = pop_file_ids(attrs)
    {created_by_id, attrs} = Map.pop(attrs, :created_by_id)
    {access_restricted, attrs} = Map.pop(attrs, :access_restricted)

    trusted_fields =
      file_ids
      |> Map.put(:company_id, company_id)
      |> then(fn m ->
        if created_by_id, do: Map.put(m, :created_by_id, created_by_id), else: m
      end)
      |> then(fn m ->
        if is_boolean(access_restricted),
          do: Map.put(m, :access_restricted, access_restricted),
          else: m
      end)

    %Invoice{}
    |> Ecto.Changeset.change(trusted_fields)
    |> Invoice.changeset(attrs)
    |> TrackedRepo.insert(
      on_conflict: {:replace, @upsert_replace_fields},
      conflict_target:
        {:unsafe_fragment,
         ~s|("company_id","ksef_number") WHERE ksef_number IS NOT NULL AND duplicate_of_id IS NULL|},
      returning: true,
      actor_type: :system,
      actor_label: "KSeF Sync"
    )
  end

  @spec pop_file_ids(map()) :: {map(), map()}
  defp pop_file_ids(attrs) do
    {xml_file_id, attrs} = Map.pop(attrs, :xml_file_id)
    {pdf_file_id, attrs} = Map.pop(attrs, :pdf_file_id)

    file_ids =
      %{}
      |> then(fn m -> if xml_file_id, do: Map.put(m, :xml_file_id, xml_file_id), else: m end)
      |> then(fn m -> if pdf_file_id, do: Map.put(m, :pdf_file_id, pdf_file_id), else: m end)

    {file_ids, attrs}
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
  def confirm_duplicate(invoice, opts \\ [])

  def confirm_duplicate(%Invoice{duplicate_of_id: nil}, _opts),
    do: {:error, :not_a_duplicate}

  def confirm_duplicate(%Invoice{duplicate_status: :suspected} = invoice, opts) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :confirmed})
    |> TrackedRepo.update(opts)
  end

  def confirm_duplicate(%Invoice{}, _opts), do: {:error, :invalid_status}

  @doc """
  Dismisses a duplicate invoice.

  Valid when `duplicate_of_id` is set and `duplicate_status` is `:suspected` or `:confirmed`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not dismissable.
  """
  @spec dismiss_duplicate(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def dismiss_duplicate(invoice, opts \\ [])

  def dismiss_duplicate(%Invoice{duplicate_of_id: nil}, _opts),
    do: {:error, :not_a_duplicate}

  def dismiss_duplicate(%Invoice{duplicate_status: status} = invoice, opts)
      when status in [:suspected, :confirmed] do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: :dismissed})
    |> TrackedRepo.update(opts)
  end

  def dismiss_duplicate(%Invoice{}, _opts), do: {:error, :invalid_status}

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

  # --- Aggregation Queries ---

  @doc """
  Returns monthly expense totals with proportional allocation for multi-month invoices.

  Invoices spanning multiple months have their net_amount divided equally across each
  month in the range (with rounding remainder assigned to the last month).

  Supports filters: `:category_id`, `:tags`, `:billing_date_from`, `:billing_date_to`.
  Excludes invoices with nil billing_date_from/billing_date_to.
  """
  @spec expense_monthly_totals(Ecto.UUID.t(), map()) :: [map()]
  def expense_monthly_totals(company_id, filters \\ %{}) do
    company_id
    |> base_aggregation_query(:expense)
    |> apply_filters(filters)
    |> select([i], %{
      billing_date_from: i.billing_date_from,
      billing_date_to: i.billing_date_to,
      net_amount: i.net_amount
    })
    |> Repo.all()
    |> expand_to_monthly_allocations()
    |> trim_allocations_to_window(filters)
    |> Enum.group_by(& &1.billing_date, & &1.allocated_amount)
    |> Enum.map(fn {date, amounts} ->
      %{billing_date: date, net_total: sum_decimals(amounts)}
    end)
    |> Enum.sort_by(& &1.billing_date, Date)
  end

  @doc """
  Returns expense totals grouped by category with proportional multi-month allocation.

  Supports filters: `:tags`, `:billing_date_from`, `:billing_date_to`.
  Excludes invoices with nil billing_date_from/billing_date_to. Uncategorized invoices
  are grouped under `category_name: "Uncategorized"` with `emoji: nil`.
  """
  @spec expense_by_category(Ecto.UUID.t(), map()) :: [map()]
  def expense_by_category(company_id, filters \\ %{}) do
    company_id
    |> base_aggregation_query(:expense)
    |> apply_filters(filters)
    |> join(:left, [i], c in Category, on: i.category_id == c.id)
    |> select([i, ..., c], %{
      category_name: coalesce(c.name, coalesce(c.identifier, "Uncategorized")),
      emoji: c.emoji,
      billing_date_from: i.billing_date_from,
      billing_date_to: i.billing_date_to,
      net_amount: i.net_amount
    })
    |> Repo.all()
    |> Enum.flat_map(&expand_with_metadata(&1, [:category_name, :emoji]))
    |> trim_allocations_to_window(filters)
    |> Enum.group_by(fn row -> {row.category_name, row.emoji} end, & &1.allocated_amount)
    |> Enum.map(fn {{name, emoji}, amounts} ->
      %{category_name: name, emoji: emoji, net_total: sum_decimals(amounts)}
    end)
    |> Enum.sort_by(& &1.net_total, {:desc, Decimal})
  end

  @doc """
  Returns income summary comparing current month to last month (net amounts).
  Uses billing date range with proportional allocation for multi-month invoices.
  """
  @spec income_monthly_summary(Ecto.UUID.t()) :: map()
  def income_monthly_summary(company_id) do
    today = Date.utc_today()
    current_month_start = Date.beginning_of_month(today)
    last_month_start = current_month_start |> Date.add(-1) |> Date.beginning_of_month()

    # Fetch invoices whose billing range overlaps either month
    invoices =
      company_id
      |> base_aggregation_query(:income)
      |> where(
        [i],
        i.billing_date_to >= ^last_month_start and i.billing_date_from <= ^current_month_start
      )
      |> select([i], %{
        billing_date_from: i.billing_date_from,
        billing_date_to: i.billing_date_to,
        net_amount: i.net_amount
      })
      |> Repo.all()

    allocated =
      invoices
      |> expand_to_monthly_allocations()
      |> Enum.filter(&(&1.billing_date in [current_month_start, last_month_start]))
      |> Enum.group_by(& &1.billing_date, & &1.allocated_amount)

    %{
      current_month:
        Map.get(allocated, current_month_start, [])
        |> sum_decimals(),
      last_month:
        Map.get(allocated, last_month_start, [])
        |> sum_decimals()
    }
  end

  @spec base_aggregation_query(Ecto.UUID.t(), :income | :expense) :: Ecto.Query.t()
  defp base_aggregation_query(company_id, type) do
    Invoice
    |> where(
      [i],
      i.company_id == ^company_id and i.type == ^type and
        not is_nil(i.billing_date_from) and not is_nil(i.billing_date_to)
    )
  end

  @spec sum_decimals([Decimal.t()]) :: Decimal.t()
  defp sum_decimals(amounts), do: Enum.reduce(amounts, Decimal.new(0), &Decimal.add/2)

  @spec trim_allocations_to_window([map()], map()) :: [map()]
  defp trim_allocations_to_window(allocations, filters) do
    from = Map.get(filters, :billing_date_from)
    to = Map.get(filters, :billing_date_to)

    allocations
    |> then(fn allocs ->
      if from,
        do: Enum.filter(allocs, &(Date.compare(&1.billing_date, from) != :lt)),
        else: allocs
    end)
    |> then(fn allocs ->
      if to, do: Enum.filter(allocs, &(Date.compare(&1.billing_date, to) != :gt)), else: allocs
    end)
  end

  # --- Multi-month allocation helpers ---

  @spec expand_to_monthly_allocations([map()]) :: [map()]
  defp expand_to_monthly_allocations(invoices) do
    Enum.flat_map(invoices, fn row ->
      allocate_across_months(row.billing_date_from, row.billing_date_to, row.net_amount)
      |> Enum.map(fn {date, amount} ->
        %{billing_date: date, allocated_amount: amount}
      end)
    end)
  end

  @spec expand_with_metadata(map(), [atom()]) :: [map()]
  defp expand_with_metadata(row, extra_keys) do
    metadata = Map.take(row, extra_keys)

    allocate_across_months(row.billing_date_from, row.billing_date_to, row.net_amount)
    |> Enum.map(fn {date, amount} ->
      Map.merge(metadata, %{billing_date: date, allocated_amount: amount})
    end)
  end

  @spec allocate_across_months(Date.t(), Date.t(), Decimal.t()) :: [{Date.t(), Decimal.t()}]
  defp allocate_across_months(from, to, net_amount) when not is_nil(net_amount) do
    months = months_between(from, to)
    count = length(months)

    if count <= 1 do
      [{from, net_amount}]
    else
      per_month = Decimal.div(net_amount, count) |> Decimal.round(2)
      allocated_sum = Decimal.mult(per_month, count - 1)
      last_amount = Decimal.sub(net_amount, allocated_sum)

      {init_months, [last_month]} = Enum.split(months, -1)

      Enum.map(init_months, &{&1, per_month}) ++ [{last_month, last_amount}]
    end
  end

  defp allocate_across_months(_from, _to, _nil_amount), do: []

  @spec months_between(Date.t(), Date.t()) :: [Date.t()]
  defp months_between(%Date{} = from, %Date{} = to) do
    Stream.unfold(from, fn current ->
      if Date.compare(current, to) == :gt do
        nil
      else
        next = current |> Date.add(32) |> Date.beginning_of_month()
        {current, next}
      end
    end)
    |> Enum.to_list()
  end

  # --- Categories ---

  @doc "Returns all categories for a company, ordered by sort_order then identifier."
  @spec list_categories(Ecto.UUID.t()) :: [Category.t()]
  def list_categories(company_id) do
    Category
    |> where([c], c.company_id == ^company_id)
    |> order_by([c], asc: c.sort_order, asc: c.identifier)
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
  def create_category(company_id, attrs, opts \\ []) do
    %Category{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Category.changeset(attrs)
    |> TrackedRepo.insert(opts)
  end

  @doc "Updates a category."
  @spec update_category(Category.t(), map(), keyword()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%Category{} = category, attrs, opts \\ []) do
    category
    |> Category.changeset(attrs)
    |> TrackedRepo.update(opts)
  end

  @doc "Deletes a category. Associated invoices get category_id nilified."
  @spec delete_category(Category.t(), keyword()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def delete_category(%Category{} = category, opts \\ []) do
    TrackedRepo.delete(category, opts)
  end

  # --- Tags ---

  @doc "Sets the tags on an invoice, replacing any existing tags."
  @spec set_invoice_tags(Invoice.t(), [String.t()]) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def set_invoice_tags(invoice, tags, opts \\ [])

  def set_invoice_tags(%Invoice{} = invoice, tags, opts) when is_list(tags) do
    if Enum.all?(tags, &is_binary/1) do
      do_set_invoice_tags(invoice, tags, opts)
    else
      changeset =
        invoice
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:tags, "all tags must be strings")

      {:error, changeset}
    end
  end

  def set_invoice_tags(%Invoice{} = invoice, _tags, _opts) do
    changeset =
      invoice
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:tags, "must be a list")

    {:error, changeset}
  end

  @spec do_set_invoice_tags(Invoice.t(), [String.t()], keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_set_invoice_tags(invoice, tags, opts) do
    normalized = tags |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    invoice
    |> Invoice.tags_changeset(%{tags: normalized})
    |> TrackedRepo.update(opts)
  end

  @doc "Adds a single tag to an invoice (idempotent). Trims whitespace. Uses atomic DB update with validation guards."
  @spec add_invoice_tag(Invoice.t(), String.t()) :: {:ok, Invoice.t()}
  def add_invoice_tag(%Invoice{} = invoice, tag_name) when is_binary(tag_name) do
    trimmed = String.trim(tag_name)

    if trimmed == "" or String.length(trimmed) > Invoice.max_tag_length() do
      {:ok, invoice}
    else
      Invoice
      |> where([i], i.id == ^invoice.id)
      |> where([i], fragment("NOT ? = ANY(?)", ^trimmed, i.tags))
      |> where([i], fragment("coalesce(array_length(?, 1), 0) < ?", i.tags, ^Invoice.max_tags()))
      |> Repo.update_all(
        set: [tags: dynamic([i], fragment("array_append(?, ?)", i.tags, ^trimmed))]
      )

      {:ok, Repo.reload!(invoice)}
    end
  end

  @doc """
  Lists distinct tag values used on invoices for a company,
  optionally filtered by invoice type. Ordered by most recently used.
  """
  @spec list_distinct_tags(Ecto.UUID.t(), atom() | nil, keyword()) :: [String.t()]
  def list_distinct_tags(company_id, type \\ nil, opts \\ []) do
    base =
      Invoice
      |> where([i], i.company_id == ^company_id)
      |> then(fn q -> if type, do: where(q, [i], i.type == ^type), else: q end)
      |> where([i], fragment("array_length(?, 1) > 0", i.tags))
      |> maybe_filter_by_access(opts)

    from(
      t in subquery(
        from(i in base,
          select: %{
            tag: fragment("unnest(?)", i.tags),
            updated_at: i.updated_at
          }
        )
      ),
      group_by: t.tag,
      order_by: [desc: max(t.updated_at)],
      select: t.tag
    )
    |> Repo.all()
  end

  # --- Invoice-Category Assignment ---

  @doc """
  Assigns or clears a category on an invoice.

  Categories are expense-only — returns `{:error, :expense_only}` for income invoices.
  When `category_id` is not nil, verifies the category belongs to the same
  company as the invoice before updating.
  """
  @spec set_invoice_category(Invoice.t(), Ecto.UUID.t() | nil) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t() | :category_not_in_company | :expense_only}
  def set_invoice_category(invoice, category_id, opts \\ [])

  def set_invoice_category(%Invoice{type: :income} = invoice, nil, _opts),
    do: {:ok, invoice}

  def set_invoice_category(%Invoice{type: :income}, _category_id, _opts),
    do: {:error, :expense_only}

  def set_invoice_category(%Invoice{} = invoice, nil, opts) do
    old_name = current_category_name(invoice)
    existing_meta = Keyword.get(opts, :metadata, %{})
    merged_meta = Map.merge(existing_meta, %{old_name: old_name, new_name: nil})

    invoice
    |> Invoice.category_changeset(%{category_id: nil})
    |> TrackedRepo.update(Keyword.put(opts, :metadata, merged_meta))
  end

  def set_invoice_category(%Invoice{} = invoice, category_id, opts) do
    with %Category{} = category <- fetch_company_category(invoice.company_id, category_id),
         attrs <- build_category_attrs(category_id, category) do
      old_name = current_category_name(invoice)
      existing_meta = Keyword.get(opts, :metadata, %{})
      merged_meta = Map.merge(existing_meta, %{old_name: old_name, new_name: category.name})

      invoice
      |> Invoice.category_changeset(attrs)
      |> TrackedRepo.update(Keyword.put(opts, :metadata, merged_meta))
    else
      nil -> {:error, :category_not_in_company}
    end
  end

  @doc """
  Sets the cost line on an expense invoice independently of category.

  Returns `{:error, :expense_only}` for income invoices.
  """
  @spec set_invoice_cost_line(Invoice.t(), atom() | nil) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :expense_only}
  def set_invoice_cost_line(invoice, cost_line, opts \\ [])

  def set_invoice_cost_line(%Invoice{type: :income}, _cost_line, _opts),
    do: {:error, :expense_only}

  def set_invoice_cost_line(%Invoice{} = invoice, cost_line, opts) do
    invoice
    |> Invoice.category_changeset(%{cost_line: cost_line})
    |> TrackedRepo.update(opts)
  end

  @doc """
  Sets the project tag on an invoice. Works for both income and expense invoices.

  Pass `nil` to clear the project tag.
  """
  @spec set_invoice_project_tag(Invoice.t(), String.t() | nil) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def set_invoice_project_tag(%Invoice{} = invoice, project_tag, opts \\ []) do
    invoice
    |> Invoice.project_tag_changeset(%{project_tag: project_tag})
    |> TrackedRepo.update(opts)
  end

  @doc """
  Lists distinct project tag values used on invoices for a company within the last year,
  ordered by most recently used.
  """
  @spec list_project_tags(Ecto.UUID.t()) :: [String.t()]
  def list_project_tags(company_id) do
    one_year_ago = DateTime.utc_now() |> DateTime.add(-365, :day)

    from(i in Invoice,
      where: i.company_id == ^company_id,
      where: not is_nil(i.project_tag),
      where: i.inserted_at >= ^one_year_ago,
      group_by: i.project_tag,
      order_by: [desc: max(i.inserted_at)],
      select: i.project_tag
    )
    |> Repo.all()
  end

  @doc """
  Marks an invoice's prediction status as `:manual`, indicating the user
  overrode or manually set the category/tags.

  No-ops when prediction_status is nil (never classified) or already :manual.
  """
  @spec mark_prediction_manual(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def mark_prediction_manual(%Invoice{prediction_status: nil} = invoice), do: {:ok, invoice}
  def mark_prediction_manual(%Invoice{prediction_status: :manual} = invoice), do: {:ok, invoice}

  def mark_prediction_manual(%Invoice{} = invoice) do
    invoice
    |> Invoice.prediction_changeset(%{prediction_status: :manual})
    |> Repo.update()
  end

  @doc """
  Executes `fun` inside a transaction, then marks the invoice's prediction
  status as `:manual`. Both operations succeed atomically or neither does.

  Use this from UI handlers that modify category/tags to ensure the prediction
  status update cannot silently fail while the primary change succeeds.
  """
  @spec with_manual_prediction(Invoice.t(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_manual_prediction(%Invoice{} = invoice, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, result} ->
          do_mark_prediction_manual_in_txn!(invoice)
          result

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @spec do_mark_prediction_manual_in_txn!(Invoice.t()) :: :ok
  defp do_mark_prediction_manual_in_txn!(%Invoice{prediction_status: nil}), do: :ok
  defp do_mark_prediction_manual_in_txn!(%Invoice{prediction_status: :manual}), do: :ok

  defp do_mark_prediction_manual_in_txn!(%Invoice{} = invoice) do
    invoice
    |> Invoice.prediction_changeset(%{prediction_status: :manual})
    |> Repo.update!()

    :ok
  end

  # --- Invoice Notes ---

  @doc "Updates the note on an invoice."
  @spec update_invoice_note(Invoice.t(), map()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_invoice_note(%Invoice{} = invoice, attrs, opts \\ []) do
    invoice
    |> Invoice.note_changeset(attrs)
    |> TrackedRepo.update(opts)
  end

  @doc "Updates the billing date range on any invoice, regardless of source."
  @spec update_billing_date(Invoice.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def update_billing_date(%Invoice{} = invoice, attrs, opts \\ []) do
    invoice
    |> Invoice.billing_date_changeset(attrs)
    |> TrackedRepo.update(opts)
  end

  # --- Invoice Comments ---

  @doc "Lists comments for an invoice, ordered by insertion time ascending, with user preloaded. Scoped to company."
  @spec list_invoice_comments(Ecto.UUID.t(), Ecto.UUID.t()) :: [InvoiceComment.t()]
  def list_invoice_comments(company_id, invoice_id) do
    InvoiceComment
    |> join(:inner, [c], i in Invoice, on: c.invoice_id == i.id)
    |> where([c, i], c.invoice_id == ^invoice_id and i.company_id == ^company_id)
    |> order_by([c], asc: c.inserted_at, asc: c.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Creates a comment on an invoice and returns it with user preloaded. Verifies invoice belongs to company."
  @spec create_invoice_comment(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t(), map(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def create_invoice_comment(company_id, invoice_id, user_id, attrs, opts \\ []) do
    case Repo.get_by(Invoice, id: invoice_id, company_id: company_id) do
      nil ->
        {:error, :not_found}

      _invoice ->
        %InvoiceComment{}
        |> Ecto.Changeset.change(%{invoice_id: invoice_id, user_id: user_id})
        |> InvoiceComment.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, comment} ->
            comment = Repo.preload(comment, :user)
            invoice_ref = %{id: invoice_id, company_id: company_id}

            event_opts =
              opts
              |> Keyword.put_new(:user_id, user_id)
              |> Keyword.put_new_lazy(:actor_label, fn ->
                comment.user && (comment.user.name || comment.user.email)
              end)

            Events.invoice_comment_added(invoice_ref, comment, event_opts)
            {:ok, comment}

          error ->
            error
        end
    end
  end

  @doc "Updates an existing comment's body. Returns {:error, :unauthorized} if the user doesn't own the comment."
  @spec update_invoice_comment(InvoiceComment.t(), User.t(), map(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def update_invoice_comment(%InvoiceComment{} = comment, %User{} = user, attrs, opts \\ []) do
    if comment.user_id != user.id do
      {:error, :unauthorized}
    else
      opts =
        opts
        |> Keyword.put_new(:user_id, user.id)
        |> Keyword.put_new(:actor_label, user.name || user.email)

      comment
      |> InvoiceComment.changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, updated} ->
          updated = Repo.preload(updated, :user)
          emit_comment_event(updated, "invoice.comment_edited", opts)
          {:ok, updated}

        error ->
          error
      end
    end
  end

  @doc "Deletes a comment. Returns {:error, :unauthorized} if the user doesn't own the comment."
  @spec delete_invoice_comment(InvoiceComment.t(), User.t(), keyword()) ::
          {:ok, InvoiceComment.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def delete_invoice_comment(%InvoiceComment{} = comment, %User{} = user, opts \\ []) do
    if comment.user_id != user.id do
      {:error, :unauthorized}
    else
      opts =
        opts
        |> Keyword.put_new(:user_id, user.id)
        |> Keyword.put_new(:actor_label, user.name || user.email)

      case Repo.delete(comment) do
        {:ok, deleted} ->
          emit_comment_event(deleted, "invoice.comment_deleted", opts)
          {:ok, deleted}

        error ->
          error
      end
    end
  end

  @spec emit_comment_event(InvoiceComment.t(), String.t(), keyword()) :: :ok
  defp emit_comment_event(comment, action, opts) do
    # Look up company_id from the invoice for the event
    case Repo.get(Invoice, comment.invoice_id) do
      %Invoice{} = invoice ->
        case action do
          "invoice.comment_edited" ->
            Events.invoice_comment_edited(
              %{id: invoice.id, company_id: invoice.company_id},
              comment,
              opts
            )

          "invoice.comment_deleted" ->
            Events.invoice_comment_deleted(
              %{id: invoice.id, company_id: invoice.company_id},
              comment.id,
              opts
            )
        end

      nil ->
        :ok
    end
  end

  # --- Access Control ---

  @doc "Lists access grants for an invoice, with user preloaded."
  @spec list_access_grants(Ecto.UUID.t()) :: [InvoiceAccessGrant.t()]
  def list_access_grants(invoice_id) do
    InvoiceAccessGrant
    |> where([g], g.invoice_id == ^invoice_id)
    |> preload(:user)
    |> order_by([g], asc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Grants a user access to a restricted invoice. Idempotent — duplicate grants are silently ignored.

  Validates that the target user is a member of the same company as the invoice
  and does not have full invoice visibility (i.e. is a reviewer, not admin/owner/accountant).
  """
  @spec grant_access(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, InvoiceAccessGrant.t()} | {:error, Ecto.Changeset.t()}
  def grant_access(invoice_id, user_id, granted_by_id \\ nil, opts \\ []) do
    with {:ok, company_id} <- fetch_invoice_company_id(invoice_id),
         {:ok, _membership} <- validate_grantable_member(company_id, user_id) do
      result =
        %InvoiceAccessGrant{}
        |> Ecto.Changeset.change(%{
          invoice_id: invoice_id,
          user_id: user_id,
          granted_by_id: granted_by_id
        })
        |> Ecto.Changeset.unique_constraint([:invoice_id, :user_id])
        |> Ecto.Changeset.foreign_key_constraint(:invoice_id)
        |> Ecto.Changeset.foreign_key_constraint(:user_id)
        |> Ecto.Changeset.foreign_key_constraint(:granted_by_id)
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:invoice_id, :user_id])

      case result do
        {:ok, grant} ->
          invoice_ref = %{id: invoice_id, company_id: company_id}
          Events.invoice_access_granted(invoice_ref, user_id, opts)
          {:ok, grant}

        error ->
          error
      end
    end
  end

  @spec fetch_invoice_company_id(Ecto.UUID.t()) ::
          {:ok, Ecto.UUID.t()} | {:error, Ecto.Changeset.t()}
  defp fetch_invoice_company_id(invoice_id) do
    case Repo.get(Invoice, invoice_id) do
      %Invoice{company_id: cid} -> {:ok, cid}
      nil -> {:error, grant_error(:invoice_id, "invoice not found")}
    end
  end

  @spec validate_grantable_member(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Membership.t()} | {:error, Ecto.Changeset.t()}
  defp validate_grantable_member(company_id, user_id) do
    case Companies.get_membership(user_id, company_id) do
      %Membership{role: role} = m ->
        if full_invoice_visibility?(role),
          do: {:error, grant_error(:user_id, "user already has full access via their role")},
          else: {:ok, m}

      nil ->
        {:error, grant_error(:user_id, "user is not a member of this company")}
    end
  end

  @spec grant_error(atom(), String.t()) :: Ecto.Changeset.t()
  defp grant_error(field, message) do
    %InvoiceAccessGrant{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(field, message)
  end

  @doc "Revokes a user's access to a restricted invoice."
  @spec revoke_access(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, InvoiceAccessGrant.t()} | {:error, :not_found}
  def revoke_access(invoice_id, user_id, opts \\ []) do
    InvoiceAccessGrant
    |> where([g], g.invoice_id == ^invoice_id and g.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      grant ->
        with {:ok, deleted} <- Repo.delete(grant) do
          emit_access_revoked(invoice_id, user_id, opts)
          {:ok, deleted}
        end
    end
  end

  @spec emit_access_revoked(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: :ok
  defp emit_access_revoked(invoice_id, user_id, opts) do
    case Repo.get(Invoice, invoice_id) do
      %Invoice{company_id: company_id} ->
        Events.invoice_access_revoked(%{id: invoice_id, company_id: company_id}, user_id, opts)

      nil ->
        :ok
    end
  end

  @doc """
  Sets the access_restricted flag on an invoice.

  Income invoices cannot be unrestricted — they are always restricted by design
  so reviewers cannot see them unless explicitly granted access.
  """
  @spec set_access_restricted(Invoice.t(), boolean()) ::
          {:ok, Invoice.t()} | {:error, :income_always_restricted | Ecto.Changeset.t()}
  def set_access_restricted(invoice, restricted, opts \\ [])

  def set_access_restricted(%Invoice{type: :income}, false, _opts),
    do: {:error, :income_always_restricted}

  def set_access_restricted(%Invoice{} = invoice, restricted, opts) when is_boolean(restricted) do
    invoice
    |> Ecto.Changeset.change(%{access_restricted: restricted})
    |> TrackedRepo.update(opts)
  end

  # --- Private ---

  @spec fetch_company_category(Ecto.UUID.t(), Ecto.UUID.t()) :: Category.t() | nil
  defp fetch_company_category(company_id, category_id) do
    Category
    |> where([c], c.id == ^category_id and c.company_id == ^company_id)
    |> Repo.one()
  end

  @spec current_category_name(Invoice.t()) :: String.t() | nil
  defp current_category_name(%Invoice{category: %Category{name: name}}), do: name

  defp current_category_name(%Invoice{category_id: id}) when is_binary(id) do
    Category |> where([c], c.id == ^id) |> select([c], c.name) |> Repo.one()
  end

  defp current_category_name(_invoice), do: nil

  @spec build_category_attrs(Ecto.UUID.t(), Category.t()) :: map()
  defp build_category_attrs(category_id, category) do
    attrs = %{category_id: category_id}

    if category.default_cost_line,
      do: Map.put(attrs, :cost_line, category.default_cost_line),
      else: attrs
  end

  @spec format_error_reason(term()) :: String.t()
  defp format_error_reason(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> inspect()
  end

  defp format_error_reason(reason), do: inspect(reason)

  # When a KSeF sync inserts a new invoice, check if a manually uploaded invoice
  # already exists with matching business fields. The KSeF invoice is authoritative,
  # so mark the older manual/PDF invoice as the duplicate (pointing at the new KSeF
  # row). This preserves the KSeF invoice's duplicate_of_id as NULL, which is
  # required by the upsert conflict target and DuplicateDetector.find_original_id/3.
  @spec maybe_mark_business_field_duplicate(Invoice.t(), :inserted | :updated) :: Invoice.t()
  defp maybe_mark_business_field_duplicate(invoice, :updated), do: invoice

  defp maybe_mark_business_field_duplicate(invoice, :inserted) do
    attrs = Map.from_struct(invoice)

    case DuplicateDetector.find_original_id(invoice.company_id, attrs, exclude_id: invoice.id) do
      nil ->
        invoice

      older_id ->
        older_invoice = Repo.get!(Invoice, older_id)
        mark_as_duplicate(older_invoice, invoice.id, skip_emit: true)
        invoice
    end
  end

  # Shared: mark an invoice as a suspected duplicate of another.
  # Returns the updated invoice on success, the original on failure (with a warning log).
  # Pass `skip_emit: true` for system-level operations that should not emit activity events.
  @spec mark_as_duplicate(Invoice.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  defp mark_as_duplicate(invoice, original_id, opts) do
    case invoice
         |> Invoice.duplicate_changeset(%{
           duplicate_of_id: original_id,
           duplicate_status: :suspected
         })
         |> TrackedRepo.update(opts) do
      {:ok, updated} ->
        updated

      {:error, reason} ->
        Logger.warning(
          "Failed to mark invoice #{invoice.id} (company #{invoice.company_id}) " <>
            "as duplicate of #{original_id}: #{format_error_reason(reason)}"
        )

        invoice
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

  @spec full_invoice_visibility?(Membership.role() | nil) :: boolean()
  defp full_invoice_visibility?(nil), do: false
  defp full_invoice_visibility?(role), do: Authorization.can?(role, :view_all_invoice_types)

  @spec maybe_filter_by_access(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  defp maybe_filter_by_access(query, opts) do
    role = opts[:role]
    user_id = opts[:user_id]
    has_role_key = Keyword.has_key?(opts, :role)

    cond do
      # Role with full visibility — no filtering needed
      full_invoice_visibility?(role) ->
        query

      # Role specified with a user_id — filter by access grants
      is_binary(user_id) ->
        where(
          query,
          [i],
          i.access_restricted == false or
            i.id in subquery(
              from(g in InvoiceAccessGrant, where: g.user_id == ^user_id, select: g.invoice_id)
            )
        )

      # Internal/system calls (no role key at all) — no filtering
      not has_role_key ->
        query

      # Any other case — deny restricted invoices as a safety net
      true ->
        where(query, [i], i.access_restricted == false)
    end
  end

  @spec do_list_invoices(Ecto.UUID.t(), map(), pos_integer(), pos_integer(), keyword()) ::
          [Invoice.t()]
  defp do_list_invoices(company_id, filters, page, per_page, opts) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> maybe_filter_by_access(opts)
    |> order_by([i], desc: i.issue_date, desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Query.t()
  defp apply_filters(query, filters) do
    query = apply_status_and_duplicate_filters(query, filters)

    Enum.reduce(filters, query, fn
      {:type, type}, q when type in [:income, :expense] ->
        where(q, [i], i.type == ^type)

      {:status, status}, q when status in [:pending, :approved, :rejected] ->
        where(q, [i], i.status == ^status)

      {:category_ids, ids}, q when is_list(ids) and ids != [] ->
        where(q, [i], i.category_id in ^ids)

      {:payment_statuses, ps}, q when is_list(ps) and ps != [] ->
        apply_payment_status_filter(q, ps)

      {:date_from, %Date{} = date}, q ->
        where(q, [i], i.issue_date >= ^date)

      {:date_to, %Date{} = date}, q ->
        where(q, [i], i.issue_date <= ^date)

      {:billing_date_from, %Date{} = date}, q ->
        where(q, [i], i.billing_date_to >= ^date)

      {:billing_date_to, %Date{} = date}, q ->
        where(q, [i], i.billing_date_from <= ^date)

      {:seller_nip, nip}, q when is_binary(nip) and nip != "" ->
        where(q, [i], i.seller_nip == ^nip)

      {:buyer_nip, nip}, q when is_binary(nip) and nip != "" ->
        where(q, [i], i.buyer_nip == ^nip)

      {:query, search}, q when is_binary(search) and search != "" ->
        apply_text_search(q, search)

      {:source, source}, q when source in [:ksef, :manual, :pdf_upload, :email] ->
        where(q, [i], i.source == ^source)

      {:category_id, category_id}, q when is_binary(category_id) and category_id != "" ->
        where(q, [i], i.category_id == ^category_id)

      {:tags, tags}, q when is_list(tags) and tags != [] ->
        where(q, [i], fragment("? && ?", i.tags, ^tags))

      {:is_excluded, is_excluded}, q when is_boolean(is_excluded) ->
        where(q, [i], i.is_excluded == ^is_excluded)

      _, q ->
        q
    end)
  end

  @spec apply_status_and_duplicate_filters(Ecto.Queryable.t(), map()) :: Ecto.Query.t()
  defp apply_status_and_duplicate_filters(query, filters) do
    statuses = filters[:statuses] || []
    include_duplicates = :duplicate in statuses

    query =
      if include_duplicates do
        query
      else
        where(query, [i], is_nil(i.duplicate_status) or i.duplicate_status != :confirmed)
      end

    real_statuses = Enum.reject(statuses, &(&1 == :duplicate))

    case {real_statuses, include_duplicates} do
      {[], true} ->
        where(query, [i], i.duplicate_status == :confirmed)

      {_, true} ->
        where(query, [i], i.status in ^real_statuses or i.duplicate_status == :confirmed)

      {[_ | _], false} ->
        where(query, [i], i.status in ^real_statuses)

      _ ->
        query
    end
  end

  @spec apply_payment_status_filter(Ecto.Queryable.t(), [String.t()]) :: Ecto.Query.t()
  defp apply_payment_status_filter(query, statuses) do
    has_paid = "paid" in statuses
    has_pending = "pending" in statuses
    has_none = "none" in statuses

    paid_condition =
      if has_paid,
        do:
          dynamic(
            [i],
            fragment(
              "EXISTS (SELECT 1 FROM payment_requests p WHERE p.invoice_id = ? AND p.status = 'paid')",
              i.id
            )
          )

    pending_condition =
      if has_pending,
        do:
          dynamic(
            [i],
            fragment(
              """
              EXISTS (SELECT 1 FROM payment_requests p WHERE p.invoice_id = ? AND p.status != 'voided')
              AND NOT EXISTS (SELECT 1 FROM payment_requests p WHERE p.invoice_id = ? AND p.status = 'paid')
              """,
              i.id,
              i.id
            )
          )

    none_condition =
      if has_none,
        do:
          dynamic(
            [i],
            fragment(
              "NOT EXISTS (SELECT 1 FROM payment_requests p WHERE p.invoice_id = ? AND p.status != 'voided')",
              i.id
            )
          )

    conditions = Enum.reject([paid_condition, pending_condition, none_condition], &is_nil/1)

    case conditions do
      [] ->
        query

      [first | rest] ->
        combined = Enum.reduce(rest, first, fn cond, acc -> dynamic(^acc or ^cond) end)
        where(query, ^combined)
    end
  end

  @spec apply_text_search(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  defp apply_text_search(query, search) do
    escaped =
      search
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%" <> escaped <> "%"

    where(
      query,
      [i],
      fragment("? ILIKE ? ESCAPE '\\'", i.invoice_number, ^pattern) or
        fragment("? ILIKE ? ESCAPE '\\'", i.seller_name, ^pattern) or
        fragment("? ILIKE ? ESCAPE '\\'", i.buyer_name, ^pattern) or
        fragment("? ILIKE ? ESCAPE '\\'", i.purchase_order, ^pattern) or
        fragment("? ILIKE ? ESCAPE '\\'", i.iban, ^pattern) or
        fragment("? ILIKE ? ESCAPE '\\'", i.ksef_number, ^pattern) or
        fragment("CAST(? AS TEXT) ILIKE ? ESCAPE '\\'", i.net_amount, ^pattern) or
        fragment("CAST(? AS TEXT) ILIKE ? ESCAPE '\\'", i.gross_amount, ^pattern)
    )
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
