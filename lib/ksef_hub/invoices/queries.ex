defmodule KsefHub.Invoices.Queries do
  @moduledoc """
  Query builders for the Invoices context.

  Provides filtering, pagination, text search, and ordering logic used by
  `KsefHub.Invoices` list/count operations. Functions here are internal API —
  callers should go through the `KsefHub.Invoices` facade.
  """

  import Ecto.Query

  alias KsefHub.Invoices.{AccessControl, Invoice}
  alias KsefHub.Repo

  @max_per_page 100
  @default_per_page 25

  @doc false
  @spec do_list_invoices(Ecto.UUID.t(), map(), pos_integer(), pos_integer(), keyword()) ::
          [Invoice.t()]
  def do_list_invoices(company_id, filters, page, per_page, opts) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> AccessControl.maybe_filter_by_access(opts)
    |> order_by([i], desc: i.issue_date, desc: i.inserted_at)
    |> limit(^per_page)
    |> offset(^((page - 1) * per_page))
    |> Repo.all()
  end

  @doc false
  @spec do_count_invoices(Ecto.UUID.t(), map(), keyword()) :: non_neg_integer()
  def do_count_invoices(company_id, filters, opts) do
    Invoice
    |> where([i], i.company_id == ^company_id)
    |> apply_filters(filters)
    |> AccessControl.maybe_filter_by_access(opts)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  @doc false
  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Query.t()
  def apply_filters(query, filters) do
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

      {:invoice_kind, kind}, q when is_atom(kind) ->
        where(q, [i], i.invoice_kind == ^kind)

      {:is_correction, true}, q ->
        where(q, [i], i.invoice_kind in ^Invoice.correction_kinds())

      {:is_correction, false}, q ->
        where(q, [i], i.invoice_kind not in ^Invoice.correction_kinds())

      _, q ->
        q
    end)
  end

  @doc false
  @spec extract_pagination(map()) :: {pos_integer(), pos_integer()}
  def extract_pagination(filters) do
    page = filters |> Map.get(:page, 1) |> clamp(1, 1_000_000)
    per_page = filters |> Map.get(:per_page, @default_per_page) |> clamp(1, @max_per_page)
    {page, per_page}
  end

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

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

  @spec clamp(term(), integer(), integer()) :: integer()
  defp clamp(value, min_val, max_val) when is_integer(value) do
    value |> max(min_val) |> min(max_val)
  end

  defp clamp(_, min_val, _max_val), do: min_val
end
