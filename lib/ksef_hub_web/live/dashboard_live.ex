defmodule KsefHubWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing invoice counts, expense breakdown,
  charts, and sync status.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.InvoiceComponents, only: [format_datetime: 1, format_date: 1]

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
  def handle_event("filter", %{"filters" => params}, socket) do
    query_params =
      %{}
      |> put_non_empty("billing_date_from", params["billing_date_from"])
      |> put_non_empty("billing_date_to", params["billing_date_to"])
      |> put_non_empty("category_id", params["category_id"])
      |> put_non_empty("tag_id", params["tag_id"])

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/dashboard?#{query_params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/dashboard")}
  end

  def handle_event("remove_filter", %{"key" => key}, socket) do
    query_params =
      filter_query_params(socket.assigns.filters)
      |> Map.delete(key)

    company_id = socket.assigns.current_company.id
    {:noreply, push_patch(socket, to: ~p"/c/#{company_id}/dashboard?#{query_params}")}
  end

  @spec assign_defaults(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_defaults(socket) do
    assign(socket,
      filters: %{},
      form: build_filters_form(%{}),
      active_filters: [],
      filter_count: 0,
      categories: [],
      tags: [],
      expense_monthly: [],
      expense_by_category: [],
      income_summary: %{current_month: Decimal.new(0), last_month: Decimal.new(0)}
    )
  end

  @spec assign_filter_state(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  defp assign_filter_state(socket, filters) do
    categories = socket.assigns[:categories] || []
    tags = socket.assigns[:tags] || []
    active_filters = build_active_filters(filters, categories, tags)

    assign(socket,
      filters: filters,
      form: build_filters_form(filters),
      active_filters: active_filters,
      filter_count: length(active_filters)
    )
  end

  @spec build_filters_form(map()) :: Phoenix.HTML.Form.t()
  defp build_filters_form(filters) do
    %{
      "billing_date_from" =>
        (filters[:billing_date_from] && Date.to_iso8601(filters[:billing_date_from])) || "",
      "billing_date_to" =>
        (filters[:billing_date_to] && Date.to_iso8601(filters[:billing_date_to])) || "",
      "category_id" => filters[:category_id] || "",
      "tag_id" => first_tag_id(filters) || ""
    }
    |> to_form(as: :filters)
  end

  @spec build_active_filters(map(), list(), list()) :: [map()]
  defp build_active_filters(filters, categories, tags) do
    []
    |> maybe_add_chip(filters[:category_id], "category_id", "Category", fn id ->
      case Enum.find(categories, &(&1.id == id)) do
        nil -> id
        cat -> cat.name || cat.identifier
      end
    end)
    |> maybe_add_chip(first_tag_id(filters), "tag_id", "Tag", fn id ->
      case Enum.find(tags, &(&1.id == id)) do
        nil -> id
        tag -> tag.name
      end
    end)
    |> maybe_add_chip(
      filters[:billing_date_from],
      "billing_date_from",
      "From",
      &Date.to_iso8601/1
    )
    |> maybe_add_chip(filters[:billing_date_to], "billing_date_to", "To", &Date.to_iso8601/1)
    |> Enum.reverse()
  end

  @spec maybe_add_chip(list(), any(), String.t(), String.t(), (any() -> String.t())) :: list()
  defp maybe_add_chip(acc, nil, _key, _label, _formatter), do: acc

  defp maybe_add_chip(acc, value, key, label, formatter) do
    [%{key: key, label: label, value: formatter.(value)} | acc]
  end

  @spec first_tag_id(map()) :: String.t() | nil
  defp first_tag_id(%{tag_ids: [id | _]}), do: id
  defp first_tag_id(_), do: nil

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
          tags: Invoices.list_tags(company.id, :expense)
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
    |> maybe_parse_date(:billing_date_from, params["billing_date_from"])
    |> maybe_parse_date(:billing_date_to, params["billing_date_to"])
    |> maybe_parse_string(:category_id, params["category_id"])
    |> maybe_parse_tag_id(params["tag_id"])
  end

  @spec maybe_parse_date(map(), atom(), String.t() | nil) :: map()
  defp maybe_parse_date(filters, _key, nil), do: filters
  defp maybe_parse_date(filters, _key, ""), do: filters

  defp maybe_parse_date(filters, key, value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> Map.put(filters, key, date)
      _ -> filters
    end
  end

  @spec maybe_parse_string(map(), atom(), String.t() | nil) :: map()
  defp maybe_parse_string(filters, _key, nil), do: filters
  defp maybe_parse_string(filters, _key, ""), do: filters
  defp maybe_parse_string(filters, key, value), do: Map.put(filters, key, value)

  @spec maybe_parse_tag_id(map(), String.t() | nil) :: map()
  defp maybe_parse_tag_id(filters, nil), do: filters
  defp maybe_parse_tag_id(filters, ""), do: filters
  defp maybe_parse_tag_id(filters, tag_id), do: Map.put(filters, :tag_ids, [tag_id])

  @spec filter_query_params(map()) :: map()
  defp filter_query_params(filters) do
    %{}
    |> put_non_empty(
      "billing_date_from",
      filters[:billing_date_from] && Date.to_iso8601(filters[:billing_date_from])
    )
    |> put_non_empty(
      "billing_date_to",
      filters[:billing_date_to] && Date.to_iso8601(filters[:billing_date_to])
    )
    |> put_non_empty("category_id", filters[:category_id])
    |> put_non_empty("tag_id", first_tag_id(filters))
  end

  @spec put_non_empty(map(), String.t(), String.t() | nil) :: map()
  defp put_non_empty(map, _key, nil), do: map
  defp put_non_empty(map, _key, ""), do: map
  defp put_non_empty(map, key, value), do: Map.put(map, key, value)

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
    <.form :if={@current_company} for={@form} phx-change="filter" class="contents">
      <.filter_bar active_filters={@active_filters} filter_count={@filter_count}>
        <:filter_fields>
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
                {if(cat.emoji, do: "#{cat.emoji} ", else: "")}{cat.name || cat.identifier}
              </option>
            </select>
          </div>

          <div :if={@tags != []} class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">Tag</label>
            <select
              name={@form[:tag_id].name}
              class="w-full h-9 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="">All</option>
              <option
                :for={tag <- @tags}
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
              name={@form[:billing_date_from].name}
              value={@form[:billing_date_from].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>

          <div class="space-y-1">
            <label class="block text-xs font-medium text-muted-foreground">To</label>
            <input
              type="date"
              name={@form[:billing_date_to].name}
              value={@form[:billing_date_to].value}
              class="w-full h-9 rounded-md border border-input bg-background px-3 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            />
          </div>
        </:filter_fields>
      </.filter_bar>
    </.form>

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
