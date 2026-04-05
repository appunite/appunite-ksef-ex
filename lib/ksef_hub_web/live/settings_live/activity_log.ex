defmodule KsefHubWeb.SettingsLive.ActivityLog do
  @moduledoc """
  Settings page showing the company-wide activity log.
  Restricted to admin/owner roles via `:manage_team` permission.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.ActivityLog

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Activity Log")}
  end

  @impl true
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _uri, socket) do
    page = parse_int(params["page"], 1)
    action_prefix = params["filter"]

    result =
      ActivityLog.list_for_company(socket.assigns.current_company.id,
        page: page,
        per_page: 50,
        action_prefix: action_prefix
      )

    {:noreply,
     assign(socket,
       entries: result.entries,
       page: result.page,
       total_pages: result.total_pages,
       total_count: result.total_count,
       filter: action_prefix
     )}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Activity Log
        <:subtitle>Company-wide audit trail of all operations</:subtitle>
      </.header>

      <div class="mt-4 flex items-center gap-2 flex-wrap">
        <.link
          :for={
            {label, value} <- [
              {"All", nil},
              {"Invoices", "invoice"},
              {"Payments", "payment_request"},
              {"Team", "team"},
              {"Categories", "category"},
              {"Credentials", "credential"},
              {"Tokens", "api_token"},
              {"Sync", "sync"},
              {"Bank Accounts", "bank_account"},
              {"Auth", "user"},
              {"Exports", "export"}
            ]
          }
          patch={filter_path(@current_company.id, value, @page)}
          class={[
            "px-2.5 py-1 text-xs rounded-md border transition-colors",
            if(@filter == value,
              do: "bg-shad-primary text-shad-primary-foreground border-shad-primary",
              else: "text-muted-foreground border-border hover:bg-shad-accent"
            )
          ]}
        >
          {label}
        </.link>
      </div>

      <div class="mt-4">
        <div :if={@entries == []} class="text-sm text-muted-foreground italic py-8 text-center">
          No activity recorded yet
        </div>

        <.table :if={@entries != []} rows={@entries} id="activity-log-table">
          <:col :let={entry} label="Time">
            <span class="text-xs text-muted-foreground whitespace-nowrap">
              {format_datetime(entry.inserted_at)}
            </span>
          </:col>
          <:col :let={entry} label="Actor">
            <span class="text-sm font-medium">{entry.actor_label || "System"}</span>
            <span
              :if={entry.actor_type != "user"}
              class="ml-1 text-xs px-1 py-0.5 rounded bg-shad-accent text-shad-accent-foreground"
            >
              {entry.actor_type}
            </span>
          </:col>
          <:col :let={entry} label="Action">
            <span class="text-sm">{humanize_action(entry.action)}</span>
          </:col>
          <:col :let={entry} label="Resource">
            <span class="text-xs text-muted-foreground">
              {entry.resource_type}
            </span>
          </:col>
        </.table>

        <div :if={@total_pages > 1} class="flex items-center justify-between mt-4">
          <span class="text-sm text-muted-foreground">
            Page {@page} of {@total_pages} ({@total_count} entries)
          </span>
          <div class="flex gap-2">
            <.link
              :if={@page > 1}
              patch={page_path(@current_company.id, @filter, @page - 1)}
              class="text-sm px-3 py-1 border border-border rounded-md hover:bg-shad-accent transition-colors"
            >
              Previous
            </.link>
            <.link
              :if={@page < @total_pages}
              patch={page_path(@current_company.id, @filter, @page + 1)}
              class="text-sm px-3 py-1 border border-border rounded-md hover:bg-shad-accent transition-colors"
            >
              Next
            </.link>
          </div>
        </div>
      </div>
    </.settings_layout>
    """
  end

  @spec humanize_action(String.t()) :: String.t()
  defp humanize_action(action) do
    action
    |> String.replace(".", " › ")
    |> String.replace("_", " ")
  end

  @spec format_datetime(NaiveDateTime.t()) :: String.t()
  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @spec filter_path(String.t(), String.t() | nil, pos_integer()) :: String.t()
  defp filter_path(company_id, nil, _page) do
    ~p"/c/#{company_id}/settings/activity-log"
  end

  defp filter_path(company_id, filter, _page) do
    ~p"/c/#{company_id}/settings/activity-log?filter=#{filter}"
  end

  @spec page_path(String.t(), String.t() | nil, pos_integer()) :: String.t()
  defp page_path(company_id, nil, page) do
    ~p"/c/#{company_id}/settings/activity-log?page=#{page}"
  end

  defp page_path(company_id, filter, page) do
    ~p"/c/#{company_id}/settings/activity-log?filter=#{filter}&page=#{page}"
  end

  @spec parse_int(String.t() | nil, integer()) :: integer()
  defp parse_int(nil, default), do: default

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end
end
