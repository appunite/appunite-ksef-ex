defmodule KsefHubWeb.SyncLive do
  @moduledoc """
  LiveView page displaying KSeF sync history and manual sync trigger.
  Subscribes to PubSub for real-time updates when syncs complete.
  """

  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  require Logger

  import KsefHubWeb.InvoiceComponents, only: [local_datetime: 1]

  alias KsefHub.Authorization
  alias KsefHub.Sync.History

  @doc "Subscribes to sync PubSub topic and loads sync job history."
  @impl true
  def mount(_params, _session, socket) do
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
    if Authorization.can?(socket.assigns[:current_role], :trigger_sync) do
      do_trigger_sync(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to trigger syncs.")}
    end
  end

  @spec do_trigger_sync(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp do_trigger_sync(socket) do
    company = socket.assigns.current_company

    case History.trigger_manual_sync(company.id, actor_opts(socket)) do
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
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Syncs
        <:subtitle>KSeF invoice sync history</:subtitle>
        <:actions>
          <.button :if={Authorization.can?(@current_role, :trigger_sync)} phx-click="trigger_sync">
            <.icon name="hero-arrow-path" class="size-4" /> Sync Now
          </.button>
        </:actions>
      </.header>

      <.table_container :if={@jobs_count > 0} class="mt-6">
        <.table id="syncs" rows={@streams.jobs} row_id={fn {id, _} -> id end}>
          <:col :let={{id, job}} label="Time">
            <.local_datetime at={job.inserted_at} id={"#{id}-time"} />
          </:col>
          <:col :let={{_id, job}} label="Duration">
            {format_duration(job.duration)}
          </:col>
          <:col :let={{_id, job}} label="Status">
            <.badge variant={sync_badge_variant(job.state)}>{job.state}</.badge>
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
              class="text-shad-destructive/80 text-xs truncate max-w-xs inline-block"
              title={job.error}
            >
              {truncate(job.error, 80)}
            </span>
          </:col>
        </.table>
      </.table_container>

      <.empty_state
        :if={@jobs_count == 0}
        icon="hero-arrow-path"
        title="No sync jobs yet"
        description="KSeF sync runs hourly, or trigger one manually."
        class="mt-6"
      />
    </.settings_layout>
    """
  end

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

  @spec sync_badge_variant(String.t()) :: String.t()
  defp sync_badge_variant("completed"), do: "success"
  defp sync_badge_variant("executing"), do: "info"
  defp sync_badge_variant("retryable"), do: "warning"
  defp sync_badge_variant("discarded"), do: "error"
  defp sync_badge_variant(_), do: "muted"

  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  defp truncate(str, max) when byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max), do: str
end
