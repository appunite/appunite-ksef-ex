defmodule KsefHubWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing invoice counts, expense breakdown,
  charts, and sync status.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.InvoiceComponents, only: [format_datetime: 1, format_date: 1]
  import KsefHubWeb.FilterHelpers

  alias KsefHub.Authorization
  alias KsefHub.Credentials
  alias KsefHub.Invoices

  @doc "Subscribes to sync PubSub and loads dashboard data."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    company = socket.assigns.current_company

    if connected?(socket) && company do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, "sync:status:#{company.id}")
    end

    socket =
      socket
      |> assign_defaults()
      |> load_data()

    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    filters = parse_filters(params)

    socket =
      socket
      |> assign_filter_state(filters)
      |> load_chart_data()
      |> push_chart_events()

    {:noreply, socket}
  end

  @doc "Reloads dashboard data when a sync completes."
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:sync_completed, _stats}, socket) do
    socket =
      socket
      |> load_data()
      |> load_chart_data()
      |> push_chart_events()

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params = build_query_params(socket.assigns.filters, params)
    company_id = socket.assigns.current_company.id

    {:noreply,
     push_patch(socket, to: ~p"/c/#{company_id}/dashboard?#{query_params}", replace: true)}
  end

  def handle_event("toggle_filter", %{"field" => field, "value" => value}, socket) do
    filters = toggle_filter_value(socket.assigns.filters, field, value)
    query_params = build_query_params(filters, %{})
    company_id = socket.assigns.current_company.id

    {:noreply,
     push_patch(socket, to: ~p"/c/#{company_id}/dashboard?#{query_params}", replace: true)}
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
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/dashboard", replace: true)}
  end

  @spec assign_defaults(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_defaults(socket) do
    assign(socket,
      filters: %{},
      form: build_filters_form(%{}),
      filter_count: 0,
      open_filter: nil,
      categories: [],
      tags: [],
      expense_monthly: [],
      expense_by_category: [],
      income_summary: %{current_month: Decimal.new(0), last_month: Decimal.new(0)}
    )
  end

  @spec assign_filter_state(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp assign_filter_state(socket, filters) do
    filter_count =
      length(filters[:category_ids] || []) +
        length(filters[:tags] || []) +
        if(filters[:billing_date_from], do: 1, else: 0) +
        if(filters[:billing_date_to], do: 1, else: 0)

    assign(socket,
      filters: filters,
      form: build_filters_form(filters),
      filter_count: filter_count
    )
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
    %{
      "billing_date_from" =>
        (filters[:billing_date_from] && Date.to_iso8601(filters[:billing_date_from])) || "",
      "billing_date_to" =>
        (filters[:billing_date_to] && Date.to_iso8601(filters[:billing_date_to])) || ""
    }
    |> to_form(as: :filters)
  end

  @spec load_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_data(socket) do
    case socket.assigns.current_company do
      nil ->
        assign(socket,
          page_title: "Dashboard",
          can_view_all_types:
            Authorization.can?(socket.assigns[:current_role], :view_all_invoice_types),
          total_income: 0,
          total_expense: 0,
          total_invoices: 0,
          pending_expense: 0,
          approved_expense: 0,
          rejected_expense: 0,
          credential: nil,
          last_sync_at: nil,
          cert_expires_at: nil,
          cert_active: false
        )

      company ->
        counts = Invoices.count_by_type_and_status(company.id)
        credential = Credentials.get_active_credential(company.id)
        user_cert = Credentials.get_certificate_for_company(company.id)

        can_view_all_types =
          Authorization.can?(socket.assigns[:current_role], :view_all_invoice_types)

        total_income = if can_view_all_types, do: count_type(counts, :income), else: 0
        total_expense = count_type(counts, :expense)
        pending_expense = Map.get(counts, {:expense, :pending}, 0)
        approved_expense = Map.get(counts, {:expense, :approved}, 0)
        rejected_expense = Map.get(counts, {:expense, :rejected}, 0)

        assign(socket,
          page_title: "Dashboard",
          can_view_all_types: can_view_all_types,
          total_income: total_income,
          total_expense: total_expense,
          total_invoices: total_income + total_expense,
          pending_expense: pending_expense,
          approved_expense: approved_expense,
          rejected_expense: rejected_expense,
          credential: credential,
          last_sync_at: credential && credential.last_sync_at,
          cert_expires_at: user_cert && user_cert.not_after,
          cert_active: credential != nil && credential.is_active && user_cert != nil,
          categories: Invoices.list_categories(company.id),
          tags:
            Invoices.list_distinct_tags(company.id, :expense,
              role: socket.assigns[:current_role],
              user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
            )
        )
    end
  end

  @spec load_chart_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_chart_data(socket) do
    case socket.assigns.current_company do
      nil ->
        socket

      company ->
        filters = socket.assigns.filters
        can_view_all_types = socket.assigns[:can_view_all_types]

        income_summary =
          if can_view_all_types,
            do: Invoices.income_monthly_summary(company.id),
            else: %{current_month: Decimal.new(0), last_month: Decimal.new(0)}

        assign(socket,
          expense_monthly: Invoices.expense_monthly_totals(company.id, filters),
          expense_by_category: Invoices.expense_by_category(company.id, filters),
          income_summary: income_summary
        )
    end
  end

  @spec push_chart_events(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp push_chart_events(socket) do
    if connected?(socket) do
      socket
      |> push_event("expense-bar-data", bar_chart_payload(socket.assigns.expense_monthly))
      |> push_event(
        "category-donut-data",
        donut_chart_payload(socket.assigns.expense_by_category)
      )
    else
      socket
    end
  end

  @spec bar_chart_payload([map()]) :: map()
  defp bar_chart_payload(monthly_data) do
    {labels, values} =
      Enum.reduce(monthly_data, {[], []}, fn row, {ls, vs} ->
        {[format_month_label(row.billing_date) | ls], [decimal_to_float(row.net_total) | vs]}
      end)

    %{labels: Enum.reverse(labels), values: Enum.reverse(values)}
  end

  @spec donut_chart_payload([map()]) :: map()
  defp donut_chart_payload(category_data) do
    {labels, values} =
      Enum.reduce(category_data, {[], []}, fn row, {ls, vs} ->
        label =
          if row.emoji, do: "#{row.emoji} #{row.category_name}", else: row.category_name

        {[label | ls], [decimal_to_float(row.net_total) | vs]}
      end)

    %{labels: Enum.reverse(labels), values: Enum.reverse(values)}
  end

  @spec format_month_label(Date.t()) :: String.t()
  defp format_month_label(date) do
    Calendar.strftime(date, "%b %Y")
  end

  @spec decimal_to_float(Decimal.t() | nil) :: float()
  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)

  @spec parse_filters(map()) :: map()
  defp parse_filters(params) do
    %{}
    |> maybe_put_date(:billing_date_from, params["billing_date_from"])
    |> maybe_put_date(:billing_date_to, params["billing_date_to"])
    |> maybe_put_csv(:category_ids, params["category_ids"],
      validate: fn id -> match?({:ok, _}, Ecto.UUID.cast(id)) end
    )
    |> maybe_put_csv(:tags, params["tags"])
  end

  @spec build_query_params(map(), map()) :: map()
  defp build_query_params(filters, form_params) do
    %{}
    |> maybe_put(
      "billing_date_from",
      form_params["billing_date_from"] || date_to_string(filters[:billing_date_from])
    )
    |> maybe_put(
      "billing_date_to",
      form_params["billing_date_to"] || date_to_string(filters[:billing_date_to])
    )
    |> maybe_put("category_ids", join_list(filters[:category_ids]))
    |> maybe_put("tags", join_list(filters[:tags]))
  end

  @spec count_type(map(), atom()) :: non_neg_integer()
  defp count_type(counts, type) do
    counts
    |> Enum.filter(fn {{t, _s}, _c} -> t == type end)
    |> Enum.map(fn {_, c} -> c end)
    |> Enum.sum()
  end

  @spec format_decimal(Decimal.t() | nil) :: String.t()
  defp format_decimal(%Decimal{} = d) do
    d
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end

  defp format_decimal(nil), do: "0.00"

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Dashboard
      <:subtitle>Invoice overview</:subtitle>
    </.header>

    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
      <.stat_card title="Total Invoices" value={@total_invoices} icon="hero-document-text" />
      <.stat_card
        :if={@can_view_all_types}
        title="Income"
        value={@total_income}
        icon="hero-arrow-down-tray"
        color="text-success"
      />
      <.stat_card
        title="Expenses"
        value={@total_expense}
        icon="hero-arrow-up-tray"
        color="text-warning"
      />
      <.stat_card title="Pending Review" value={@pending_expense} icon="hero-clock" color="text-info" />
    </div>

    <!-- Filters -->
    <div :if={@current_company} class="space-y-2 mt-4 mb-6">
      <div class="flex items-center gap-2 flex-wrap">
        <.multi_select
          id="category-filter"
          label="Category"
          field="category_ids"
          options={Enum.map(@categories, &{category_label(&1), &1.id})}
          selected={@filters[:category_ids] || []}
          searchable={length(@categories) > 6}
          open={@open_filter == "category-filter"}
        />
        <.multi_select
          :if={@tags != []}
          id="tag-filter"
          label="Tag"
          field="tags"
          options={Enum.map(@tags, &{&1, &1})}
          selected={@filters[:tags] || []}
          searchable={length(@tags) > 6}
          open={@open_filter == "tag-filter"}
        />

        <.form for={@form} id="dashboard-date-form" phx-change="filter" class="contents">
          <.date_range_picker
            id="billing-date-range"
            from_name={@form[:billing_date_from].name}
            to_name={@form[:billing_date_to].name}
            from_value={@form[:billing_date_from].value}
            to_value={@form[:billing_date_to].value}
          />
        </.form>

        <.reset_filters_button :if={@filter_count > 0} />
      </div>
    </div>

    <!-- Charts -->
    <div :if={@current_company} class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <.card padding="p-5">
        <h2 class="text-base font-semibold mb-3">Monthly Expenses</h2>
        <div id="expense-bar-chart" phx-hook="ExpenseBarChart" phx-update="ignore" class="h-64">
          <canvas></canvas>
        </div>
      </.card>

      <.card padding="p-5">
        <h2 class="text-base font-semibold mb-3">Expenses by Category</h2>
        <div id="category-donut-chart" phx-hook="CategoryDonutChart" phx-update="ignore" class="h-64">
          <canvas></canvas>
        </div>
      </.card>
    </div>

    <!-- Income Summary -->
    <div
      :if={@can_view_all_types && @current_company}
      class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-6"
    >
      <.stat_card
        title="Income This Month"
        value={format_decimal(@income_summary.current_month) <> " PLN"}
        icon="hero-banknotes"
        color="text-success"
      />
      <.stat_card
        title="Income Last Month"
        value={format_decimal(@income_summary.last_month) <> " PLN"}
        icon="hero-banknotes"
        color="text-muted-foreground"
      />
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
      <!-- Expense Breakdown -->
      <.card padding="p-5">
        <h2 class="text-base font-semibold mb-3">Expense Status</h2>
        <div class="space-y-2.5">
          <div class="flex items-center justify-between">
            <.badge variant="warning">Pending</.badge>
            <span class="font-mono text-sm">{@pending_expense}</span>
          </div>
          <div class="flex items-center justify-between">
            <.badge variant="success">Approved</.badge>
            <span class="font-mono text-sm">{@approved_expense}</span>
          </div>
          <div class="flex items-center justify-between">
            <.badge variant="error">Rejected</.badge>
            <span class="font-mono text-sm">{@rejected_expense}</span>
          </div>
        </div>
      </.card>
      
    <!-- Sync Status -->
      <.card padding="p-5">
        <h2 class="text-base font-semibold mb-3">Sync Status</h2>
        <div class="space-y-3">
          <div class="flex justify-between items-center">
            <span class="text-sm text-muted-foreground">Certificate</span>
            <.badge
              :if={
                @cert_active && @cert_expires_at &&
                  Date.compare(@cert_expires_at, Date.utc_today()) == :lt
              }
              variant="warning"
            >
              Expired
            </.badge>
            <.badge
              :if={
                @cert_active &&
                  (!@cert_expires_at || Date.compare(@cert_expires_at, Date.utc_today()) != :lt)
              }
              variant="success"
            >
              Active
            </.badge>
            <.badge :if={!@cert_active} variant="error">Not configured</.badge>
          </div>
          <div :if={@credential} class="flex justify-between items-center">
            <span class="text-sm text-muted-foreground">NIP</span>
            <span class="font-mono text-sm">{@credential.nip}</span>
          </div>
          <div class="flex justify-between items-center">
            <span class="text-sm text-muted-foreground">Last Sync</span>
            <span class="text-sm">{format_datetime(@last_sync_at)}</span>
          </div>
          <div :if={@cert_expires_at} class="flex justify-between items-center">
            <span class="text-sm text-muted-foreground">Cert Expires</span>
            <span class={["text-sm", cert_expiry_class(@cert_expires_at)]}>
              {format_date(@cert_expires_at)}
            </span>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  @spec stat_card(map()) :: Phoenix.LiveView.Rendered.t()
  defp stat_card(assigns) do
    assigns = assign_new(assigns, :color, fn -> "text-foreground" end)

    ~H"""
    <div class="border border-border rounded-xl p-4 flex items-center justify-between">
      <div>
        <div class="text-sm text-muted-foreground">{@title}</div>
        <div class={"text-2xl font-bold #{@color}"}>{@value}</div>
      </div>
      <div class={@color}>
        <.icon name={@icon} class="size-6" />
      </div>
    </div>
    """
  end

  @spec cert_expiry_class(Date.t() | nil) :: String.t()
  defp cert_expiry_class(nil), do: ""

  defp cert_expiry_class(date) do
    days_left = Date.diff(date, Date.utc_today())

    cond do
      days_left < 7 -> "text-error font-bold"
      days_left < 30 -> "text-warning"
      true -> "text-success"
    end
  end
end
