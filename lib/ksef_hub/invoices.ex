defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices from KSeF sync or manual entry.
  """

  import Ecto.Query

  alias KsefHub.Invoices.{Category, Invoice, InvoiceTag, Tag}
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
    * `:source` - "ksef" or "manual"
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

  @doc "Fetches an invoice by UUID with category and tags preloaded."
  @spec get_invoice_with_details!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: Invoice.t()
  def get_invoice_with_details!(company_id, id, opts \\ []) do
    Invoice
    |> where([i], i.company_id == ^company_id and i.id == ^id)
    |> maybe_scope_type_by_role(opts[:role])
    |> preload([:category, :tags])
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
    :source,
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
      # Ecto's conflict_target doesn't support partial index WHERE clauses natively,
      # so we use {:unsafe_fragment, ...}. The fragment is a static string (no interpolation),
      # so there is no SQL injection risk. It must match the partial unique index definition.
      conflict_target:
        {:unsafe_fragment,
         ~s|("company_id","ksef_number") WHERE ksef_number IS NOT NULL AND duplicate_of_id IS NULL|},
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

    case create_invoice(attrs) do
      {:ok, _invoice} = success ->
        success

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_ksef_number_conflict?(changeset) do
          attrs
          |> Map.merge(%{
            duplicate_of_id: find_original_id(company_id, attrs),
            duplicate_status: "suspected"
          })
          |> create_invoice()
        else
          {:error, changeset}
        end
    end
  end

  @doc """
  Confirms a suspected duplicate invoice.

  Only valid when `duplicate_of_id` is set and `duplicate_status` is `"suspected"`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not `"suspected"`.
  """
  @spec confirm_duplicate(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def confirm_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def confirm_duplicate(%Invoice{duplicate_status: "suspected"} = invoice) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: "confirmed"})
    |> Repo.update()
  end

  def confirm_duplicate(%Invoice{}), do: {:error, :invalid_status}

  @doc """
  Dismisses a duplicate invoice.

  Valid when `duplicate_of_id` is set and `duplicate_status` is `"suspected"` or `"confirmed"`.
  Returns `{:error, :not_a_duplicate}` when no duplicate_of_id is set,
  or `{:error, :invalid_status}` when duplicate_status is not dismissable.
  """
  @spec dismiss_duplicate(Invoice.t()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :not_a_duplicate | :invalid_status}
  def dismiss_duplicate(%Invoice{duplicate_of_id: nil}), do: {:error, :not_a_duplicate}

  def dismiss_duplicate(%Invoice{duplicate_status: status} = invoice)
      when status in ~w(suspected confirmed) do
    invoice
    |> Invoice.duplicate_changeset(%{duplicate_status: "dismissed"})
    |> Repo.update()
  end

  def dismiss_duplicate(%Invoice{}), do: {:error, :invalid_status}

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

  @doc "Assigns or clears a category on an invoice."
  @spec set_invoice_category(Invoice.t(), Ecto.UUID.t() | nil) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def set_invoice_category(%Invoice{} = invoice, category_id) do
    invoice
    |> Invoice.category_changeset(%{category_id: category_id})
    |> Repo.update()
  end

  # --- Invoice-Tag Associations ---

  @doc "Adds a tag to an invoice."
  @spec add_invoice_tag(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, InvoiceTag.t()} | {:error, Ecto.Changeset.t()}
  def add_invoice_tag(invoice_id, tag_id) do
    invoice_id
    |> InvoiceTag.changeset(tag_id)
    |> Repo.insert()
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
    Repo.transaction(fn ->
      InvoiceTag
      |> where([it], it.invoice_id == ^invoice_id)
      |> Repo.delete_all()

      Enum.each(tag_ids, &insert_invoice_tag!(invoice_id, &1))
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
        Map.merge(attrs, %{duplicate_of_id: original_id, duplicate_status: "suspected"})
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
end
