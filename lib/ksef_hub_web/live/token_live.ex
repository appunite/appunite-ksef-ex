defmodule KsefHubWeb.TokenLive do
  @moduledoc """
  LiveView for listing and revoking API tokens.

  Token creation is handled by `KsefHubWeb.TokenLive.Form`.
  Tokens are scoped to the current company. Any role with `:manage_tokens` permission can access.
  """
  use KsefHubWeb, :live_view

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

  @spec time_ago(DateTime.t() | nil) :: String.t()
  defp time_ago(nil), do: "never"

  defp time_ago(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86_400 -> "#{div(diff, 3600)} hr ago"
      diff < 86_400 * 2 -> "yesterday"
      diff < 86_400 * 30 -> "#{div(diff, 86_400)} days ago"
      diff < 86_400 * 365 -> "#{div(diff, 86_400 * 30)} mo ago"
      true -> "#{div(diff, 86_400 * 365)} yr ago"
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
      <.table_container class="mt-6">
        <.table
          id="tokens"
          rows={@streams.tokens}
          row_id={fn {id, _} -> id end}
          row_item={fn {_id, item} -> item end}
        >
          <:col :let={token} label="Name">
            <span class="text-sm" data-testid={"token-name-#{token.id}"}>{token.name}</span>
          </:col>
          <:col :let={token} label="Token">
            <code class="font-mono text-sm">{token.token_prefix}…</code>
          </:col>
          <:col :let={token} label="Created">
            <span class="font-mono text-xs text-muted-foreground">
              {Calendar.strftime(token.inserted_at, "%Y-%m-%d")}
            </span>
          </:col>
          <:col :let={token} label="Last Used">
            <span class="font-mono text-xs text-muted-foreground">
              {time_ago(token.last_used_at)}
            </span>
          </:col>
          <:action :let={token}>
            <.button
              :if={token.is_active}
              variant="ghost"
              size="sm"
              class="text-shad-destructive hover:text-shad-destructive"
              phx-click="revoke"
              phx-value-id={token.id}
              data-confirm="Are you sure? This will immediately revoke API access for this token."
            >
              Revoke
            </.button>
            <.badge :if={!token.is_active} variant="muted">revoked</.badge>
          </:action>
        </.table>
      </.table_container>

      <.empty_state :if={@tokens_count == 0}>
        No API tokens yet. Create one to get started.
      </.empty_state>
    </.settings_layout>
    """
  end
end
