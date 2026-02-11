defmodule KsefHubWeb.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing and filtering invoices by type and status.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices

  import KsefHubWeb.InvoiceComponents

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Invoices")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    invoices =
      case socket.assigns[:current_company] do
        %{id: company_id} -> Invoices.list_invoices(company_id, filters)
        _ -> []
      end

    {:noreply, assign(socket, filter_assigns(filters, invoices))}
  end

  @spec filter_assigns(map(), list()) :: keyword()
  defp filter_assigns(filters, invoices) do
    [
      invoices: invoices,
      filters: filters,
      type_filter: filters[:type] || "",
      status_filter: filters[:status] || "",
      date_from: (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
      date_to: (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
      search: filters[:query] || ""
    ]
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{}
      |> maybe_put("type", params["type"])
      |> maybe_put("status", params["status"])
      |> maybe_put("date_from", params["date_from"])
      |> maybe_put("date_to", params["date_to"])
      |> maybe_put("query", params["query"])

    {:noreply, push_patch(socket, to: ~p"/invoices?#{query_params}")}
  end

  defp parse_filters(params) do
    %{}
    |> maybe_put_filter(:type, params["type"], ~w(income expense))
    |> maybe_put_filter(:status, params["status"], ~w(pending approved rejected))
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_search(:query, params["query"])
  end

  defp maybe_put_filter(map, _key, nil, _valid), do: map
  defp maybe_put_filter(map, _key, "", _valid), do: map

  defp maybe_put_filter(map, key, value, valid) do
    if value in valid, do: Map.put(map, key, value), else: map
  end

  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  defp maybe_put_search(map, _key, nil), do: map
  defp maybe_put_search(map, _key, ""), do: map
  defp maybe_put_search(map, key, value), do: Map.put(map, key, value)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoices
      <:subtitle>Browse and manage KSeF invoices</:subtitle>
    </.header>

    <!-- Filters -->
    <form phx-change="filter" class="flex flex-wrap gap-3 mt-4 mb-6 items-end">
      <div class="form-control w-32">
        <label class="label"><span class="label-text text-xs">Type</span></label>
        <select name="type" class="select select-sm select-bordered">
          <option value="">All</option>
          <option value="income" selected={@type_filter == "income"}>Income</option>
          <option value="expense" selected={@type_filter == "expense"}>Expense</option>
        </select>
      </div>

      <div class="form-control w-32">
        <label class="label"><span class="label-text text-xs">Status</span></label>
        <select name="status" class="select select-sm select-bordered">
          <option value="">All</option>
          <option value="pending" selected={@status_filter == "pending"}>Pending</option>
          <option value="approved" selected={@status_filter == "approved"}>Approved</option>
          <option value="rejected" selected={@status_filter == "rejected"}>Rejected</option>
        </select>
      </div>

      <div class="form-control w-36">
        <label class="label"><span class="label-text text-xs">From</span></label>
        <input type="date" name="date_from" value={@date_from} class="input input-sm input-bordered" />
      </div>

      <div class="form-control w-36">
        <label class="label"><span class="label-text text-xs">To</span></label>
        <input type="date" name="date_to" value={@date_to} class="input input-sm input-bordered" />
      </div>

      <div class="form-control flex-1 min-w-48">
        <label class="label"><span class="label-text text-xs">Search</span></label>
        <input
          type="text"
          name="query"
          value={@search}
          placeholder="Invoice number, seller, buyer..."
          phx-debounce="300"
          class="input input-sm input-bordered"
        />
      </div>
    </form>

    <!-- Invoice Table -->
    <div class="overflow-x-auto">
      <.table id="invoices" rows={@invoices} row_id={fn inv -> "inv-#{inv.id}" end}>
        <:col :let={inv} label="Number" class="w-1/5">
          <.link navigate={~p"/invoices/#{inv.id}"} class="link link-primary">
            {inv.invoice_number}
          </.link>
        </:col>
        <:col :let={inv} label="Date" class="w-28">
          <span class="whitespace-nowrap">{format_date(inv.issue_date)}</span>
        </:col>
        <:col :let={inv} label="Type" class="w-24">
          <.type_badge type={inv.type} />
        </:col>
        <:col :let={inv} label="Seller">{inv.seller_name}</:col>
        <:col :let={inv} label="Gross" class="w-36 text-right">
          <span class="font-mono">{format_amount(inv.gross_amount)}</span>
          <span class="text-xs text-base-content/60">{inv.currency}</span>
        </:col>
        <:col :let={inv} label="Status" class="w-28">
          <.status_badge status={inv.status} />
        </:col>
      </.table>
    </div>

    <p :if={@invoices == []} class="text-center text-base-content/60 py-8">
      No invoices found matching your filters.
    </p>
    """
  end
end
