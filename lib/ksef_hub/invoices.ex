defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices from KSeF sync or manual entry.
  """

  import Ecto.Query

  require Logger

  alias KsefHub.Accounts.User
  alias KsefHub.Companies
  alias KsefHub.Companies.Company
  alias KsefHub.Files
  alias KsefHub.InvoiceClassifier.Worker, as: ClassifierWorker
  alias KsefHub.InvoiceExtractor.ContextBuilder

  alias KsefHub.ActivityLog.Event
  alias KsefHub.ActivityLog.Events
  alias KsefHub.ActivityLog.TrackedRepo

  alias KsefHub.Invoices.{
    AccessControl,
    Analytics,
    AutoApproval,
    Category,
    Classification,
    Comments,
    DuplicateDetector,
    Duplicates,
    Extraction,
    Invoice,
    NipVerifier,
    Queries,
    Reextraction
  }

  alias KsefHub.Repo

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
    {page, per_page} = Queries.extract_pagination(filters)
    Queries.do_list_invoices(company_id, filters, page, per_page, opts)
  end

  @doc """
  Returns the count of invoices for a company matching the given filters.

  Uses the same filter logic as `list_invoices/2` but returns only the count.
  """
  @spec count_invoices(Ecto.UUID.t(), map(), keyword()) :: non_neg_integer()
  def count_invoices(company_id, filters \\ %{}, opts \\ []) do
    Queries.do_count_invoices(company_id, filters, opts)
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
    {page, per_page} = Queries.extract_pagination(filters)

    entries =
      company_id
      |> Queries.do_list_invoices(filters, page, per_page, opts)
      |> Repo.preload([:category])

    total_count = Queries.do_count_invoices(company_id, filters, opts)
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
    |> AccessControl.maybe_filter_by_access(opts)
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with associations preloaded."
  @spec get_invoice_with_details!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def get_invoice_with_details!(company_id, id, opts \\ []) do
    access_query = AccessControl.access_scoped_invoice_query(opts)

    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> AccessControl.maybe_filter_by_access(opts)
    |> preload([
      :xml_file,
      :pdf_file,
      :category,
      :created_by,
      :inbound_email,
      corrects_invoice: ^access_query,
      corrections: ^access_query
    ])
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID with associations preloaded, returning nil if not found."
  @spec get_invoice_with_details(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice_with_details(company_id, id, opts \\ []) do
    access_query = AccessControl.access_scoped_invoice_query(opts)

    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> AccessControl.maybe_filter_by_access(opts)
    |> preload([
      :xml_file,
      :pdf_file,
      :category,
      :created_by,
      :inbound_email,
      corrects_invoice: ^access_query,
      corrections: ^access_query
    ])
    |> Repo.one()
  end

  @doc "Fetches an invoice by UUID scoped to a company, returning nil if not found."
  @spec get_invoice(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> AccessControl.maybe_filter_by_access(opts)
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
  Links correction invoices to their originals by matching `corrected_invoice_ksef_number`
  to `ksef_number` within the same company. Only updates corrections that have
  `corrects_invoice_id` as nil (not yet linked). Idempotent and safe to call after each sync.

  Uses raw SQL for bulk performance. Bypasses Ecto changesets and ActivityLog —
  no `invoice.correction_linked` events are emitted. This is intentional: the
  linking is a bookkeeping step during sync, not a user-visible mutation.
  """
  @spec link_unlinked_corrections(Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def link_unlinked_corrections(company_id) do
    Repo.query!(
      """
      UPDATE invoices AS correction
      SET corrects_invoice_id = original.id, updated_at = NOW()
      FROM invoices AS original
      WHERE correction.company_id = $1
        AND correction.corrected_invoice_ksef_number IS NOT NULL
        AND correction.corrects_invoice_id IS NULL
        AND correction.invoice_kind IN ('correction', 'advance_correction', 'settlement_correction')
        AND original.company_id = $1
        AND original.ksef_number = correction.corrected_invoice_ksef_number
        AND original.duplicate_of_id IS NULL
        AND original.id <> correction.id
      """,
      [Ecto.UUID.dump!(company_id)]
    )
    |> then(fn %{num_rows: n} -> {n, nil} end)
  end

  defdelegate compute_billing_date(attrs), to: Extraction
  defdelegate missing_critical_fields(invoice), to: Extraction
  defdelegate determine_extraction_status_from_attrs(attrs), to: Extraction
  defdelegate populate_company_fields(attrs, company), to: Extraction

  defdelegate recalculate_extraction_status(invoice, attrs), to: Extraction

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

  @doc """
  Creates an invoice.
  """
  @spec create_invoice(map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | term()}
  def create_invoice(attrs, opts \\ []) do
    company_id = attrs[:company_id] || attrs["company_id"]
    {pdf_content, attrs} = Map.pop(attrs, :pdf_content)
    {xml_content, attrs} = Map.pop(attrs, :xml_content)
    attrs = attrs |> Extraction.maybe_default_billing_date() |> maybe_restrict_access()

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
    attrs = attrs |> Extraction.maybe_default_billing_date() |> maybe_restrict_access()

    case do_upsert(company_id, attrs) do
      {:ok, invoice} ->
        action = if invoice.inserted_at == invoice.updated_at, do: :inserted, else: :updated
        if action == :inserted, do: enqueue_prediction(invoice)
        invoice = Duplicates.maybe_mark_business_field_duplicate(invoice, action)
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
    :invoice_kind,
    :corrected_invoice_number,
    :corrected_invoice_ksef_number,
    :corrected_invoice_date,
    :correction_period_from,
    :correction_period_to,
    :correction_reason,
    :correction_type,
    :corrects_invoice_id,
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
      |> Extraction.atomize_known_keys()
      |> Map.take(Invoice.editable_fields(invoice.type))

    changeset = Invoice.edit_changeset(invoice, attrs)

    changeset =
      if old_status do
        critical_changed? =
          Enum.any?(Extraction.critical_extraction_fields(), &Map.has_key?(changeset.changes, &1))

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

  defdelegate reparse_from_stored_xml(invoice, opts \\ []), to: Reextraction
  defdelegate re_extract_invoice(invoice, company, opts \\ []), to: Reextraction

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
        if Duplicates.unique_ksef_number_conflict?(changeset),
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
    extraction_status = Extraction.determine_extraction_status(extracted)

    invoice_attrs =
      Extraction.build_pdf_upload_attrs(
        extracted,
        company.id,
        pdf_binary,
        type,
        filename,
        extraction_status
      )
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

  @doc false
  @spec maybe_enqueue_prediction(atom(), Invoice.t()) :: :ok | :skip | :enqueue_failed
  def maybe_enqueue_prediction(:complete, invoice), do: enqueue_prediction(invoice)
  def maybe_enqueue_prediction(_status, _invoice), do: :ok

  defp verify_nip_for_type(extracted, company_nip, type),
    do: NipVerifier.verify_for_type(extracted, company_nip, type)

  @spec do_insert_invoice(Ecto.UUID.t(), map(), keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_insert_invoice(company_id, attrs, caller_opts) do
    {file_ids, attrs} = pop_file_ids(attrs)
    {created_by_id, attrs} = Map.pop(attrs, :created_by_id)
    {access_restricted, attrs} = Map.pop(attrs, :access_restricted)
    {corrects_invoice_id, attrs} = Map.pop(attrs, :corrects_invoice_id)

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
      |> then(fn m ->
        if corrects_invoice_id, do: Map.put(m, :corrects_invoice_id, corrects_invoice_id), else: m
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
    {corrects_invoice_id, attrs} = Map.pop(attrs, :corrects_invoice_id)

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
      |> then(fn m ->
        if corrects_invoice_id, do: Map.put(m, :corrects_invoice_id, corrects_invoice_id), else: m
      end)

    %Invoice{}
    |> Ecto.Changeset.change(trusted_fields)
    |> Invoice.changeset(attrs)
    |> TrackedRepo.insert(
      [
        on_conflict: {:replace, @upsert_replace_fields},
        conflict_target:
          {:unsafe_fragment,
           ~s|("company_id","ksef_number") WHERE ksef_number IS NOT NULL AND duplicate_of_id IS NULL|},
        returning: true
      ] ++ Event.ksef_sync_opts()
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

  defdelegate confirm_duplicate(invoice), to: Duplicates
  defdelegate confirm_duplicate(invoice, opts), to: Duplicates
  defdelegate dismiss_duplicate(invoice), to: Duplicates
  defdelegate dismiss_duplicate(invoice, opts), to: Duplicates

  @doc """
  Returns invoice counts grouped by type and status for a company.
  """
  @spec count_by_type_and_status(Ecto.UUID.t()) :: %{
          {Invoice.invoice_type(), Invoice.invoice_status()} => non_neg_integer()
        }
  defdelegate count_by_type_and_status(company_id), to: Analytics

  @doc """
  Returns monthly expense totals with proportional allocation for multi-month invoices.

  Invoices spanning multiple months have their net_amount divided equally across each
  month in the range (with rounding remainder assigned to the last month).

  Supports filters: `:category_id`, `:tags`, `:billing_date_from`, `:billing_date_to`.
  Excludes invoices with nil billing_date_from/billing_date_to.
  """
  @spec expense_monthly_totals(Ecto.UUID.t(), map()) :: [map()]
  def expense_monthly_totals(company_id, filters \\ %{}) do
    Analytics.expense_monthly_totals(company_id, filters)
  end

  @doc """
  Returns expense totals grouped by category with proportional multi-month allocation.

  Supports filters: `:tags`, `:billing_date_from`, `:billing_date_to`.
  Excludes invoices with nil billing_date_from/billing_date_to. Uncategorized invoices
  are grouped under `category_name: "Uncategorized"` with `emoji: nil`.
  """
  @spec expense_by_category(Ecto.UUID.t(), map()) :: [map()]
  def expense_by_category(company_id, filters \\ %{}) do
    Analytics.expense_by_category(company_id, filters)
  end

  @doc """
  Returns income summary comparing current month to last month (net amounts).
  Uses billing date range with proportional allocation for multi-month invoices.
  """
  @spec income_monthly_summary(Ecto.UUID.t()) :: map()
  defdelegate income_monthly_summary(company_id), to: Analytics

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

  # --- Classification (tags, categories, cost lines, project tags, predictions) ---

  @doc "Sets the tags on an invoice, replacing any existing tags."
  @spec set_invoice_tags(Invoice.t(), [String.t()], keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def set_invoice_tags(invoice, tags, opts \\ []),
    do: Classification.set_invoice_tags(invoice, tags, opts)

  defdelegate add_invoice_tag(invoice, tag_name), to: Classification

  @doc """
  Lists distinct tag values used on invoices for a company,
  optionally filtered by invoice type. Ordered by most recently used.
  """
  @spec list_distinct_tags(Ecto.UUID.t(), atom() | nil, keyword()) :: [String.t()]
  def list_distinct_tags(company_id, type \\ nil, opts \\ []),
    do: Classification.list_distinct_tags(company_id, type, opts)

  @doc """
  Assigns or clears a category on an invoice.

  Categories are expense-only — returns `{:error, :expense_only}` for income invoices.
  When `category_id` is not nil, verifies the category belongs to the same
  company as the invoice before updating.
  """
  @spec set_invoice_category(Invoice.t(), Ecto.UUID.t() | nil, keyword()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t() | :category_not_in_company | :expense_only}
  def set_invoice_category(invoice, category_id, opts \\ []),
    do: Classification.set_invoice_category(invoice, category_id, opts)

  @doc """
  Sets the cost line on an expense invoice independently of category.

  Returns `{:error, :expense_only}` for income invoices.
  """
  @spec set_invoice_cost_line(Invoice.t(), atom() | nil, keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :expense_only}
  def set_invoice_cost_line(invoice, cost_line, opts \\ []),
    do: Classification.set_invoice_cost_line(invoice, cost_line, opts)

  @doc """
  Sets the project tag on an invoice. Works for both income and expense invoices.

  Pass `nil` to clear the project tag.
  """
  @spec set_invoice_project_tag(Invoice.t(), String.t() | nil, keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def set_invoice_project_tag(invoice, project_tag, opts \\ []),
    do: Classification.set_invoice_project_tag(invoice, project_tag, opts)

  defdelegate list_project_tags(company_id), to: Classification
  defdelegate mark_prediction_manual(invoice), to: Classification
  defdelegate with_manual_prediction(invoice, fun), to: Classification

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

  defdelegate list_invoice_comments(company_id, invoice_id), to: Comments
  defdelegate create_invoice_comment(company_id, invoice_id, user_id, attrs), to: Comments
  defdelegate create_invoice_comment(company_id, invoice_id, user_id, attrs, opts), to: Comments
  defdelegate update_invoice_comment(comment, user, attrs), to: Comments
  defdelegate update_invoice_comment(comment, user, attrs, opts), to: Comments
  defdelegate delete_invoice_comment(comment, user), to: Comments
  defdelegate delete_invoice_comment(comment, user, opts), to: Comments

  # --- Access Control ---

  defdelegate list_access_grants(invoice_id), to: AccessControl
  defdelegate grant_access(invoice_id, user_id), to: AccessControl
  defdelegate grant_access(invoice_id, user_id, granted_by_id), to: AccessControl
  defdelegate grant_access(invoice_id, user_id, granted_by_id, opts), to: AccessControl
  defdelegate revoke_access(invoice_id, user_id), to: AccessControl
  defdelegate revoke_access(invoice_id, user_id, opts), to: AccessControl
  defdelegate set_access_restricted(invoice, restricted), to: AccessControl
  defdelegate set_access_restricted(invoice, restricted, opts), to: AccessControl

  # --- Private ---

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
