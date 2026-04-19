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
  alias KsefHub.Sync.History

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

    tab_counts = compute_tab_counts(company_id, role, socket.assigns)

    {:noreply,
     socket
     |> assign(all_tags: all_tags)
     |> assign(tab_counts: tab_counts)
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
      can_sync: Authorization.can?(role, :trigger_sync),
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
      length(filters[:expense_category_ids] || []) +
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

  def handle_event("clear_filter_field", %{"field" => field}, socket) do
    filters = clear_filter_field(socket.assigns.filters, field)
    query_params = build_query_params(filters, %{})
    company_id = socket.assigns.current_company.id
    {:noreply,
     socket
     |> assign(:open_filter, nil)
     |> push_patch(to: ~p"/c/#{company_id}/invoices?#{query_params}")}
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

  def handle_event("trigger_sync", _params, socket) do
    if Authorization.can?(socket.assigns[:current_role], :trigger_sync) do
      company_id = socket.assigns.current_company.id

      case History.trigger_manual_sync(company_id, actor_opts(socket)) do
        {:ok, _job} ->
          {:noreply, put_flash(socket, :info, "Manual sync triggered.")}

        {:error, :already_running} ->
          {:noreply, put_flash(socket, :error, "A sync is already running.")}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Manual sync failed.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized.")}
    end
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
    |> maybe_put("expense_category_ids", join_list(filters[:expense_category_ids]))
    |> maybe_put_list("tags[]", filters[:tags])
    |> maybe_put("payment_statuses", join_list(filters[:payment_statuses]))
  end

  @spec tab_url(String.t(), map(), atom()) :: String.t()
  defp tab_url(company_id, filters, type) do
    params =
      filter_params_without_page(filters)
      |> Map.delete("type")
      |> Map.put("type", to_string(type))

    ~p"/c/#{company_id}/invoices?#{params}"
  end

  # Single GROUP BY query returning income/expense counts — replaces the old
  # approach that ran two full paginated queries (list + count each) per tab.
  @spec compute_tab_counts(String.t() | nil, atom() | nil, map()) :: %{
          income: non_neg_integer(),
          expense: non_neg_integer()
        }
  defp compute_tab_counts(nil, _role, _assigns), do: %{income: 0, expense: 0}

  defp compute_tab_counts(company_id, role, assigns) do
    user_id = assigns[:current_user] && assigns.current_user.id
    Invoices.count_invoices_by_type(company_id, role: role, user_id: user_id)
  end

  @spec counterparty_nip(map(), atom() | nil) :: String.t() | nil
  defp counterparty_nip(invoice, :income), do: invoice.buyer_nip
  defp counterparty_nip(invoice, _type), do: invoice.seller_nip

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
    type_param = params["type"]
    is_income = type_param == "income"

    %{}
    |> maybe_put_enum(:type, type_param, Invoice, :type)
    |> Map.put_new(:type, :expense)
    |> maybe_put_csv(:statuses, params["statuses"],
      valid: ~w(pending approved rejected duplicate incomplete excluded),
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
        |> maybe_put_csv(:expense_category_ids, params["expense_category_ids"],
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
        <.button :if={@can_sync} variant="outline" phx-click="trigger_sync">
          <.icon name="hero-arrow-path" class="size-4" /> Sync now
        </.button>
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

    <.status_tabs
      active_id={Atom.to_string(@filters[:type])}
      tabs={[
        %{id: "expense", label: "Expense", count: @tab_counts.expense,
          href: tab_url(@current_company.id, @filters, :expense)},
        %{id: "income", label: "Income", count: @tab_counts.income,
          href: tab_url(@current_company.id, @filters, :income)}
      ]}
    />

    <div class="flex items-center gap-2 flex-wrap mb-4">
      <.form for={@form} id="search-filter-form" phx-change="filter" class="contents">
        <.search_input
          name={@form[:query].name}
          value={@form[:query].value}
          placeholder="Search invoices..."
          phx-debounce="300"
          class="w-48 lg:w-64"
        />
      </.form>
      <.form for={@form} id="date-filter-form" phx-change="filter" class="contents">
        <.date_range_picker
          id="invoice-date-range"
          from_name={@form[:date_from].name}
          to_name={@form[:date_to].name}
          from_value={@form[:date_from].value}
          to_value={@form[:date_to].value}
        />
      </.form>
      <.multi_select
        id="status-filter"
        label="Status"
        field="statuses"
        icon="hero-check-circle"
        options={[
          {"Pending", "pending"},
          {"Approved", "approved"},
          {"Rejected", "rejected"},
          {"Duplicate", "duplicate"},
          {"Incomplete", "incomplete"},
          {"Excluded", "excluded"}
        ]}
        selected={Enum.map(@filters[:statuses] || [], &to_string/1)}
        open={@open_filter == "status-filter"}
      />
      <.multi_select
        :if={@filters[:type] == :expense}
        id="category-filter"
        label="Category"
        field="expense_category_ids"
        icon="hero-folder"
        options={Enum.map(@categories, &{category_label(&1), &1.id})}
        selected={@filters[:expense_category_ids] || []}
        searchable={length(@categories) > 6}
        open={@open_filter == "category-filter"}
      />
      <.multi_select
        :if={@filters[:type] != :income}
        id="payment-filter"
        label="Payment"
        field="payment_statuses"
        icon="hero-credit-card"
        options={[{"Paid", "paid"}, {"Pending", "pending"}, {"None", "none"}]}
        selected={@filters[:payment_statuses] || []}
        open={@open_filter == "payment-filter"}
      />
      <.multi_select
        id="tag-filter"
        label="Tag"
        field="tags"
        icon="hero-tag"
        options={Enum.map(@all_tags, &{&1, &1})}
        selected={@filters[:tags] || []}
        searchable={length(@all_tags) > 6}
        open={@open_filter == "tag-filter"}
      />
      <.reset_filters_button :if={@filter_count > 0} />
    </div>

    <!-- Invoice Table -->
    <.table_container>
      <.table
        id="invoices"
        rows={@invoices}
        row_id={fn inv -> "inv-#{inv.id}" end}
        row_click={fn inv -> JS.navigate(~p"/c/#{@current_company.id}/invoices/#{inv.id}") end}
      >
        <%!-- Source dot --%>
        <:col :let={inv} label="" class="w-6">
          <.source_dot source={inv.source} />
        </:col>
        <%!-- Invoice number (truncated for UUID-style) --%>
        <:col :let={inv} label="Number" class="w-44">
          <span class="font-mono text-xs tabular-nums truncate block w-full" title={inv.invoice_number}>
            {inv.invoice_number || "—"}
          </span>
        </:col>
        <%!-- Date: "17 Apr" --%>
        <:col :let={inv} label="Date" class="w-20">
          <span class="font-mono text-xs tabular-nums text-muted-foreground whitespace-nowrap">
            {format_date_short(inv.issue_date)}
          </span>
        </:col>
        <%!-- Counterparty name + NIP below --%>
        <:col
          :let={inv}
          label={if @filters[:type] == :income, do: "Buyer", else: "Seller"}
        >
          <div class="flex items-center gap-1.5">
            <.link
              navigate={~p"/c/#{@current_company.id}/invoices/#{inv.id}"}
              class="text-sm truncate max-w-[200px] hover:underline underline-offset-4"
            >
              {counterparty_name(inv, @filters[:type])}
            </.link>
            <.restricted_icon :if={inv.access_restricted} />
          </div>
          <div
            :if={counterparty_nip(inv, @filters[:type])}
            class="font-mono text-[11px] text-muted-foreground mt-0.5"
          >
            {counterparty_nip(inv, @filters[:type])}
          </div>
        </:col>
        <%!-- Amount: gross on top, net below --%>
        <:col :let={inv} label="Amount" class="w-36 text-right">
          <.invoice_amount gross={inv.gross_amount} net={inv.net_amount} currency={inv.currency} />
        </:col>
        <%!-- Kind badge --%>
        <:col :let={inv} label="Kind" class="w-24">
          <.invoice_kind_badge kind={inv.invoice_kind} />
        </:col>
        <%!-- Category: shown on expense, empty spacer on income (keeps layout balanced) --%>
        <:col
          :let={inv}
          label={if @filters[:type] == :expense, do: "Category", else: ""}
          class={if @filters[:type] == :income, do: "w-40", else: nil}
        >
          <.category_badge
            :if={@filters[:type] == :expense}
            category={inv.category}
            confidence={inv.prediction_expense_category_confidence}
            prediction_status={inv.prediction_status}
          />
        </:col>
        <%!-- Status: shown on expense, empty spacer on income (keeps layout balanced) --%>
        <:col :let={inv} label={if @filters[:type] == :expense, do: "Status", else: ""} class="w-32">
          <div :if={@filters[:type] == :expense} class="flex flex-wrap gap-1">
            <.status_badge status={display_status(inv)} />
            <.needs_review_badge
              prediction_status={inv.prediction_status}
              duplicate_status={inv.duplicate_status}
              extraction_status={inv.extraction_status}
              status={inv.expense_approval_status}
            />
          </div>
        </:col>
        <:action>
          <.icon
            name="hero-chevron-right"
            class="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
          />
        </:action>
      </.table>

      <.empty_state :if={@invoices == [] && @total_count == 0}>
        No data for selected period
      </.empty_state>

      <div class="px-4 py-3">
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
