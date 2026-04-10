defmodule KsefHubWeb.InvoiceLive.Index do
  @moduledoc """
  LiveView for listing and filtering invoices by type and status, with pagination.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Credentials
  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice
  alias KsefHub.PaymentRequests

  import KsefHubWeb.CertificateComponents, only: [cert_expiry_alert: 1]
  import KsefHubWeb.InvoiceComponents
  import KsefHubWeb.FilterHelpers

  @doc "Loads initial assigns: page title, categories, tags, and certificate status."
  @impl true
  @spec mount(map() | nil, map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company_id =
      case socket.assigns do
        %{current_company: %{id: id}} -> id
        _ -> nil
      end

    cert_status =
      if company_id, do: Credentials.certificate_expiry_status(company_id), else: :no_certificate

    {:ok,
     assign(socket,
       page_title: "Invoices",
       categories: if(company_id, do: Invoices.list_categories(company_id), else: []),
       all_tags: [],
       cert_status: cert_status,
       open_filter: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    role = socket.assigns[:current_role]

    filters =
      params
      |> parse_filters()
      |> Map.put_new(:type, :expense)
      |> Map.put_new(:statuses, [:pending, :approved])

    company_id =
      case socket.assigns[:current_company] do
        %{id: id} -> id
        _ -> nil
      end

    all_tags =
      if company_id do
        Invoices.list_distinct_tags(company_id, filters[:type],
          role: role,
          user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
        )
      else
        []
      end

    result =
      if company_id do
        Invoices.list_invoices_paginated(company_id, filters,
          role: role,
          user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
        )
      else
        %{entries: [], page: 1, per_page: 25, total_count: 0, total_pages: 1}
      end

    {:noreply,
     socket
     |> assign(all_tags: all_tags)
     |> assign(filter_assigns(filters, result, role, socket.assigns))}
  end

  @spec filter_assigns(map(), map(), atom() | nil, map()) :: keyword()
  defp filter_assigns(filters, result, role, _assigns) do
    form = build_filters_form(filters)

    invoice_ids = Enum.map(result.entries, & &1.id)
    payment_statuses = PaymentRequests.payment_statuses_for_invoices(invoice_ids)

    filter_count = filter_count(filters)

    [
      invoices: result.entries,
      filters: filters,
      form: form,
      payment_statuses: payment_statuses,
      page: result.page,
      per_page: result.per_page,
      total_count: result.total_count,
      total_pages: result.total_pages,
      can_create: Authorization.can?(role, :create_invoice),
      filter_count: filter_count
    ]
  end

  @spec statuses_count(map()) :: non_neg_integer()
  defp statuses_count(filters) do
    default_statuses = MapSet.new([:pending, :approved])

    case filters[:statuses] || [] do
      [] -> 0
      list -> if MapSet.new(list) == default_statuses, do: 0, else: length(list)
    end
  end

  @spec filter_count(map()) :: non_neg_integer()
  defp filter_count(filters) do
    statuses_count(filters) +
      length(filters[:category_ids] || []) +
      length(filters[:tags] || []) +
      length(filters[:payment_statuses] || []) +
      if(filters[:date_from], do: 1, else: 0) +
      if(filters[:date_to], do: 1, else: 0) +
      if(filters[:query] && String.trim(filters[:query]) != "", do: 1, else: 0)
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
    %{
      "type" => to_string_or_empty(filters[:type]),
      "date_from" => (filters[:date_from] && Date.to_iso8601(filters[:date_from])) || "",
      "date_to" => (filters[:date_to] && Date.to_iso8601(filters[:date_to])) || "",
      "query" => filters[:query] || ""
    }
    |> to_form(as: :filters)
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params = build_query_params(socket.assigns.filters, params)
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{query_params}")}
  end

  def handle_event("toggle_filter", %{"field" => field, "value" => value}, socket) do
    filters = toggle_filter_value(socket.assigns.filters, field, value)
    query_params = build_query_params(filters, %{})
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{query_params}")}
  end

  def handle_event("open_filter", %{"id" => id}, socket) do
    current = socket.assigns.open_filter
    {:noreply, assign(socket, :open_filter, if(current == id, do: nil, else: id))}
  end

  def handle_event("close_filter", _params, socket) do
    {:noreply, assign(socket, :open_filter, nil)}
  end

  def handle_event("clear_filters", _params, socket) do
    company_id = socket.assigns.current_company.id
    current_type = to_string_or_empty(socket.assigns.filters[:type])
    params = maybe_put(%{}, "type", current_type)
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/invoices?#{params}")}
  end

  @spec build_query_params(map(), map()) :: map()
  defp build_query_params(filters, form_params) do
    %{}
    |> maybe_put("type", to_string_or_empty(filters[:type]))
    |> then(fn params ->
      case filters[:statuses] do
        [] -> Map.put(params, "statuses", "")
        other -> maybe_put(params, "statuses", join_list(other))
      end
    end)
    |> maybe_put("date_from", form_params["date_from"] || date_to_string(filters[:date_from]))
    |> maybe_put("date_to", form_params["date_to"] || date_to_string(filters[:date_to]))
    |> maybe_put("query", form_params["query"] || filters[:query])
    |> maybe_put("category_ids", join_list(filters[:category_ids]))
    |> maybe_put_list("tags[]", filters[:tags])
    |> maybe_put("payment_statuses", join_list(filters[:payment_statuses]))
  end

  @spec tab_url(String.t(), map(), atom() | nil) :: String.t()
  defp tab_url(company_id, filters, type) do
    params =
      filter_params_without_page(filters)
      |> Map.delete("type")
      |> then(fn p -> if type, do: Map.put(p, "type", to_string(type)), else: p end)

    ~p"/c/#{company_id}/invoices?#{params}"
  end

  @spec counterparty_name(map(), atom() | nil) :: String.t()
  defp counterparty_name(invoice, :income) do
    cond do
      String.trim(invoice.buyer_name || "") != "" -> invoice.buyer_name
      String.trim(invoice.seller_name || "") != "" -> invoice.seller_name
      String.trim(invoice.invoice_number || "") != "" -> invoice.invoice_number
      true -> "Untitled invoice"
    end
  end

  defp counterparty_name(invoice, _type) do
    cond do
      String.trim(invoice.seller_name || "") != "" -> invoice.seller_name
      String.trim(invoice.invoice_number || "") != "" -> invoice.invoice_number
      true -> "Untitled invoice"
    end
  end

  @spec filter_params_without_page(map()) :: map()
  defp filter_params_without_page(filters) do
    build_query_params(filters, %{})
  end

  @spec parse_filters(map()) :: map()
  defp parse_filters(params) do
    is_income = params["type"] == "income"

    %{}
    |> maybe_put_enum(:type, params["type"], Invoice, :type)
    |> maybe_put_csv(:statuses, params["statuses"],
      valid: ~w(pending approved rejected duplicate),
      transform: &String.to_existing_atom/1
    )
    |> then(fn map ->
      if params["statuses"] == "" and not Map.has_key?(map, :statuses),
        do: Map.put(map, :statuses, []),
        else: map
    end)
    |> maybe_put_date(:date_from, params["date_from"])
    |> maybe_put_date(:date_to, params["date_to"])
    |> maybe_put_search(:query, params["query"])
    |> then(fn map ->
      if is_income do
        map
      else
        map
        |> maybe_put_csv(:category_ids, params["category_ids"],
          validate: fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end
        )
        |> maybe_put_csv(:payment_statuses, params["payment_statuses"],
          valid: ~w(paid pending none)
        )
      end
    end)
    |> maybe_put_tags(:tags, params["tags[]"] || params["tags"])
    |> maybe_put_page(:page, params["page"])
  end

  @doc "Renders the invoice index page with filters, type tabs, and optional certificate warning."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
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

    <div
      :if={@cert_status == :no_certificate}
      data-testid="certificate-warning-banner"
      class="rounded-lg border border-warning/50 bg-warning/10 p-4 mb-4 flex items-start gap-3"
    >
      <.icon name="hero-exclamation-triangle" class="size-5 text-warning mt-0.5" />
      <div>
        <p class="text-sm font-medium">KSeF sync not configured</p>
        <p class="text-sm text-muted-foreground">
          Upload a certificate in
          <.link
            navigate={~p"/c/#{@current_company.id}/settings/certificates"}
            class="underline"
          >
            Settings &rarr; Certificates
          </.link>
          to enable automatic invoice sync with KSeF.
        </p>
      </div>
    </div>

    <.cert_expiry_alert
      status={@cert_status}
      link_target={~p"/c/#{@current_company.id}/settings/certificates"}
      class="mb-4"
    />

    <!-- Type Tabs -->
    <div class="flex border-b border-border mb-4">
      <.link
        patch={tab_url(@current_company.id, @filters, :expense)}
        class={tab_class(@filters[:type] == :expense)}
        aria-current={if @filters[:type] == :expense, do: "page"}
      >
        Expense
      </.link>
      <.link
        patch={tab_url(@current_company.id, @filters, :income)}
        class={tab_class(@filters[:type] == :income)}
        aria-current={if @filters[:type] == :income, do: "page"}
      >
        Income
      </.link>
    </div>

    <div class="space-y-2 mt-4 mb-6">
      <div class="flex items-center gap-2 flex-wrap">
        <.multi_select
          id="status-filter"
          label="Status"
          field="statuses"
          options={[
            {"Pending", "pending"},
            {"Approved", "approved"},
            {"Rejected", "rejected"},
            {"Duplicate", "duplicate"}
          ]}
          selected={Enum.map(@filters[:statuses] || [], &to_string/1)}
          open={@open_filter == "status-filter"}
        />
        <.multi_select
          :if={@filters[:type] == :expense}
          id="category-filter"
          label="Category"
          field="category_ids"
          options={Enum.map(@categories, &{category_label(&1), &1.id})}
          selected={@filters[:category_ids] || []}
          searchable={length(@categories) > 6}
          open={@open_filter == "category-filter"}
        />
        <.multi_select
          :if={@filters[:type] != :income}
          id="payment-filter"
          label="Payment"
          field="payment_statuses"
          options={[{"Paid", "paid"}, {"Pending", "pending"}, {"None", "none"}]}
          selected={@filters[:payment_statuses] || []}
          open={@open_filter == "payment-filter"}
        />
        <.multi_select
          id="tag-filter"
          label="Tag"
          field="tags"
          options={Enum.map(@all_tags, &{&1, &1})}
          selected={@filters[:tags] || []}
          searchable={length(@all_tags) > 6}
          open={@open_filter == "tag-filter"}
        />

        <.form for={@form} id="date-search-form" phx-change="filter" class="contents">
          <.date_range_picker
            id="invoice-date-range"
            from_name={@form[:date_from].name}
            to_name={@form[:date_to].name}
            from_value={@form[:date_from].value}
            to_value={@form[:date_to].value}
          />

          <.reset_filters_button :if={@filter_count > 0} />

          <.search_input
            name={@form[:query].name}
            value={@form[:query].value}
            placeholder="Search invoices..."
            phx-debounce="300"
          />
        </.form>
      </div>
    </div>

    <!-- Invoice Table -->
    <.table_container>
      <.table id="invoices" rows={@invoices} row_id={fn inv -> "inv-#{inv.id}" end}>
        <:col :let={inv} label="Issue date" class="w-28">
          <span class="whitespace-nowrap">{format_date(inv.issue_date)}</span>
        </:col>
        <:col :let={inv} label={if @filters[:type] == :income, do: "Buyer", else: "Seller"}>
          <div class="flex items-center gap-1">
            <.link
              navigate={~p"/c/#{@current_company.id}/invoices/#{inv.id}"}
              class="text-shad-primary underline-offset-4 hover:underline"
            >
              {counterparty_name(inv, @filters[:type])}
            </.link>
            <.restricted_icon :if={inv.access_restricted} />
          </div>
        </:col>
        <:col :let={inv} label="Amount" class="w-36 text-right">
          <div class="font-mono">{format_amount(inv.net_amount)}</div>
          <div class="font-mono text-xs text-muted-foreground">
            {format_amount(inv.gross_amount)} {inv.currency}
          </div>
        </:col>
        <:col :let={inv} :if={@filters[:type] != :income} label="Status" class="w-28">
          <div class="flex flex-wrap gap-1">
            <.status_badge status={display_status(inv)} />
            <.needs_review_badge
              prediction_status={inv.prediction_status}
              duplicate_status={inv.duplicate_status}
              extraction_status={inv.extraction_status}
              status={inv.status}
            />
            <.extraction_badge
              status={inv.extraction_status}
              duplicate_status={inv.duplicate_status}
            />
          </div>
          <div class="mt-1">
            <.payment_badge status={@payment_statuses[inv.id]} />
          </div>
        </:col>
        <:col :let={inv} :if={@filters[:type] != :income} label="Category">
          <.category_badge category={inv.category} />
        </:col>
        <:col :let={inv} label="Tags">
          <div class="flex flex-wrap gap-1">
            <.badge :for={tag <- inv.tags} variant="info">{tag}</.badge>
            <.badge :if={inv.project_tag} variant="success">{inv.project_tag}</.badge>
          </div>
          <span
            :if={inv.tags == [] && is_nil(inv.project_tag)}
            class="text-muted-foreground"
          >
            -
          </span>
        </:col>
      </.table>

      <.empty_state :if={@invoices == [] && @total_count == 0}>
        No invoices found matching your filters.
      </.empty_state>

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
    </.table_container>
    """
  end
end
