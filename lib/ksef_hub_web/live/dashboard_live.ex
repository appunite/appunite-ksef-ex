defmodule KsefHubWeb.DashboardLive do
  @moduledoc """
  LiveView for the main dashboard showing invoice counts, expense breakdown, and sync status.
  """
  use KsefHubWeb, :live_view

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
  end

  @spec count_type(map(), String.t()) :: non_neg_integer()
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

  @spec format_datetime(DateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: "Never"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  @spec format_date(Date.t() | nil) :: String.t()
  defp format_date(nil), do: "-"
  defp format_date(date), do: Calendar.strftime(date, "%Y-%m-%d")

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
