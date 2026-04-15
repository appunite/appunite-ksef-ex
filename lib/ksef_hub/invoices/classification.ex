defmodule KsefHub.Invoices.Classification do
  @moduledoc """
  Classification, categorization, and tagging for invoices.

  Manages invoice category assignment (with cost-line auto-population),
  free-form tags, project tags, and ML-prediction status tracking.

  This module is used internally by `KsefHub.Invoices` — the public API facade
  delegates to the functions here.
  """

  import Ecto.Query

  alias KsefHub.ActivityLog.TrackedRepo
  alias KsefHub.Invoices.{AccessControl, Category, Invoice}
  alias KsefHub.Repo

  # -------------------------------------------------------------------
  # Tags
  # -------------------------------------------------------------------

  @doc "Sets the tags on an invoice, replacing any existing tags."
  @spec set_invoice_tags(Invoice.t(), [String.t()], keyword()) ::
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
      |> AccessControl.maybe_filter_by_access(opts)

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

  # -------------------------------------------------------------------
  # Invoice-Category Assignment
  # -------------------------------------------------------------------

  @doc """
  Assigns or clears a category on an invoice.

  Categories are expense-only — returns `{:error, :expense_only}` for income invoices.
  When `category_id` is not nil, verifies the category belongs to the same
  company as the invoice before updating.
  """
  @spec set_invoice_category(Invoice.t(), Ecto.UUID.t() | nil, keyword()) ::
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

  # -------------------------------------------------------------------
  # Cost Line
  # -------------------------------------------------------------------

  @doc """
  Sets the cost line on an expense invoice independently of category.

  Returns `{:error, :expense_only}` for income invoices.
  """
  @spec set_invoice_cost_line(Invoice.t(), atom() | nil, keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t() | :expense_only}
  def set_invoice_cost_line(invoice, cost_line, opts \\ [])

  def set_invoice_cost_line(%Invoice{type: :income}, _cost_line, _opts),
    do: {:error, :expense_only}

  def set_invoice_cost_line(%Invoice{} = invoice, cost_line, opts) do
    invoice
    |> Invoice.category_changeset(%{cost_line: cost_line})
    |> TrackedRepo.update(opts)
  end

  # -------------------------------------------------------------------
  # Project Tags
  # -------------------------------------------------------------------

  @doc """
  Sets the project tag on an invoice. Works for both income and expense invoices.

  Pass `nil` to clear the project tag.
  """
  @spec set_invoice_project_tag(Invoice.t(), String.t() | nil, keyword()) ::
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

  # -------------------------------------------------------------------
  # Prediction Status
  # -------------------------------------------------------------------

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

  # -------------------------------------------------------------------
  # Private Helpers
  # -------------------------------------------------------------------

  @spec do_set_invoice_tags(Invoice.t(), [String.t()], keyword()) ::
          {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  defp do_set_invoice_tags(invoice, tags, opts) do
    normalized = tags |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    invoice
    |> Invoice.tags_changeset(%{tags: normalized})
    |> TrackedRepo.update(opts)
  end

  @spec fetch_company_category(Ecto.UUID.t(), Ecto.UUID.t()) :: Category.t() | nil
  defp fetch_company_category(company_id, category_id) do
    Category
    |> where([c], c.id == ^category_id and c.company_id == ^company_id)
    |> Repo.one()
  end

  @spec current_category_name(Invoice.t()) :: String.t() | nil
  defp current_category_name(%Invoice{category: %Category{name: name}}), do: name

  defp current_category_name(%Invoice{category_id: id} = invoice) when is_binary(id) do
    if Ecto.assoc_loaded?(invoice.category) do
      nil
    else
      Category |> where([c], c.id == ^id) |> select([c], c.name) |> Repo.one()
    end
  end

  defp current_category_name(_invoice), do: nil

  @spec build_category_attrs(Ecto.UUID.t(), Category.t()) :: map()
  defp build_category_attrs(category_id, category) do
    attrs = %{category_id: category_id}

    if category.default_cost_line,
      do: Map.put(attrs, :cost_line, category.default_cost_line),
      else: attrs
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
end
