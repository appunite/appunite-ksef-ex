defmodule KsefHubWeb.UserLoginLive do
  @moduledoc """
  LiveView for user login with email and password.

  Uses the `phx-trigger-action` pattern: validates the form in LiveView,
  then triggers a real HTTP POST to `UserSessionController.create/2`.
  """

  use KsefHubWeb, :live_view

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    return_to = sanitize_return_to(params["return_to"])
    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, return_to: return_to),
     temporary_assigns: [form: nil]}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"user" => user_params}, socket) do
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    # The form will POST to the session controller via phx-trigger-action
    form = to_form(user_params, as: "user")
    {:noreply, assign(socket, form: form, trigger_submit: true)}
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @spec sanitize_return_to(String.t() | nil) :: String.t() | nil
  defp sanitize_return_to(nil), do: nil
  defp sanitize_return_to(""), do: nil

  defp sanitize_return_to(path) when is_binary(path) do
    uri = URI.parse(path)

    if is_nil(uri.host) && String.starts_with?(path, "/") do
      path
    else
      nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="card bg-base-100 border border-base-300 w-full max-w-md">
        <div class="card-body">
          <h2 data-testid="page-title" class="card-title text-2xl justify-center mb-4">Log in</h2>

          <.simple_form
            for={@form}
            id="login_form"
            action={~p"/users/log-in"}
            phx-update="ignore"
            phx-submit="save"
            phx-trigger-action={@trigger_submit}
          >
            <input :if={@return_to} type="hidden" name="user[return_to]" value={@return_to} />
            <.input field={@form[:email]} type="email" label="Email" required />
            <.input field={@form[:password]} type="password" label="Password" required />

            <:actions>
              <.link href={~p"/users/reset-password"} class="text-sm link link-primary">
                Forgot your password?
              </.link>
            </:actions>

            <:actions>
              <.button phx-disable-with="Logging in..." class="btn btn-primary w-full">
                Log in
              </.button>
            </:actions>
          </.simple_form>

          <div class="divider">OR</div>

          <a href={~p"/auth/google"} class="btn btn-outline w-full gap-2">
            Sign in with Google
          </a>

          <p class="text-center text-sm mt-4">
            Don't have an account?
            <.link navigate={~p"/users/register"} class="link link-primary font-semibold">
              Sign up
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
