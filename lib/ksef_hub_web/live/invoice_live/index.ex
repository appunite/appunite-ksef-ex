defmodule KsefHubWeb.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing and filtering invoices by type and status, with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.InvoiceComponents

  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns[:current_company] && socket.assigns.current_company.id

    {:ok,
     assign(socket,
       page_title: "Invoices",
       categories: if(company_id, do: Invoices.list_categories(company_id), else: []),
       all_tags: if(company_id, do: Invoices.list_tags(company_id), else: [])
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    role = socket.assigns[:current_role]

    result =
      case socket.assigns[:current_company] do
        %{id: company_id} ->
          Invoices.list_invoices_paginated(company_id, filters, role: role)

        _ ->
          %{entries: [], page: 1, per_page: 25, total_count: 0, total_pages: 1}
      end

    {:noreply, assign(socket, filter_assigns(filters, result, role))}
  end

  @spec filter_assigns(map(), map(), atom() | nil) :: keyword()
  defp filter_assigns(filters, result, role) do
    first_tag_id = filters[:tag_ids] |> List.wrap() |> List.first()

    form =
      %{
        "type" => to_string_or_empty(filters[:type]),
        "status" => to_string_or_empty(filters[:status]),
        "date_from" => (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
        "date_to" => (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
        "query" => filters[:query] || "",
        "category_id" => filters[:category_id] || "",
        "tag_id" => first_tag_id || ""
      }
      |> to_form(as: :filters)

    [
      invoices: result.entries,
      filters: filters,
      form: form,
      page: result.page,
      per_page: result.per_page,
      total_count: result.total_count,
      total_pages: result.total_pages,
      is_reviewer: role == :reviewer
    ]
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params =
      %{}
      |> maybe_put("type", params["type"])
      |> maybe_put("status", params["status"])
      |> maybe_put("date_from", params["date_from"])
      |> maybe_put("date_to", params["date_to"])
      |> maybe_put("query", params["query"])
      |> maybe_put("category_id", params["category_id"])
      |> maybe_put("tag_id", params["tag_id"])

    {:noreply, push_patch(socket, to: ~p"/invoices?#{query_params}")}
  end

  @spec parse_filters(map()) :: map()
  defp parse_filters(params) do
    %{}
    |> maybe_put_enum(:type, params["type"], Invoice, :type)
    |> maybe_put_enum(:status, params["status"], Invoice, :status)
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_search(:query, params["query"])
    |> maybe_put_uuid(:category_id, params["category_id"])
    |> maybe_put_tag_ids(params["tag_id"])
    |> maybe_put_page(:page, params["page"])
  end

  @spec maybe_put_enum(map(), atom(), String.t() | nil, module(), atom()) :: map()
  defp maybe_put_enum(map, _key, nil, _schema, _field), do: map
  defp maybe_put_enum(map, _key, "", _schema, _field), do: map

  defp maybe_put_enum(map, key, value, schema, field) do
    type = schema.__schema__(:type, field)

    case Ecto.Type.cast(type, value) do
      {:ok, atom} -> Map.put(map, key, atom)
      :error -> map
    end
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

  @spec maybe_put_page(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_page(map, _key, nil), do: map
  defp maybe_put_page(map, _key, ""), do: map

  defp maybe_put_page(map, key, value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> Map.put(map, key, int)
      _ -> map
    end
  end

  @spec maybe_put_uuid(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_uuid(map, _key, nil), do: map
  defp maybe_put_uuid(map, _key, ""), do: map

  defp maybe_put_uuid(map, key, value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> Map.put(map, key, uuid)
      :error -> map
    end
  end

  @spec maybe_put_tag_ids(map(), String.t() | nil) :: map()
  defp maybe_put_tag_ids(map, nil), do: map
  defp maybe_put_tag_ids(map, ""), do: map

  defp maybe_put_tag_ids(map, tag_id) do
    case Ecto.UUID.cast(tag_id) do
      {:ok, uuid} -> Map.put(map, :tag_ids, [uuid])
      :error -> map
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec to_string_or_empty(atom() | String.t() | nil) :: String.t()
  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value) when is_atom(value), do: Atom.to_string(value)
  defp to_string_or_empty(value) when is_binary(value), do: value

  @spec pagination_params(map(), pos_integer()) :: map()
  defp pagination_params(filters, target_page) do
    %{}
    |> maybe_put("type", to_string_or_empty(filters[:type]))
    |> maybe_put("status", to_string_or_empty(filters[:status]))
    |> maybe_put("date_from", filters[:date_from] && Date.to_iso8601(filters[:date_from]))
    |> maybe_put("date_to", filters[:date_to] && Date.to_iso8601(filters[:date_to]))
    |> maybe_put("query", filters[:query])
    |> maybe_put("category_id", filters[:category_id])
    |> maybe_put("tag_id", filters[:tag_ids] |> List.wrap() |> List.first())
    |> maybe_put("page", if(target_page > 1, do: Integer.to_string(target_page)))
  end

  @spec visible_pages(pos_integer(), pos_integer()) :: [pos_integer()]
  defp visible_pages(_current_page, total_pages) when total_pages <= 7 do
    Enum.to_list(1..total_pages)
  end

  defp visible_pages(current_page, total_pages) do
    # Show a window of 5 pages centered on the current page
    half = 2
    start = max(1, current_page - half)
    finish = min(total_pages, current_page + half)

    # Adjust if near the edges
    {start, finish} =
      cond do
        finish - start < 4 && start == 1 -> {1, min(5, total_pages)}
        finish - start < 4 && finish == total_pages -> {max(1, total_pages - 4), total_pages}
        true -> {start, finish}
      end

    Enum.to_list(start..finish)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoices
      <:subtitle>Browse and manage KSeF invoices</:subtitle>
    </.header>

    <!-- Filters -->
    <.form for={@form} phx-change="filter" class="flex flex-wrap gap-3 mt-4 mb-6 items-end">
      <div class="form-control w-32">
        <label class="label"><span class="label-text text-xs">Type</span></label>
        <select
          :if={!@is_reviewer}
          name={@form[:type].name}
          class="select select-sm select-bordered"
        >
          <option value="">All</option>
          <option value="income" selected={@form[:type].value == "income"}>Income</option>
          <option value="expense" selected={@form[:type].value == "expense"}>Expense</option>
        </select>
        <select
          :if={@is_reviewer}
          name={@form[:type].name}
          class="select select-sm select-bordered"
          disabled
        >
          <option value="expense" selected>Expense</option>
        </select>
      </div>

      <div class="form-control w-32">
        <label class="label"><span class="label-text text-xs">Status</span></label>
        <select name={@form[:status].name} class="select select-sm select-bordered">
          <option value="">All</option>
          <option value="pending" selected={@form[:status].value == "pending"}>Pending</option>
          <option value="approved" selected={@form[:status].value == "approved"}>Approved</option>
          <option value="rejected" selected={@form[:status].value == "rejected"}>Rejected</option>
        </select>
      </div>

      <div class="form-control w-40">
        <label class="label"><span class="label-text text-xs">Category</span></label>
        <select name={@form[:category_id].name} class="select select-sm select-bordered">
          <option value="">All</option>
          <option
            :for={cat <- @categories}
            value={cat.id}
            selected={@form[:category_id].value == cat.id}
          >
            {if(cat.emoji, do: "#{cat.emoji} ", else: "")}{cat.name}
          </option>
        </select>
      </div>

      <div class="form-control w-36">
        <label class="label"><span class="label-text text-xs">Tag</span></label>
        <select name={@form[:tag_id].name} class="select select-sm select-bordered">
          <option value="">All</option>
          <option
            :for={tag <- @all_tags}
            value={tag.id}
            selected={@form[:tag_id].value == tag.id}
          >
            {tag.name}
          </option>
        </select>
      </div>

      <div class="form-control w-36">
        <label class="label"><span class="label-text text-xs">From</span></label>
        <input
          type="date"
          name={@form[:date_from].name}
          value={@form[:date_from].value}
          class="input input-sm input-bordered"
        />
      </div>

      <div class="form-control w-36">
        <label class="label"><span class="label-text text-xs">To</span></label>
        <input
          type="date"
          name={@form[:date_to].name}
          value={@form[:date_to].value}
          class="input input-sm input-bordered"
        />
      </div>

      <div class="form-control flex-1 min-w-48">
        <label class="label"><span class="label-text text-xs">Search</span></label>
        <input
          type="text"
          name={@form[:query].name}
          value={@form[:query].value}
          placeholder="Invoice number, seller, buyer..."
          phx-debounce="300"
          class="input input-sm input-bordered"
        />
      </div>
    </.form>

    <!-- Invoice Table -->
    <div class="overflow-x-auto">
      <.table id="invoices" rows={@invoices} row_id={fn inv -> "inv-#{inv.id}" end}>
        <:col :let={inv} label="Date" class="w-28">
          <span class="whitespace-nowrap">{format_date(inv.issue_date)}</span>
        </:col>
        <:col :let={inv} label="Type" class="w-24">
          <.type_badge type={inv.type} />
        </:col>
        <:col :let={inv} label="Seller">
          <.link navigate={~p"/invoices/#{inv.id}"} class="link link-primary">
            {inv.seller_name}
          </.link>
        </:col>
        <:col :let={inv} label="Gross" class="w-36 text-right">
          <span class="font-mono">{format_amount(inv.gross_amount)}</span>
          <span class="text-xs text-base-content/60">{inv.currency}</span>
        </:col>
        <:col :let={inv} label="Status" class="w-28">
          <.status_badge status={inv.status} />
        </:col>
        <:col :let={inv} label="Category">
          <.category_badge category={inv.category} />
        </:col>
        <:col :let={inv} label="Tags">
          <.tag_list tags={inv.tags} />
        </:col>
        <:col :let={inv} label="" class="w-16">
          <.prediction_indicator prediction_status={inv.prediction_status} />
        </:col>
      </.table>
    </div>

    <p :if={@invoices == [] && @total_count == 0} class="text-center text-base-content/60 py-8">
      No invoices found matching your filters.
    </p>

    <!-- Pagination -->
    <div
      :if={@total_pages > 1}
      class="flex items-center justify-between mt-6"
      data-testid="pagination"
    >
      <p class="text-sm text-base-content/60">
        Showing {(@page - 1) * @per_page + 1}–{min(@page * @per_page, @total_count)} of {@total_count} invoices
      </p>

      <div class="join">
        <.link
          :if={@page > 1}
          patch={~p"/invoices?#{pagination_params(@filters, @page - 1)}"}
          class="join-item btn btn-sm"
        >
          Prev
        </.link>
        <span :if={@page <= 1} class="join-item btn btn-sm btn-disabled">Prev</span>

        <.link
          :for={p <- visible_pages(@page, @total_pages)}
          patch={~p"/invoices?#{pagination_params(@filters, p)}"}
          class={["join-item btn btn-sm", p == @page && "btn-active"]}
        >
          {p}
        </.link>

        <.link
          :if={@page < @total_pages}
          patch={~p"/invoices?#{pagination_params(@filters, @page + 1)}"}
          class="join-item btn btn-sm"
        >
          Next
        </.link>
        <span :if={@page >= @total_pages} class="join-item btn btn-sm btn-disabled">Next</span>
      </div>
    </div>
    """
  end
end
