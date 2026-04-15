defmodule KsefHub.Invoices.Analytics do
  @moduledoc """
  Analytics and aggregation queries for invoices.

  Provides invoice counting, monthly expense/income totals, and category-based
  breakdowns with proportional multi-month allocation. Invoices spanning multiple
  months have their net_amount divided equally across each month in the range
  (with rounding remainder assigned to the last month).

  This module is used internally by `KsefHub.Invoices` — the public API facade
  delegates to the functions here.
  """

  import Ecto.Query

  alias KsefHub.Invoices.{Category, Invoice, Queries}
  alias KsefHub.Repo

  # -------------------------------------------------------------------
  # Public API
  # -------------------------------------------------------------------

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
    |> Queries.apply_filters(filters)
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
    |> Queries.apply_filters(filters)
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
    current_month_end = Date.end_of_month(today)
    last_month_start = current_month_start |> Date.add(-1) |> Date.beginning_of_month()

    # Fetch invoices whose billing range overlaps either month
    invoices =
      company_id
      |> base_aggregation_query(:income)
      |> where(
        [i],
        i.billing_date_to >= ^last_month_start and i.billing_date_from <= ^current_month_end
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

  # -------------------------------------------------------------------
  # Private helpers
  # -------------------------------------------------------------------

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
    start_month = Date.beginning_of_month(from)
    end_month = Date.beginning_of_month(to)
    months = months_between(start_month, end_month)
    count = length(months)

    if count <= 1 do
      [{start_month, net_amount}]
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
end
