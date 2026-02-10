defmodule KsefHubWeb.UserResetPasswordLive do
  @moduledoc """
  LiveView for resetting a user's password via email token.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Accounts

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @spec assign_user_and_token(Phoenix.LiveView.Socket.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  @spec assign_form(Phoenix.LiveView.Socket.t(), Ecto.Changeset.t() | map()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end

  defp assign_form(socket, _) do
    assign(socket, form: to_form(%{}, as: "user"))
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center">
      <div class="card bg-base-100 border border-base-300 w-full max-w-md">
        <div class="card-body">
          <h2 data-testid="page-title" class="card-title text-2xl justify-center mb-4">
            Reset Password
          </h2>

          <.simple_form
            for={@form}
            id="reset_password_form"
            phx-submit="reset_password"
            phx-change="validate"
          >
            <.error :if={@form[:password] && @form[:password].errors != []}>
              Oops, something went wrong! Please check the errors below.
            </.error>

            <.input field={@form[:password]} type="password" label="New password" required />

            <:actions>
              <.button phx-disable-with="Resetting..." class="btn btn-primary w-full">
                Reset password
              </.button>
            </:actions>
          </.simple_form>

          <p class="text-center text-sm mt-4">
            <.link navigate={~p"/users/register"} class="link link-primary">Register</.link>
            | <.link navigate={~p"/users/log-in"} class="link link-primary">Log in</.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
