defmodule KsefHubWeb.CompanyLive.Index do
  @moduledoc """
  LiveView for listing companies.

  Company creation and editing is handled by `KsefHubWeb.CompanyLive.Form`.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Authorization
  alias KsefHub.Companies

  @doc "Loads companies with credential status on mount."
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Companies",
       can_manage_company: Authorization.can?(socket.assigns[:current_role], :manage_company)
     )
     |> load_companies()}
  end

  @spec load_companies(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_companies(socket) do
    user = socket.assigns.current_user

    assign(
      socket,
      :companies_with_creds,
      Companies.list_companies_for_user_with_credential_status(user.id)
    )
  end

  @doc "Renders the company list page."
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.header>
      Companies
      <:subtitle>Manage your companies</:subtitle>
      <:actions>
        <.button navigate={~p"/companies/new"}>
          New Company
        </.button>
      </:actions>
    </.header>

    <.table_container class="mt-6">
      <.table
        id="companies"
        rows={@companies_with_creds}
        row_id={fn c -> "company-#{c.id}" end}
        row_click={
          @can_manage_company &&
            fn company -> JS.navigate(~p"/companies/#{company.id}/edit") end
        }
      >
        <:col :let={company} label="Name">
          <span class="text-sm" data-testid="company-name">{company.name}</span>
          <div class="font-mono text-[11px] text-muted-foreground">{company.nip}</div>
        </:col>
        <:col :let={company} label="KSeF Sync">
          <.badge :if={company.has_active_credential} variant="success">configured</.badge>
          <.badge :if={!company.has_active_credential} variant="muted">not configured</.badge>
        </:col>
        <:col :let={company} label="Status">
          <.badge :if={company.is_active} variant="success">active</.badge>
          <.badge :if={!company.is_active} variant="muted">inactive</.badge>
        </:col>
        <:action>
          <.icon
            :if={@can_manage_company}
            name="hero-chevron-right"
            class="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity"
          />
        </:action>
      </.table>
    </.table_container>

    <.empty_state :if={@companies_with_creds == []}>
      No companies yet. Create one to get started.
    </.empty_state>
    """
  end
end
