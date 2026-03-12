defmodule KsefHubWeb.UserRegistrationLive do
  @moduledoc """
  LiveView for user registration with email and password.
  """

  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Accounts
  alias KsefHub.Accounts.User
  alias KsefHub.Invitations

  @doc false
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    changeset = Accounts.change_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  @doc false
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, memberships} = Invitations.accept_pending_invitations_for_email(user)

        if memberships != [] do
          Logger.info("Auto-accepted #{length(memberships)} invitation(s) for user #{user.id}")
        end

        case Accounts.deliver_user_confirmation_instructions(
               user,
               &url(~p"/users/confirm/#{&1}")
             ) do
          {:ok, _} ->
            :ok

          {:error, _reason} ->
            Logger.error("Failed to deliver confirmation email")
        end

        changeset = Accounts.change_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  @spec assign_form(Phoenix.LiveView.Socket.t(), Ecto.Changeset.t()) ::
          Phoenix.LiveView.Socket.t()
  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  @doc false
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.auth_card title="Create an account">
      <.simple_form
        for={@form}
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log-in"}
        method="post"
      >
        <.error :if={@check_errors}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={@form[:email]} type="email" label="Email" required />
        <.input field={@form[:password]} type="password" label="Password" required />

        <:actions>
          <.button
            phx-disable-with="Creating account..."
            class="inline-flex items-center justify-center gap-2 w-full h-9 px-4 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 transition-colors cursor-pointer"
          >
            Create account
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
          Already registered?
          <.link
            navigate={~p"/users/log-in"}
            class="text-shad-primary underline-offset-4 hover:underline font-semibold"
          >
            Log in
          </.link>
        </p>
      </:footer>
    </.auth_card>
    """
  end
end
