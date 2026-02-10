defmodule KsefHubWeb.UserConfirmationLive do
  @moduledoc """
  LiveView for confirming a user account via email token.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Accounts

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, token: token, confirmed: false)
    {:ok, socket, temporary_assigns: [token: nil]}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("confirm_account", %{"token" => token}, socket) do
    case Accounts.confirm_user(token) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(confirmed: true)
         |> put_flash(:info, "Account confirmed successfully.")}

      :error ->
        {:noreply, put_flash(socket, :error, "Confirmation link is invalid or it has expired.")}
    end
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="card bg-base-100 border border-base-300 w-full max-w-md">
        <div class="card-body text-center">
          <h2 data-testid="page-title" class="card-title text-2xl justify-center mb-4">
            Confirm Account
          </h2>

          <div :if={!@confirmed}>
            <p class="mb-4">Click the button below to confirm your account.</p>
            <.simple_form for={%{}} id="confirmation_form" phx-submit="confirm_account">
              <input type="hidden" name="token" value={@token} />
              <:actions>
                <.button class="btn btn-primary w-full">Confirm my account</.button>
              </:actions>
            </.simple_form>
          </div>

          <div :if={@confirmed} data-testid="confirmation-success">
            <p class="text-success mb-4">Your account has been confirmed!</p>
            <.link navigate={~p"/users/log-in"} class="btn btn-primary w-full">
              Log in
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
