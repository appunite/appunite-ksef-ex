defmodule KsefHubWeb.TokenLive do
  @moduledoc """
  LiveView for listing and revoking API tokens.

  Token creation is handled by `KsefHubWeb.TokenLive.Form`.
  Tokens are scoped to the current company. Any role with `:manage_tokens` permission can access.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.InvoiceComponents, only: [format_datetime: 1]
  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Accounts

  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    tokens = Accounts.list_api_tokens(socket.assigns.current_user.id, company_id)

    {:ok,
     socket
     |> assign(page_title: "API Tokens", tokens_count: length(tokens))
     |> stream(:tokens, tokens)}
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    user_id = socket.assigns.current_user.id
    company_id = socket.assigns.current_company.id

    case Accounts.revoke_api_token(user_id, company_id, id) do
      {:ok, revoked_token} ->
        {:noreply,
         socket
         |> stream_insert(:tokens, revoked_token)
         |> put_flash(:info, "Token revoked.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Token not found.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke token.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        API Tokens
        <:subtitle>Manage bearer tokens for API access</:subtitle>
        <:actions>
          <.button navigate={~p"/c/#{@current_company.id}/settings/tokens/new"}>
            New Token
          </.button>
        </:actions>
      </.header>
      <div class="rounded-lg border border-border overflow-hidden mt-6">
        <div class="overflow-x-auto">
          <.table
            id="tokens"
            rows={@streams.tokens}
            row_id={fn {id, _} -> id end}
            row_item={fn {_id, item} -> item end}
          >
            <:col :let={token} label="Name">
              <span data-testid={"token-name-#{token.id}"}>{token.name}</span>
            </:col>
            <:col :let={token} label="Prefix">
              <code class="font-mono text-sm">{token.token_prefix}****</code>
            </:col>
            <:col :let={token} label="Last Used">
              {format_datetime(token.last_used_at)}
            </:col>
            <:col :let={token} label="Requests">
              <span class="font-mono">{token.request_count}</span>
            </:col>
            <:col :let={token} label="Status">
              <.badge :if={token.is_active} variant="success">Active</.badge>
              <.badge :if={!token.is_active} variant="muted">Revoked</.badge>
            </:col>
            <:action :let={token}>
              <.button
                :if={token.is_active}
                variant="outline"
                size="sm"
                class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
                phx-click="revoke"
                phx-value-id={token.id}
                data-confirm="Are you sure? This will immediately revoke API access for this token."
              >
                Revoke
              </.button>
            </:action>
          </.table>
        </div>
      </div>

      <p :if={@tokens_count == 0} class="text-center text-muted-foreground py-8">
        No API tokens yet. Create one to get started.
      </p>
    </.settings_layout>
    """
  end
end
