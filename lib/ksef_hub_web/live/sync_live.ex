defmodule KsefHubWeb.SyncLive do
  @moduledoc """
  LiveView page displaying KSeF sync history and manual sync trigger.
  Subscribes to PubSub for real-time updates when syncs complete.
  """

  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Authorization
  alias KsefHub.Sync.History

  @doc "Subscribes to sync PubSub topic and loads sync job history."
  @impl true
  def mount(_params, _session, socket) do
    if not Authorization.can?(socket.assigns[:current_role], :view_syncs) do
      {:ok,
       socket
       |> put_flash(:error, "You don't have permission to view syncs.")
       |> redirect(to: ~p"/c/#{socket.assigns.current_company.id}/invoices")}
    else
      do_mount_sync(socket)
    end
  end

  @spec do_mount_sync(Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  defp do_mount_sync(socket) do
    company = socket.assigns.current_company

    if connected?(socket) && company do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, "sync:status:#{company.id}")
    end

    jobs = if company, do: History.list_sync_jobs(company.id), else: []

    {:ok,
     socket
     |> assign(page_title: "Syncs", jobs_count: length(jobs))
     |> stream(:jobs, jobs)}
  end

  @doc "Handles PubSub sync completion events by refreshing the job list."
  @impl true
  def handle_info({:sync_completed, _stats}, socket) do
    company = socket.assigns.current_company
    jobs = if company, do: History.list_sync_jobs(company.id), else: []
    {:noreply, socket |> assign(jobs_count: length(jobs)) |> stream(:jobs, jobs, reset: true)}
  end

  @doc "Handles manual sync trigger with nil company guard and full error handling."
  @impl true
  def handle_event("trigger_sync", _params, %{assigns: %{current_company: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "No company selected.")}
  end

  def handle_event("trigger_sync", _params, socket) do
    company = socket.assigns.current_company

    case History.trigger_manual_sync(company.id) do
      {:ok, _job} ->
        jobs = History.list_sync_jobs(company.id)

        {:noreply,
         socket
         |> assign(jobs_count: length(jobs))
         |> stream(:jobs, jobs, reset: true)
         |> put_flash(:info, "Manual sync triggered.")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A sync is already running.")}

      {:error, reason} ->
        Logger.error("Manual sync failed: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Manual sync failed.")}
    end
  end

  @doc "Renders the sync history page with job table and manual trigger button."
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Syncs
      <:subtitle>KSeF invoice sync history</:subtitle>
      <:actions>
        <button phx-click="trigger_sync" class="btn btn-primary btn-sm">
          <.icon name="hero-arrow-path" class="size-4" /> Sync Now
        </button>
      </:actions>
    </.header>

    <div class="mt-6 overflow-x-auto">
      <.table id="syncs" rows={@streams.jobs} row_id={fn {id, _} -> id end}>
        <:col :let={{_id, job}} label="Time">
          {format_datetime(job.inserted_at)}
        </:col>
        <:col :let={{_id, job}} label="Duration">
          {format_duration(job.duration)}
        </:col>
        <:col :let={{_id, job}} label="Status">
          <span class={[
            "inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border",
            status_classes(job.state)
          ]}>
            {job.state}
          </span>
        </:col>
        <:col :let={{_id, job}} label="Income">
          <span class="font-mono">{job.income_count || "-"}</span>
        </:col>
        <:col :let={{_id, job}} label="Expense">
          <span class="font-mono">{job.expense_count || "-"}</span>
        </:col>
        <:col :let={{_id, job}} label="Error">
          <span
            :if={job.error}
            class="text-error/80 text-xs truncate max-w-xs inline-block"
            title={job.error}
          >
            {truncate(job.error, 80)}
          </span>
        </:col>
      </.table>
    </div>

    <div :if={@jobs_count == 0} class="text-center py-12">
      <.icon name="hero-arrow-path" class="size-8 text-base-content/20 mx-auto mb-2" />
      <p class="text-base-content/60">No sync runs yet.</p>
    </div>
    """
  end

  @spec format_datetime(DateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  @spec format_duration(integer() | nil) :: String.t()
  defp format_duration(nil), do: "-"

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds}s"
  end

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  @spec status_classes(String.t()) :: String.t()
  defp status_classes("completed"), do: "bg-success/10 text-success border-success/20"
  defp status_classes("executing"), do: "bg-info/10 text-info border-info/20"
  defp status_classes("retryable"), do: "bg-warning/10 text-warning border-warning/20"
  defp status_classes("discarded"), do: "bg-error/10 text-error border-error/20"
  defp status_classes(_), do: "bg-base-200 text-base-content/60 border-base-300"

  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  defp truncate(str, max) when byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max), do: str
end
