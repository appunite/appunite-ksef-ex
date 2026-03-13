defmodule KsefHubWeb.UserLoginLive do
  @moduledoc """
  LiveView for user login with email and password.

  Renders a form with `phx-update="ignore"` and a plain HTML `action`,
  so the browser POSTs directly to `UserSessionController.create/2`.
  """

  use KsefHubWeb, :live_view

  alias KsefHubWeb.UrlHelpers

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    return_to = UrlHelpers.sanitize_return_to(params["return_to"])
    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, return_to: return_to),
     temporary_assigns: [form: nil]}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.auth_card title="Log in">
      <.simple_form
        for={@form}
        id="login_form"
        action={~p"/users/log-in"}
        phx-update="ignore"
      >
        <input :if={@return_to} type="hidden" name="user[return_to]" value={@return_to} />
        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.link
            href={~p"/users/reset-password"}
            class="text-sm text-shad-primary underline-offset-4 hover:underline"
          >
            Forgot your password?
          </.link>
        </:actions>

        <:actions>
          <.button
            phx-disable-with="Logging in..."
            class="inline-flex items-center justify-center gap-2 w-full h-9 px-4 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 transition-colors cursor-pointer"
          >
            Log in
          </.button>
        </:actions>
      </.simple_form>

      <div class="border-t border-border my-4"></div>

      <a
        href={~p"/auth/google"}
        class="inline-flex items-center justify-center gap-2 w-full h-9 px-4 text-sm font-medium rounded-md border border-input bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
      >
        Sign in with Google
      </a>

      <:footer>
        <p class="text-center text-sm mt-4">
          Don't have an account?
          <.link
            navigate={~p"/users/register"}
            class="text-shad-primary underline-offset-4 hover:underline font-semibold"
          >
            Sign up
          </.link>
        </p>
      </:footer>
    </.auth_card>
    """
  end
end
