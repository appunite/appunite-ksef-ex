defmodule KsefHubWeb.SyncLive do
  @moduledoc """
  LiveView page displaying KSeF sync history and manual sync trigger.
  Subscribes to PubSub for real-time updates when syncs complete.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Sync.History

  @impl true
  def mount(_params, _session, socket) do
    company = socket.assigns.current_company

    if connected?(socket) && company do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, "sync:status:#{company.id}")
    end

    jobs = if company, do: History.list_sync_jobs(company.id), else: []

    {:ok,
     assign(socket,
       page_title: "Syncs",
       jobs: jobs
     )}
  end

  @impl true
  def handle_info({:sync_completed, _stats}, socket) do
    company = socket.assigns.current_company
    jobs = if company, do: History.list_sync_jobs(company.id), else: []
    {:noreply, assign(socket, jobs: jobs)}
  end

  @impl true
  def handle_event("trigger_sync", _params, socket) do
    company = socket.assigns.current_company

    case History.trigger_manual_sync(company.id) do
      {:ok, _job} ->
        # Reload immediately to show the scheduled/executing job
        jobs = History.list_sync_jobs(company.id)
        {:noreply, socket |> assign(jobs: jobs) |> put_flash(:info, "Manual sync triggered.")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A sync is already running.")}
    end
  end

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
      <.table id="syncs" rows={@jobs} row_id={fn j -> "sync-#{j.id}" end}>
        <:col :let={job} label="Time">
          {format_datetime(job.inserted_at)}
        </:col>
        <:col :let={job} label="Duration">
          {format_duration(job.duration)}
        </:col>
        <:col :let={job} label="Status">
          <span class={["badge badge-sm", status_badge(job.state)]}>
            {job.state}
          </span>
        </:col>
        <:col :let={job} label="Income">
          <span class="font-mono">{job.income_count || "-"}</span>
        </:col>
        <:col :let={job} label="Expense">
          <span class="font-mono">{job.expense_count || "-"}</span>
        </:col>
        <:col :let={job} label="Error">
          <span
            :if={job.error}
            class="text-error text-xs truncate max-w-xs inline-block"
            title={job.error}
          >
            {truncate(job.error, 80)}
          </span>
        </:col>
      </.table>
    </div>

    <p :if={@jobs == []} class="text-center text-base-content/60 py-8">
      No sync runs yet.
    </p>
    """
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_duration(nil), do: "-"

  defp format_duration(seconds) when seconds < 60 do
    "#{seconds}s"
  end

  defp format_duration(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    "#{minutes}m #{secs}s"
  end

  defp status_badge("completed"), do: "badge-success"
  defp status_badge("executing"), do: "badge-info"
  defp status_badge("retryable"), do: "badge-warning"
  defp status_badge("discarded"), do: "badge-error"
  defp status_badge("scheduled"), do: "badge-ghost"
  defp status_badge("available"), do: "badge-ghost"
  defp status_badge(_), do: "badge-ghost"

  defp truncate(str, max) when byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max), do: str
end
