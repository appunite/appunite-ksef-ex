defmodule KsefHub.Invoices do
  @moduledoc """
  The Invoices context. Manages income and expense invoices synced from KSeF.
  """

  import Ecto.Query
  alias KsefHub.Repo
  alias KsefHub.Invoices.Invoice

  @doc """
  Returns a list of invoices matching the given filters.

  ## Filters
    * `:type` - "income" or "expense"
    * `:status` - "pending", "approved", or "rejected"
    * `:date_from` - earliest issue_date (inclusive)
    * `:date_to` - latest issue_date (inclusive)
    * `:seller_nip` - filter by seller NIP
    * `:buyer_nip` - filter by buyer NIP
    * `:query` - search across invoice_number, seller_name, buyer_name
  """
  @spec list_invoices(map()) :: [Invoice.t()]
  def list_invoices(filters \\ %{}) do
    Invoice
    |> apply_filters(filters)
    |> order_by([i], desc: i.issue_date, desc: i.inserted_at)
    |> Repo.all()
  end

  @spec get_invoice!(Ecto.UUID.t()) :: Invoice.t()
  def get_invoice!(id), do: Repo.get!(Invoice, id)

  @spec get_invoice(Ecto.UUID.t()) :: Invoice.t() | nil
  def get_invoice(id), do: Repo.get(Invoice, id)

  @spec get_invoice_by_ksef_number(String.t()) :: Invoice.t() | nil
  def get_invoice_by_ksef_number(ksef_number) do
    Repo.get_by(Invoice, ksef_number: ksef_number)
  end

  @doc """
  Creates an invoice.
  """
  @spec create_invoice(map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def create_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Upserts an invoice by ksef_number. Used during sync to avoid duplicates.
  """
  @spec upsert_invoice(map()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()}
  def upsert_invoice(attrs) do
    %Invoice{}
    |> Invoice.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [
        :xml_content, :seller_nip, :seller_name, :buyer_nip, :buyer_name,
        :invoice_number, :issue_date, :net_amount, :vat_amount, :gross_amount,
        :currency, :ksef_acquisition_date, :permanent_storage_date, :updated_at
      ]},
      conflict_target: :ksef_number,
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
  @spec approve_invoice(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()} | {:error, {:invalid_type, String.t()}}
  def approve_invoice(%Invoice{type: "expense"} = invoice) do
    update_invoice(invoice, %{status: "approved"})
  end

  def approve_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Rejects an expense invoice.
  """
  @spec reject_invoice(Invoice.t()) :: {:ok, Invoice.t()} | {:error, Ecto.Changeset.t()} | {:error, {:invalid_type, String.t()}}
  def reject_invoice(%Invoice{type: "expense"} = invoice) do
    update_invoice(invoice, %{status: "rejected"})
  end

  def reject_invoice(%Invoice{type: type}), do: {:error, {:invalid_type, type}}

  @doc """
  Returns invoice counts grouped by type and status.
  """
  @spec count_by_type_and_status() :: %{{String.t(), String.t()} => non_neg_integer()}
  def count_by_type_and_status do
    Invoice
    |> group_by([i], [i.type, i.status])
    |> select([i], {i.type, i.status, count(i.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {type, status, count}, acc ->
      Map.put(acc, {type, status}, count)
    end)
  end

  # --- Private ---

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
        escaped = search |> String.replace("\\", "\\\\") |> String.replace("%", "\\%") |> String.replace("_", "\\_")
        pattern = "%" <> escaped <> "%"
        where(q, [i],
          fragment("? ILIKE ? ESCAPE '\\'", i.invoice_number, ^pattern) or
          fragment("? ILIKE ? ESCAPE '\\'", i.seller_name, ^pattern) or
          fragment("? ILIKE ? ESCAPE '\\'", i.buyer_name, ^pattern)
        )

      _, q ->
        q
    end)
  end
end
