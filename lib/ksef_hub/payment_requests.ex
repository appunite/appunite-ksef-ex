defmodule KsefHub.PaymentRequests do
  @moduledoc """
  The PaymentRequests context. Manages payment requests (wire transfer instructions)
  for invoices and standalone payments.
  """

  import Ecto.Query

  alias KsefHub.Invoices.Invoice
  alias KsefHub.PaymentRequests.{CsvBuilder, CsvDownload, PaymentRequest}
  alias KsefHub.Repo

  @max_per_page 100
  @default_per_page 25

  # --- List & Paginate ---

  @doc """
  Returns a paginated list of payment requests for a company.

  ## Filters
    * `:status` - `:pending` or `:paid`
    * `:date_from` - earliest inserted_at date (inclusive)
    * `:date_to` - latest inserted_at date (inclusive)
    * `:query` - search across recipient_name, title, iban
    * `:page` - page number (1-based, default 1)
    * `:per_page` - results per page (default 25, max 100)
  """
  @spec list_payment_requests(Ecto.UUID.t(), map()) :: [PaymentRequest.t()]
  def list_payment_requests(company_id, filters \\ %{}) do
    {page, per_page} = extract_pagination(filters)

    PaymentRequest
    |> where([p], p.company_id == ^company_id)
    |> apply_filters(filters)
    |> order_by([p], desc: p.inserted_at)
    |> offset(^((page - 1) * per_page))
    |> limit(^per_page)
    |> preload(:invoice)
    |> Repo.all()
  end

  @doc "Returns a paginated result map with entries and metadata."
  @spec list_payment_requests_paginated(Ecto.UUID.t(), map()) :: %{
          entries: [PaymentRequest.t()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
        }
  def list_payment_requests_paginated(company_id, filters \\ %{}) do
    {page, per_page} = extract_pagination(filters)
    entries = list_payment_requests(company_id, filters)
    total_count = count_payment_requests(company_id, filters)
    total_pages = max(ceil(total_count / per_page), 1)

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @spec count_payment_requests(Ecto.UUID.t(), map()) :: non_neg_integer()
  defp count_payment_requests(company_id, filters) do
    PaymentRequest
    |> where([p], p.company_id == ^company_id)
    |> apply_filters(filters)
    |> Repo.aggregate(:count)
  end

  # --- Get ---

  @doc "Fetches a single payment request scoped to a company."
  @spec get_payment_request!(Ecto.UUID.t(), Ecto.UUID.t()) :: PaymentRequest.t()
  def get_payment_request!(company_id, id) do
    PaymentRequest
    |> where([p], p.company_id == ^company_id and p.id == ^id)
    |> preload(:invoice)
    |> Repo.one!()
  end

  @doc "Fetches a single payment request, returns nil if not found."
  @spec get_payment_request(Ecto.UUID.t(), Ecto.UUID.t()) :: PaymentRequest.t() | nil
  def get_payment_request(company_id, id) do
    PaymentRequest
    |> where([p], p.company_id == ^company_id and p.id == ^id)
    |> preload(:invoice)
    |> Repo.one()
  end

  # --- Create ---

  @doc "Creates a new payment request."
  @spec create_payment_request(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, PaymentRequest.t()} | {:error, Ecto.Changeset.t()}
  def create_payment_request(company_id, user_id, attrs) do
    %PaymentRequest{}
    |> PaymentRequest.changeset(
      attrs
      |> Map.put(:company_id, company_id)
      |> Map.put(:created_by_id, user_id)
    )
    |> Repo.insert()
  end

  # --- Pre-fill from invoice ---

  @doc """
  Returns attribute map pre-filled from an invoice.

  For expense invoices the recipient is the seller; for income the recipient is the buyer.
  """
  @spec prefill_attrs_from_invoice(Invoice.t()) :: map()
  def prefill_attrs_from_invoice(%Invoice{type: :expense} = invoice) do
    %{
      recipient_name: invoice.seller_name || "",
      recipient_address: invoice.seller_address,
      amount: invoice.gross_amount,
      currency: invoice.currency || "PLN",
      title: "Invoice #{invoice.invoice_number}",
      iban: invoice.iban || "",
      invoice_id: invoice.id
    }
  end

  def prefill_attrs_from_invoice(%Invoice{type: :income} = invoice) do
    %{
      recipient_name: invoice.buyer_name || "",
      recipient_address: invoice.buyer_address,
      amount: invoice.gross_amount,
      currency: invoice.currency || "PLN",
      title: "Invoice #{invoice.invoice_number}",
      iban: "",
      invoice_id: invoice.id
    }
  end

  def prefill_attrs_from_invoice(_invoice), do: %{}

  # --- Mark as paid ---

  @doc "Marks a single payment request as paid."
  @spec mark_as_paid(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, PaymentRequest.t()} | {:error, :not_found | :already_paid}
  def mark_as_paid(company_id, id) do
    case get_payment_request(company_id, id) do
      nil -> {:error, :not_found}
      %{status: :paid} = pr -> {:ok, pr}
      pr -> pr |> PaymentRequest.mark_paid_changeset() |> Repo.update()
    end
  end

  @doc "Marks multiple payment requests as paid. Returns the number of updated records."
  @spec mark_many_as_paid(Ecto.UUID.t(), [Ecto.UUID.t()]) :: {non_neg_integer(), nil}
  def mark_many_as_paid(company_id, ids) when is_list(ids) do
    PaymentRequest
    |> where([p], p.company_id == ^company_id and p.id in ^ids and p.status == :pending)
    |> Repo.update_all(set: [status: :paid, updated_at: DateTime.utc_now()])
  end

  # --- CSV ---

  @doc "Builds CSV binary from a list of payment requests. Delegates to CsvBuilder."
  @spec build_csv([PaymentRequest.t()]) :: binary()
  def build_csv(payment_requests) do
    CsvBuilder.build(payment_requests)
  end

  @doc "Records a CSV download event."
  @spec record_csv_download(Ecto.UUID.t(), Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, CsvDownload.t()} | {:error, Ecto.Changeset.t()}
  def record_csv_download(company_id, user_id, pr_ids) do
    %CsvDownload{
      payment_request_ids: pr_ids,
      downloaded_at: DateTime.utc_now(),
      user_id: user_id,
      company_id: company_id
    }
    |> Repo.insert()
  end

  # --- Payment status for invoices ---

  @doc """
  Returns the payment status for a single invoice.

  Returns `:paid` if any linked payment request is paid, `:pending` if all are pending,
  or `nil` if there are no payment requests.
  """
  @spec payment_status_for_invoice(Ecto.UUID.t()) :: :paid | :pending | nil
  def payment_status_for_invoice(invoice_id) do
    statuses =
      PaymentRequest
      |> where([p], p.invoice_id == ^invoice_id)
      |> select([p], p.status)
      |> Repo.all()

    cond do
      statuses == [] -> nil
      :paid in statuses -> :paid
      true -> :pending
    end
  end

  @doc """
  Returns a map of invoice_id => payment status for a list of invoice IDs.

  Status is `:paid` if any linked PR is paid, `:pending` otherwise.
  """
  @spec payment_statuses_for_invoices([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => :paid | :pending}
  def payment_statuses_for_invoices([]), do: %{}

  def payment_statuses_for_invoices(invoice_ids) do
    PaymentRequest
    |> where([p], p.invoice_id in ^invoice_ids)
    |> group_by([p], p.invoice_id)
    |> select([p], {p.invoice_id, fragment("bool_or(? = 'paid')", p.status)})
    |> Repo.all()
    |> Map.new(fn {id, has_paid} ->
      {id, if(has_paid, do: :paid, else: :pending)}
    end)
  end

  # --- Fetch by IDs (for CSV download) ---

  @doc "Fetches payment requests by IDs, scoped to a company."
  @spec get_payment_requests_by_ids(Ecto.UUID.t(), [Ecto.UUID.t()]) :: [PaymentRequest.t()]
  def get_payment_requests_by_ids(company_id, ids) when is_list(ids) do
    PaymentRequest
    |> where([p], p.company_id == ^company_id and p.id in ^ids)
    |> Repo.all()
  end

  # --- Private ---

  @spec extract_pagination(map()) :: {pos_integer(), pos_integer()}
  defp extract_pagination(filters) do
    page = max((filters[:page] || 1) |> to_integer(), 1)

    per_page =
      min(max((filters[:per_page] || @default_per_page) |> to_integer(), 1), @max_per_page)

    {page, per_page}
  end

  @spec to_integer(integer()) :: integer()
  defp to_integer(v) when is_integer(v), do: v
  defp to_integer(v) when is_binary(v), do: String.to_integer(v)
  defp to_integer(_), do: 1

  @spec apply_filters(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp apply_filters(query, filters) do
    query
    |> filter_by_status(filters[:status])
    |> filter_by_date_from(filters[:date_from])
    |> filter_by_date_to(filters[:date_to])
    |> filter_by_query(filters[:query])
  end

  @spec filter_by_status(Ecto.Queryable.t(), atom() | nil) :: Ecto.Queryable.t()
  defp filter_by_status(query, nil), do: query
  defp filter_by_status(query, status), do: where(query, [p], p.status == ^status)

  @spec filter_by_date_from(Ecto.Queryable.t(), Date.t() | nil) :: Ecto.Queryable.t()
  defp filter_by_date_from(query, nil), do: query

  defp filter_by_date_from(query, date) do
    datetime = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    where(query, [p], p.inserted_at >= ^datetime)
  end

  @spec filter_by_date_to(Ecto.Queryable.t(), Date.t() | nil) :: Ecto.Queryable.t()
  defp filter_by_date_to(query, nil), do: query

  defp filter_by_date_to(query, date) do
    datetime = DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
    where(query, [p], p.inserted_at < ^datetime)
  end

  @spec filter_by_query(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp filter_by_query(query, nil), do: query
  defp filter_by_query(query, ""), do: query

  defp filter_by_query(query, term) do
    like_term = "%#{term}%"

    where(
      query,
      [p],
      ilike(p.recipient_name, ^like_term) or ilike(p.title, ^like_term) or
        ilike(p.iban, ^like_term)
    )
  end
end
