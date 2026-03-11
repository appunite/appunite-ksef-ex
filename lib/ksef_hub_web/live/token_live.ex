defmodule KsefHubWeb.TokenLive do
  @moduledoc """
  LiveView for managing API tokens — create, view, and revoke bearer tokens.

  Tokens are scoped to the current company. Owners, admins, and accountants can access.
  """
  use KsefHubWeb, :live_view

  alias KsefHub.Accounts

  @impl true
  def mount(_params, _session, socket) do
    company_id = socket.assigns.current_company.id
    tokens = Accounts.list_api_tokens(socket.assigns.current_user.id, company_id)

    {:ok,
     socket
     |> assign(
       page_title: "API Tokens",
       tokens_count: length(tokens),
       form: to_form(%{"name" => "", "description" => ""}, as: :token),
       show_token: nil,
       show_create_form: false
     )
     |> stream(:tokens, tokens)}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_create_form: !socket.assigns.show_create_form)}
  end

  @impl true
  def handle_event("validate", %{"token" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :token))}
  end

  @impl true
  def handle_event("create", %{"token" => params}, socket) do
    user_id = socket.assigns.current_user.id
    company_id = socket.assigns.current_company.id

    attrs = %{
      name: params["name"],
      description: params["description"]
    }

    case Accounts.create_api_token(user_id, company_id, attrs) do
      {:ok, %{token: plain_token, api_token: api_token}} ->
        {:noreply,
         socket
         |> assign(
           tokens_count: socket.assigns.tokens_count + 1,
           show_token: plain_token,
           show_create_form: false,
           form: to_form(%{"name" => "", "description" => ""}, as: :token)
         )
         |> stream_insert(:tokens, api_token, at: 0)
         |> put_flash(:info, "Token created. Copy it now — it won't be shown again.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to create tokens.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(form: to_form(changeset, as: :token))
         |> put_flash(:error, "Failed to create token.")}
    end
  end

  @impl true
  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, show_token: nil)}
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
    <.header>
      API Tokens
      <:subtitle>Manage bearer tokens for API access</:subtitle>
      <:actions>
        <button
          phx-click="toggle_form"
          class="inline-flex items-center justify-center gap-2 h-8 px-3 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer"
        >
          <.icon name="hero-plus" class="size-4" /> New Token
        </button>
      </:actions>
    </.header>

    <!-- Plaintext Token Alert -->
    <div
      :if={@show_token}
      class="border border-warning/20 bg-warning/5 rounded-lg p-4 mt-4 flex gap-3 items-start"
      role="alert"
    >
      <.icon name="hero-exclamation-triangle" class="size-5 text-warning/70 shrink-0 mt-0.5" />
      <div class="flex-1">
        <p class="font-semibold text-sm">Copy your API token now. It won't be shown again.</p>
        <code class="block mt-2 p-2 bg-card rounded text-sm font-mono break-all select-all text-card-foreground">
          {@show_token}
        </code>
      </div>
      <button
        phx-click="dismiss_token"
        class="inline-flex items-center justify-center gap-2 h-8 px-3 text-sm font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
      >
        Dismiss
      </button>
    </div>

    <!-- Create Form -->
    <div
      :if={@show_create_form}
      class="rounded-xl border border-border bg-card text-card-foreground mt-6"
    >
      <div class="p-6">
        <h2 class="text-base font-semibold">Create New Token</h2>
        <.form
          for={@form}
          phx-submit="create"
          phx-change="validate"
          class="space-y-4 mt-2"
          id="create-token-form"
        >
          <.input field={@form[:name]} label="Name" placeholder="e.g. CI/CD Pipeline" required />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            placeholder="What is this token used for?"
          />
          <div class="flex gap-2">
            <button
              type="submit"
              class="inline-flex items-center justify-center gap-2 h-8 px-3 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer"
            >
              Create Token
            </button>
            <button
              type="button"
              phx-click="toggle_form"
              class="inline-flex items-center justify-center gap-2 h-8 px-3 text-sm font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
            >
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>

    <!-- Token Table -->
    <div class="mt-6 overflow-x-auto">
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
          <span
            :if={token.is_active}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-success/10 text-success border-success/20"
          >
            Active
          </span>
          <span
            :if={!token.is_active}
            class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border bg-muted text-muted-foreground border-border"
          >
            Revoked
          </span>
        </:col>
        <:action :let={token}>
          <button
            :if={token.is_active}
            phx-click="revoke"
            phx-value-id={token.id}
            data-confirm="Are you sure? This will immediately revoke API access for this token."
            class="inline-flex items-center justify-center gap-1 h-7 px-2 text-xs font-medium rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer text-shad-destructive"
          >
            Revoke
          </button>
        </:action>
      </.table>
    </div>

    <p :if={@tokens_count == 0} class="text-center text-muted-foreground py-8">
      No API tokens yet. Create one to get started.
    </p>
    """
  end

  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: String.t()
  defp format_datetime(nil), do: "Never"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
