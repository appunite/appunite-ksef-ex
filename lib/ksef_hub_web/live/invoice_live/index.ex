defmodule KsefHubWeb.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing and filtering invoices by type and status, with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice
  alias KsefHub.PaymentRequests

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
    filters =
      params
      |> parse_filters()
      |> Map.put_new(:type, :expense)

    role = socket.assigns[:current_role]

    result =
      case socket.assigns[:current_company] do
        %{id: company_id} ->
          Invoices.list_invoices_paginated(company_id, filters, role: role)

        _ ->
          %{entries: [], page: 1, per_page: 25, total_count: 0, total_pages: 1}
      end

    {:noreply, assign(socket, filter_assigns(filters, result, role, socket.assigns))}
  end

  @spec filter_assigns(map(), map(), atom() | nil, map()) :: keyword()
  defp filter_assigns(filters, result, role, assigns) do
    normalized = normalize_filters(filters, role)
    form = build_filters_form(normalized)

    active_filters =
      build_active_filters(
        normalized,
        Map.get(assigns, :categories, []),
        Map.get(assigns, :all_tags, [])
      )

    invoice_ids = Enum.map(result.entries, & &1.id)
    payment_statuses = PaymentRequests.payment_statuses_for_invoices(invoice_ids)

    [
      invoices: result.entries,
      filters: filters,
      form: form,
      payment_statuses: payment_statuses,
      page: result.page,
      per_page: result.per_page,
      total_count: result.total_count,
      total_pages: result.total_pages,
      can_view_all_types: Authorization.can?(role, :view_all_invoice_types),
      can_create: Authorization.can?(role, :create_invoice),
      active_filters: active_filters,
      filter_count: length(active_filters)
    ]
  end

  @spec normalize_filters(map(), atom() | nil) :: map()
  defp normalize_filters(filters, role) do
    if filters[:type] && !Authorization.can?(role, :view_all_invoice_types) do
      Map.delete(filters, :type)
    else
      filters
    end
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
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
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    current_type = to_string_or_empty(socket.assigns.filters[:type])

    query_params =
      %{}
      |> maybe_put("type", current_type)
      |> maybe_put("status", params["status"])
      |> maybe_put("date_from", params["date_from"])
      |> maybe_put("date_to", params["date_to"])
      |> maybe_put("query", params["query"])
      |> maybe_put("category_id", params["category_id"])
      |> maybe_put("tag_id", params["tag_id"])

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{query_params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    company_id = socket.assigns.current_company.id
    current_type = to_string_or_empty(socket.assigns.filters[:type])
    params = maybe_put(%{}, "type", current_type)
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{params}")}
  end

  def handle_event("remove_filter", %{"key" => key}, socket) do
    query_params =
      filter_params_without_page(socket.assigns.filters)
      |> Map.delete(key)

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{query_params}")}
  end

  @spec tab_class(boolean()) :: String.t()
  defp tab_class(true),
    do: "px-4 py-2 text-sm font-medium border-b-2 -mb-px border-shad-primary text-shad-primary"

  defp tab_class(false),
    do:
      "px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors border-transparent text-muted-foreground hover:text-foreground hover:border-border"

  @spec tab_url(String.t(), map(), atom() | nil) :: String.t()
  defp tab_url(company_id, filters, type) do
    params =
      filter_params_without_page(filters)
      |> Map.delete("type")
      |> then(fn p -> if type, do: Map.put(p, "type", to_string(type)), else: p end)

    ~p"/c/#{company_id}/invoices?#{params}"
  end

  @spec build_active_filters(map(), list(), list()) :: [map()]
  defp build_active_filters(filters, categories, tags) do
    []
    |> maybe_add_chip(filters[:status], "status", "Status", &status_display/1)
    |> maybe_add_chip(filters[:category_id], "category_id", "Category", fn id ->
      case Enum.find(categories, &(&1.id == id)) do
        nil -> id
        cat -> cat.name
      end
    end)
    |> maybe_add_chip(first_tag_id(filters), "tag_id", "Tag", fn id ->
      case Enum.find(tags, &(&1.id == id)) do
        nil -> id
        tag -> tag.name
      end
    end)
    |> maybe_add_chip(filters[:date_from], "date_from", "From", &Date.to_iso8601/1)
    |> maybe_add_chip(filters[:date_to], "date_to", "To", &Date.to_iso8601/1)
    |> Enum.reverse()
  end

  @spec maybe_add_chip(list(), any(), String.t(), String.t(), (any() -> String.t())) :: list()
  defp maybe_add_chip(acc, nil, _key, _label, _formatter), do: acc

  defp maybe_add_chip(acc, value, key, label, formatter) do
    [%{key: key, label: label, value: formatter.(value)} | acc]
  end

  @spec status_display(atom()) :: String.t()
  defp status_display(:pending), do: "Pending"
  defp status_display(:approved), do: "Approved"
  defp status_display(:rejected), do: "Rejected"
  defp status_display(other), do: to_string(other)

  @spec filter_params_without_page(map()) :: map()
  defp filter_params_without_page(filters) do
    %{}
    |> maybe_put("type", to_string_or_empty(filters[:type]))
    |> maybe_put("status", to_string_or_empty(filters[:status]))
    |> maybe_put("date_from", filters[:date_from] && Date.to_iso8601(filters[:date_from]))
    |> maybe_put("date_to", filters[:date_to] && Date.to_iso8601(filters[:date_to]))
    |> maybe_put("query", filters[:query])
    |> maybe_put("category_id", filters[:category_id])
    |> maybe_put("tag_id", first_tag_id(filters))
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

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Invoices
      <:subtitle>Invoices for {@current_company.name}</:subtitle>
      <:actions>
        <.button :if={@can_create} navigate={~p"/c/#{@current_company.id}/invoices/upload"}>
          <.icon name="hero-arrow-up-tray" class="size-4" /> Upload PDF
        </.button>
      </:actions>
    </.header>

    <!-- Type Tabs -->
    <div class="flex border-b border-border mb-4">
      <.link
        :if={@can_view_all_types}
        patch={tab_url(@current_company.id, @filters, :expense)}
        class={tab_class(@filters[:type] == :expense)}
      >
        Expense
      </.link>
      <.link
        :if={@can_view_all_types}
        patch={tab_url(@current_company.id, @filters, :income)}
        class={tab_class(@filters[:type] == :income)}
      >
        Income
      </.link>
      <span :if={!@can_view_all_types} class={tab_class(true)}>
        Expense
      </span>
    </div>

    <.form for={@form} phx-change="filter" class="contents">
      <.filter_bar
        active_filters={@active_filters}
        filter_count={@filter_count}
        search_name={@form[:query].name}
        search_value={@form[:query].value}
        search_placeholder="Invoice number, seller, buyer..."
      >
        <:filter_fields>
          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">Status</label>
            <select
              name={@form[:status].name}
              class="w-full h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="">All</option>
              <option value="pending" selected={@form[:status].value == "pending"}>Pending</option>
              <option value="approved" selected={@form[:status].value == "approved"}>
                Approved
              </option>
              <option value="rejected" selected={@form[:status].value == "rejected"}>
                Rejected
              </option>
            </select>
          </div>

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">Category</label>
            <select
              name={@form[:category_id].name}
              class="w-full h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
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

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">Tag</label>
            <select
              name={@form[:tag_id].name}
              class="w-full h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
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

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">From</label>
            <input
              type="date"
              name={@form[:date_from].name}
              value={@form[:date_from].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">To</label>
            <input
              type="date"
              name={@form[:date_to].name}
              value={@form[:date_to].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </:filter_fields>
      </.filter_bar>
    </.form>

    <!-- Invoice Table -->
    <div class="rounded-lg border border-border overflow-hidden">
      <div class="overflow-x-auto">
        <.table id="invoices" rows={@invoices} row_id={fn inv -> "inv-#{inv.id}" end}>
          <:col :let={inv} label="Date" class="w-28">
            <span class="whitespace-nowrap">{format_date(inv.issue_date)}</span>
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
          <:col :let={inv} label="Payment" class="w-28">
            <.payment_badge status={@payment_statuses[inv.id]} />
          </:col>
        </.table>
      </div>

      <p
        :if={@invoices == [] && @total_count == 0}
        class="text-center text-muted-foreground py-8"
      >
        No invoices found matching your filters.
      </p>

      <div class="border-t border-border px-4 py-3">
        <.pagination
          page={@page}
          per_page={@per_page}
          total_count={@total_count}
          total_pages={@total_pages}
          base_url={~p"/c/#{@current_company.id}/invoices"}
          params={filter_params_without_page(@filters)}
          noun="invoices"
        />
      </div>
    </div>
    """
  end
end
