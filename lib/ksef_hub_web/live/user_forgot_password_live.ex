defmodule KsefHubWeb.UserForgotPasswordLive do
  @moduledoc """
  LiveView for requesting password reset instructions.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Accounts

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset-password/#{&1}")
      )
    end

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If your email is in our system, you will receive instructions to reset your password shortly."
     )
     |> redirect(to: ~p"/")}
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="card bg-base-100 border border-base-300 w-full max-w-md">
        <div class="card-body">
          <h2 class="card-title text-2xl justify-center mb-4">Forgot your password?</h2>
          <p class="text-sm text-base-content/70 mb-4 text-center">
            We'll send a password reset link to your inbox.
          </p>

          <.simple_form for={@form} id="reset_password_form" phx-submit="send_email">
            <.input field={@form[:email]} type="email" label="Email" required />
            <:actions>
              <.button phx-disable-with="Sending..." class="btn btn-primary w-full">
                Send password reset instructions
              </.button>
            </:actions>
          </.simple_form>

          <p class="text-center text-sm mt-4">
            <.link navigate={~p"/users/register"} class="link link-primary">Register</.link>
            |
            <.link navigate={~p"/users/log-in"} class="link link-primary">Log in</.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
