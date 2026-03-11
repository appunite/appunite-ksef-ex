defmodule KsefHubWeb.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing and filtering invoices by type and status, with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  import KsefHubWeb.InvoiceComponents

  @impl true
  def mount(_params, _session, socket) do
    company_id =
      case socket.assigns do
        %{current_company: %{id: id}} -> id
        _ -> nil
      end

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
    form =
      %{
        "type" => to_string_or_empty(filters[:type]),
        "status" => to_string_or_empty(filters[:status]),
        "date_from" => (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
        "date_to" => (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
        "query" => filters[:query] || "",
        "category_id" => filters[:category_id] || "",
        "tag_id" => first_tag_id(filters) || ""
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
      can_view_all_types: Authorization.can?(role, :view_all_invoice_types),
      can_create: Authorization.can?(role, :create_invoice)
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

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{query_params}")}
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

  @spec maybe_put_date(map(), atom(), String.t() | nil) :: map()
  defp maybe_put_date(map, _key, nil), do: map
  defp maybe_put_date(map, _key, ""), do: map

  defp maybe_put_date(map, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(map, key, date)
      _ -> map
    end
  end

  @spec maybe_put_search(map(), atom(), String.t() | nil) :: map()
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

  @spec maybe_put(map(), String.t(), String.t() | nil) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec first_tag_id(map()) :: Ecto.UUID.t() | nil
  defp first_tag_id(filters), do: filters[:tag_ids] |> List.wrap() |> List.first()

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
    |> maybe_put("tag_id", first_tag_id(filters))
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
      <:actions>
        <.link
          :if={@can_create}
          navigate={~p"/c/#{@current_company.id}/invoices/upload"}
          class="inline-flex items-center justify-center gap-2 h-8 px-3 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors"
        >
          <.icon name="hero-arrow-up-tray" class="size-4" /> Upload PDF
        </.link>
      </:actions>
    </.header>

    <!-- Filters -->
    <.form for={@form} phx-change="filter" class="flex flex-wrap gap-3 mt-4 mb-6 items-end">
      <div class="space-y-1 w-32">
        <label class="block text-xs font-medium text-muted-foreground">Type</label>
        <select
          :if={@can_view_all_types}
          name={@form[:type].name}
          class="h-8 rounded-md border border-input bg-background px-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <option value="">All</option>
          <option value="income" selected={@form[:type].value == "income"}>Income</option>
          <option value="expense" selected={@form[:type].value == "expense"}>Expense</option>
        </select>
        <select
          :if={!@can_view_all_types}
          name={@form[:type].name}
          class="h-8 rounded-md border border-input bg-background px-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          disabled
        >
          <option value="expense" selected>Expense</option>
        </select>
      </div>

      <div class="space-y-1 w-32">
        <label class="block text-xs font-medium text-muted-foreground">Status</label>
        <select
          name={@form[:status].name}
          class="h-8 rounded-md border border-input bg-background px-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <option value="">All</option>
          <option value="pending" selected={@form[:status].value == "pending"}>Pending</option>
          <option value="approved" selected={@form[:status].value == "approved"}>Approved</option>
          <option value="rejected" selected={@form[:status].value == "rejected"}>Rejected</option>
        </select>
      </div>

      <div class="space-y-1 w-40">
        <label class="block text-xs font-medium text-muted-foreground">Category</label>
        <select
          name={@form[:category_id].name}
          class="h-8 rounded-md border border-input bg-background px-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
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

      <div class="space-y-1 w-36">
        <label class="block text-xs font-medium text-muted-foreground">Tag</label>
        <select
          name={@form[:tag_id].name}
          class="h-8 rounded-md border border-input bg-background px-2 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
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

      <div class="space-y-1 w-36">
        <label class="block text-xs font-medium text-muted-foreground">From</label>
        <input
          type="date"
          name={@form[:date_from].name}
          value={@form[:date_from].value}
          class="h-8 rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
      </div>

      <div class="space-y-1 w-36">
        <label class="block text-xs font-medium text-muted-foreground">To</label>
        <input
          type="date"
          name={@form[:date_to].name}
          value={@form[:date_to].value}
          class="h-8 rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        />
      </div>

      <div class="space-y-1 flex-1 min-w-48">
        <label class="block text-xs font-medium text-muted-foreground">Search</label>
        <input
          type="text"
          name={@form[:query].name}
          value={@form[:query].value}
          placeholder="Invoice number, seller, buyer..."
          phx-debounce="300"
          class="h-8 rounded-md border border-input bg-background px-3 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
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
          <.link
            navigate={~p"/c/#{@current_company.id}/invoices/#{inv.id}"}
            class="text-shad-primary underline-offset-4 hover:underline"
          >
            {cond do
              String.trim(inv.seller_name || "") != "" -> inv.seller_name
              String.trim(inv.invoice_number || "") != "" -> inv.invoice_number
              true -> "Untitled invoice"
            end}
          </.link>
        </:col>
        <:col :let={inv} label="Gross" class="w-36 text-right">
          <span class="font-mono">{format_amount(inv.gross_amount)}</span>
          <span class="text-xs text-muted-foreground">{inv.currency}</span>
        </:col>
        <:col :let={inv} label="Status" class="w-28">
          <div class="flex flex-wrap gap-1">
            <.status_badge status={display_status(inv)} />
            <.needs_review_badge
              prediction_status={inv.prediction_status}
              duplicate_status={inv.duplicate_status}
              extraction_status={inv.extraction_status}
              status={inv.status}
            />
            <.extraction_badge status={inv.extraction_status} />
          </div>
        </:col>
        <:col :let={inv} label="Category">
          <.category_badge category={inv.category} />
        </:col>
        <:col :let={inv} label="Tags">
          <.tag_list tags={inv.tags} />
        </:col>
      </.table>
    </div>

    <p :if={@invoices == [] && @total_count == 0} class="text-center text-muted-foreground py-8">
      No invoices found matching your filters.
    </p>

    <!-- Pagination -->
    <div
      :if={@total_pages > 1}
      class="flex items-center justify-between mt-6"
      data-testid="pagination"
    >
      <p class="text-sm text-muted-foreground">
        Showing {(@page - 1) * @per_page + 1}–{min(@page * @per_page, @total_count)} of {@total_count} invoices
      </p>

      <div class="flex">
        <.link
          :if={@page > 1}
          patch={~p"/c/#{@current_company.id}/invoices?#{pagination_params(@filters, @page - 1)}"}
          class="inline-flex items-center justify-center h-8 px-3 text-sm border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors first:rounded-l-md last:rounded-r-md"
        >
          Prev
        </.link>
        <span
          :if={@page <= 1}
          class="inline-flex items-center justify-center h-8 px-3 text-sm border border-input bg-background transition-colors first:rounded-l-md last:rounded-r-md opacity-50 pointer-events-none"
        >
          Prev
        </span>

        <.link
          :for={p <- visible_pages(@page, @total_pages)}
          patch={~p"/c/#{@current_company.id}/invoices?#{pagination_params(@filters, p)}"}
          class={[
            "inline-flex items-center justify-center h-8 px-3 text-sm border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors first:rounded-l-md last:rounded-r-md",
            p == @page && "bg-shad-accent text-shad-accent-foreground font-medium"
          ]}
        >
          {p}
        </.link>

        <.link
          :if={@page < @total_pages}
          patch={~p"/c/#{@current_company.id}/invoices?#{pagination_params(@filters, @page + 1)}"}
          class="inline-flex items-center justify-center h-8 px-3 text-sm border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors first:rounded-l-md last:rounded-r-md"
        >
          Next
        </.link>
        <span
          :if={@page >= @total_pages}
          class="inline-flex items-center justify-center h-8 px-3 text-sm border border-input bg-background transition-colors first:rounded-l-md last:rounded-r-md opacity-50 pointer-events-none"
        >
          Next
        </span>
      </div>
    </div>
    """
  end
end
