defmodule KsefHubWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing invoice counts, expense breakdown, and sync status.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Credentials
  alias KsefHub.Invoices

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, "sync:status")
    end

    {:ok, load_data(socket)}
  end

  @impl true
  def handle_info({:sync_completed, _stats}, socket) do
    {:noreply, load_data(socket)}
  end

  defp load_data(socket) do
    counts = Invoices.count_by_type_and_status()
    credential = Credentials.get_active_credential()

    total_income = count_type(counts, "income")
    total_expense = count_type(counts, "expense")
    pending_expense = Map.get(counts, {"expense", "pending"}, 0)
    approved_expense = Map.get(counts, {"expense", "approved"}, 0)
    rejected_expense = Map.get(counts, {"expense", "rejected"}, 0)

    assign(socket,
      page_title: "Dashboard",
      total_income: total_income,
      total_expense: total_expense,
      total_invoices: total_income + total_expense,
      pending_expense: pending_expense,
      approved_expense: approved_expense,
      rejected_expense: rejected_expense,
      credential: credential,
      last_sync_at: credential && credential.last_sync_at,
      cert_expires_at: credential && credential.certificate_expires_at,
      cert_active: credential != nil && credential.is_active
    )
  end

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
      <:subtitle>KSeF Hub overview</:subtitle>
    </.header>

    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
      <.stat_card title="Total Invoices" value={@total_invoices} icon="hero-document-text" />
      <.stat_card
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
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-base">Expense Status</h2>
          <div class="overflow-x-auto">
            <table class="table table-sm">
              <tbody>
                <tr>
                  <td>
                    <span class="badge badge-warning badge-sm">Pending</span>
                  </td>
                  <td class="text-right font-mono">{@pending_expense}</td>
                </tr>
                <tr>
                  <td>
                    <span class="badge badge-success badge-sm">Approved</span>
                  </td>
                  <td class="text-right font-mono">{@approved_expense}</td>
                </tr>
                <tr>
                  <td>
                    <span class="badge badge-error badge-sm">Rejected</span>
                  </td>
                  <td class="text-right font-mono">{@rejected_expense}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
      
    <!-- Sync Status -->
      <div class="card bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title text-base">Sync Status</h2>
          <div class="space-y-3">
            <div class="flex justify-between items-center">
              <span class="text-sm text-base-content/70">Certificate</span>
              <span :if={@cert_active} class="badge badge-success badge-sm">Active</span>
              <span :if={!@cert_active} class="badge badge-error badge-sm">Not configured</span>
            </div>
            <div :if={@credential} class="flex justify-between items-center">
              <span class="text-sm text-base-content/70">NIP</span>
              <span class="font-mono text-sm">{@credential.nip}</span>
            </div>
            <div class="flex justify-between items-center">
              <span class="text-sm text-base-content/70">Last Sync</span>
              <span class="text-sm">{format_datetime(@last_sync_at)}</span>
            </div>
            <div :if={@cert_expires_at} class="flex justify-between items-center">
              <span class="text-sm text-base-content/70">Cert Expires</span>
              <span class={["text-sm", cert_expiry_class(@cert_expires_at)]}>
                {format_date(@cert_expires_at)}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :color, fn -> "text-base-content" end)

    ~H"""
    <div class="stat bg-base-100 shadow-sm rounded-box">
      <div class={"stat-figure #{@color}"}>
        <.icon name={@icon} class="size-6" />
      </div>
      <div class="stat-title">{@title}</div>
      <div class={"stat-value #{@color}"}>{@value}</div>
    </div>
    """
  end

  defp format_datetime(nil), do: "Never"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp format_date(nil), do: "-"
  defp format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

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
