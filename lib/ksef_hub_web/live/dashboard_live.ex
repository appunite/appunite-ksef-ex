defmodule KsefHubWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing invoice counts, expense breakdown, and sync status.
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

    {:ok, load_data(socket)}
  end

  @doc "Reloads dashboard data when a sync completes."
  @impl true
  @spec handle_info(term(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:sync_completed, _stats}, socket) do
    {:noreply, load_data(socket)}
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
          cert_active: credential != nil && credential.is_active && user_cert != nil
        )
    end
  end

  @spec count_type(map(), atom()) :: non_neg_integer()
  defp count_type(counts, type) do
    counts
    |> Enum.filter(fn {{t, _s}, _c} -> t == type end)
    |> Enum.map(fn {_, c} -> c end)
    |> Enum.sum()
  end

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

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-8">
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
