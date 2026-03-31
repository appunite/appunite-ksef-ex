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

    <div class="rounded-lg border border-border overflow-hidden mt-6">
      <div class="overflow-x-auto">
        <.table
          id="companies"
          rows={@companies_with_creds}
          row_id={fn c -> "company-#{c.id}" end}
        >
          <:col :let={company} label="Name">
            <span data-testid="company-name">{company.name}</span>
          </:col>
          <:col :let={company} label="NIP">
            <span class="font-mono">{company.nip}</span>
          </:col>
          <:col :let={company} label="KSeF Sync">
            <.badge :if={company.has_active_credential} variant="success">Configured</.badge>
            <.badge :if={!company.has_active_credential} variant="muted">Not configured</.badge>
          </:col>
          <:col :let={company} label="Status">
            <.badge :if={company.is_active} variant="success">Active</.badge>
            <.badge :if={!company.is_active} variant="muted">Inactive</.badge>
          </:col>
          <:action :let={company}>
            <.button
              :if={@can_manage_company}
              variant="outline"
              size="sm"
              navigate={~p"/companies/#{company.id}/edit"}
            >
              Edit
            </.button>
          </:action>
        </.table>
      </div>
    </div>

    <p :if={@companies_with_creds == []} class="text-center text-muted-foreground py-8">
      No companies yet. Create one to get started.
    </p>
    """
  end
end
