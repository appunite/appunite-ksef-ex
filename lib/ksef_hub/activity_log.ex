defmodule KsefHub.ActivityLog do
  @moduledoc """
  Query context for the activity log. Provides read-only functions for
  listing activity entries scoped to invoices or companies.
  """

  import Ecto.Query

  alias KsefHub.AuditLog
  alias KsefHub.Repo

  @max_per_page 100
  @default_per_page 50

  @doc """
  Lists activity log entries for a specific invoice, ordered by newest first.

  ## Options
    * `:limit` — max entries to return (default 50, max 100)
  """
  @spec list_for_invoice(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: [AuditLog.t()]
  def list_for_invoice(company_id, invoice_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_per_page) |> max(1) |> min(@max_per_page)

    AuditLog
    |> where([a], a.company_id == ^company_id)
    |> where([a], a.resource_type == "invoice" and a.resource_id == ^invoice_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Lists activity log entries for a company (platform-level), paginated.

  ## Options
    * `:page` — page number (default 1)
    * `:per_page` — entries per page (default 50, max 100)
    * `:action_prefix` — filter by action prefix (e.g., "invoice", "team")
    * `:resource_type` — filter by resource type
  """
  @spec list_for_company(Ecto.UUID.t(), keyword()) :: %{
          entries: [AuditLog.t()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: non_neg_integer()
          # total_pages is 0 when total_count is 0
        }
  def list_for_company(company_id, opts \\ []) do
    page = max(Keyword.get(opts, :page, 1), 1)
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> max(1) |> min(@max_per_page)

    base_query =
      AuditLog
      |> where([a], a.company_id == ^company_id)
      |> maybe_filter_action_prefix(Keyword.get(opts, :action_prefix))
      |> maybe_filter_resource_type(Keyword.get(opts, :resource_type))

    total_count = Repo.aggregate(base_query, :count)
    total_pages = if(total_count == 0, do: 0, else: ceil(total_count / per_page))

    entries =
      base_query
      |> order_by([a], desc: a.inserted_at)
      |> offset(^((page - 1) * per_page))
      |> limit(^per_page)
      |> Repo.all()

    %{
      entries: entries,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages
    }
  end

  @doc """
  Lists activity log entries for a specific invoice, including related payment request events.
  This provides the full invoice timeline including payments.
  """
  @spec list_invoice_timeline(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: [AuditLog.t()]
  def list_invoice_timeline(company_id, invoice_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_per_page) |> max(1) |> min(@max_per_page)

    AuditLog
    |> where([a], a.company_id == ^company_id)
    |> where(
      [a],
      (a.resource_type == "invoice" and a.resource_id == ^invoice_id) or
        fragment("? ->> 'invoice_id' = ?", a.metadata, ^invoice_id)
    )
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  @spec maybe_filter_action_prefix(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_filter_action_prefix(query, nil), do: query
  defp maybe_filter_action_prefix(query, ""), do: query

  defp maybe_filter_action_prefix(query, prefix) do
    pattern = prefix <> ".%"
    where(query, [a], like(a.action, ^pattern))
  end

  @spec maybe_filter_resource_type(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  defp maybe_filter_resource_type(query, nil), do: query
  defp maybe_filter_resource_type(query, ""), do: query

  defp maybe_filter_resource_type(query, type) do
    where(query, [a], a.resource_type == ^type)
  end
end
