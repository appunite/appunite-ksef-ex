defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices from KSeF sync or manual entry.
  """

  import Ecto.Query

  alias KsefHub.Invoices.Invoice
  alias KsefHub.Repo

  @list_fields Invoice.__schema__(:fields) -- [:xml_content]
  @max_per_page 100
  @default_per_page 25

  @doc """
  Returns a list of invoices for a company matching the given filters.

  Excludes `xml_content` from results for performance. Supports pagination
  via `:page` (1-based, default 1) and `:per_page` (default 25, max 100).

  ## Filters
    * `:type` - "income" or "expense"
    * `:status` - "pending", "approved", or "rejected"
    * `:date_from` - earliest issue_date (inclusive)
    * `:date_to` - latest issue_date (inclusive)
    * `:seller_nip` - filter by seller NIP
    * `:buyer_nip` - filter by buyer NIP
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

    entries = do_list_invoices(company_id, filters, page, per_page)
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
    |> Repo.one!()
  end

  @doc "Fetches an invoice by UUID scoped to a company, returning nil if not found."
  @spec get_invoice(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t() | nil
  def get_invoice(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
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

    %Invoice{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Invoice.changeset(attrs)
    |> Repo.insert()
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
        {:ok, invoice, action}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @upsert_replace_fields [
    :xml_content,
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
    :updated_at
  ]

  @spec do_upsert(Ecto.UUID.t(), map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_upsert(company_id, attrs) do
    %Invoice{}
    |> Ecto.Changeset.change(%{company_id: company_id})
    |> Invoice.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, @upsert_replace_fields},
      conflict_target: {:unsafe_fragment, ~s|("company_id","ksef_number") WHERE ksef_number IS NOT NULL AND duplicate_of_id IS NULL|},
      returning: true
    )
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
  Approves an expense invoice.
  """
  @spec approve_invoice(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:invalid_type, String.t()}}
  def approve_invoice(%Invoice{type: "expense"} = invoice) do
    update_invoice(invoice, %{status: "approved"})
  end

  def approve_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Rejects an expense invoice.
  """
  @spec reject_invoice(Invoice.t()) ::
          {:ok, Invoice.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:invalid_type, String.t()}}
  def reject_invoice(%Invoice{type: "expense"} = invoice) do
    update_invoice(invoice, %{status: "rejected"})
  end

  def reject_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Creates a manual invoice, optionally detecting duplicates by ksef_number.

  Forces `source: "manual"` and strips KSeF-only fields. If a `ksef_number` is
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
      |> Map.merge(%{source: "manual", company_id: company_id})

    attrs = detect_duplicate(company_id, attrs)
    create_invoice(attrs)
  end

  @doc """
  Confirms a suspected duplicate invoice.

  Only valid when `duplicate_of_id` is set and `duplicate_status` is `"suspected"`.
  """
  @spec confirm_duplicate(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate}
  def confirm_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def confirm_duplicate(%Invoice{} = invoice) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: "confirmed"})
    |> Repo.update()
  end

  @doc """
  Dismisses a suspected duplicate invoice.

  Only valid when `duplicate_of_id` is set. Sets `duplicate_status` to `"dismissed"`.
  """
  @spec dismiss_duplicate(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate}
  def dismiss_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def dismiss_duplicate(%Invoice{} = invoice) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: "dismissed"})
    |> Repo.update()
  end

  @doc """
  Returns invoice counts grouped by type and status for a company.
  """
  @spec count_by_type_and_status(Ecto.UUID.t()) :: %{
          {String.t(), String.t()} => non_neg_integer()
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

  # --- Private ---

  @spec detect_duplicate(Ecto.UUID.t(), map()) :: map()
  defp detect_duplicate(company_id, attrs) do
    ksef_number = attrs[:ksef_number] || attrs["ksef_number"]

    if ksef_number && ksef_number != "" do
      existing =
        Invoice
        |> where([i], i.company_id == ^company_id and i.ksef_number == ^ksef_number)
        |> where([i], is_nil(i.duplicate_of_id))
        |> Repo.one()

      if existing do
        Map.merge(attrs, %{duplicate_of_id: existing.id, duplicate_status: "suspected"})
      else
        attrs
      end
    else
      attrs
    end
  end

  @spec scope_by_role(map(), String.t() | nil) :: map()
  defp scope_by_role(filters, "reviewer"), do: Map.put(filters, :type, "expense")
  defp scope_by_role(filters, _role), do: filters

  @spec maybe_scope_type_by_role(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Query.t()
  defp maybe_scope_type_by_role(query, "reviewer"), do: where(query, [i], i.type == "expense")
  defp maybe_scope_type_by_role(query, _role), do: query

  @spec do_list_invoices(Ecto.UUID.t(), map(), pos_integer(), pos_integer()) :: [Invoice.t()]
  defp do_list_invoices(company_id, filters, page, per_page) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> order_by([i], desc: i.issue_date, desc: i.inserted_at)
    |> select([i], struct(i, ^@list_fields))
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Query.t()
  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:type, type}, q when type in ~w(income expense) ->
        where(q, [i], i.type == ^type)

      {:status, status}, q when status in ~w(pending approved rejected) ->
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

      {:source, source}, q when source in ~w(ksef manual) ->
        where(q, [i], i.source == ^source)

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
end
