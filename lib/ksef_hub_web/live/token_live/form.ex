defmodule KsefHubWeb.TokenLive.Form do
  @moduledoc """
  LiveView for creating a new API token.

  After creation, displays the plaintext token for the user to copy.
  Navigates back to the token list on dismiss.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Accounts

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "New API Token",
       form: to_form(%{"name" => "", "description" => ""}, as: :token),
       show_token: nil
     )}
  end

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
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
      {:ok, %{token: plain_token}} ->
        {:noreply, assign(socket, show_token: plain_token)}

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
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        New API Token
        <:subtitle>Create a new bearer token for API access</:subtitle>
      </.header>

      <div :if={@show_token} class="mt-6">
        <div
          class="border border-warning/20 bg-warning/5 rounded-lg p-4 flex gap-3 items-start"
          role="alert"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 text-warning/70 shrink-0 mt-0.5" />
          <div class="flex-1">
            <p class="font-semibold text-sm">Copy your API token now. It won't be shown again.</p>
            <code class="block mt-2 p-2 bg-card rounded text-sm font-mono break-all select-all text-card-foreground">
              {@show_token}
            </code>
          </div>
        </div>

        <div class="flex items-center gap-3 mt-4">
          <.button navigate={~p"/c/#{@current_company.id}/settings/tokens"}>
            Done
          </.button>
        </div>
      </div>

      <.form
        :if={!@show_token}
        for={@form}
        phx-submit="create"
        phx-change="validate"
        class="mt-6 space-y-6 max-w-xl"
        id="create-token-form"
      >
        <.input field={@form[:name]} label="Name" placeholder="e.g. CI/CD Pipeline" required />
        <.input
          field={@form[:description]}
          type="textarea"
          label="Description"
          placeholder="What is this token used for?"
        />

        <div class="flex items-center gap-3 pt-2">
          <.button type="submit">Create Token</.button>
          <.button variant="outline" navigate={~p"/c/#{@current_company.id}/settings/tokens"}>
            Cancel
          </.button>
        </div>
      </.form>
    </.settings_layout>
    """
  end
end
