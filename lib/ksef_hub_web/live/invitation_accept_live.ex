defmodule KsefHubWeb.InvitationAcceptLive do
  @moduledoc """
  LiveView for accepting company invitations via tokenized link.

  If the user is logged in, accepts the invitation immediately and redirects
  to the dashboard. If not logged in, shows an error or message prompting
  them to log in or sign up.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Invitations

  @doc "Validates the invitation token and attempts acceptance if user is authenticated."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(%{"token" => token}, _session, socket) do
    user = socket.assigns[:current_user]

    if user do
      handle_accept(socket, token, user)
    else
      return_to = "/invitations/accept/#{token}"

      {:ok,
       socket
       |> put_flash(:info, "Please log in or sign up to accept this invitation.")
       |> redirect(to: "/users/log-in?return_to=#{URI.encode(return_to)}")}
    end
  end

  @spec handle_accept(Phoenix.LiveView.Socket.t(), String.t(), KsefHub.Accounts.User.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  defp handle_accept(socket, token, user) do
    case Invitations.accept_invitation(token, user) do
      {:ok, _result} ->
        {:ok,
         socket
         |> put_flash(:info, "Invitation accepted! You've joined the company.")
         |> redirect(to: "/invoices")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(page_title: "Invalid Invitation")
         |> assign(error: :invalid, accepted: false)}

      {:error, :expired} ->
        {:ok,
         socket
         |> assign(page_title: "Invitation Expired")
         |> assign(error: :expired, accepted: false)}

      {:error, :already_member} ->
        {:ok,
         socket
         |> put_flash(:info, "You're already a member of this company.")
         |> redirect(to: "/invoices")}

      {:error, %Ecto.Changeset{}} ->
        {:ok,
         socket
         |> put_flash(:error, "Something went wrong while accepting the invitation.")
         |> redirect(to: "/invoices")}
    end
  end

  @doc "Renders the invitation acceptance page."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md mt-12">
      <div
        :if={@error == :expired}
        class="rounded-xl border border-warning bg-card text-card-foreground"
      >
        <div class="p-8 text-center">
          <.icon name="hero-clock" class="size-12 text-warning mx-auto" />
          <h2 class="text-lg font-semibold mt-3">Invitation expired</h2>
          <p class="text-sm text-muted-foreground mt-2">
            This invitation has expired. Please ask the company owner to send a new one.
          </p>
          <.link
            navigate="/invoices"
            class="inline-flex items-center justify-center gap-2 h-9 px-4 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer mt-4"
          >
            Continue
          </.link>
        </div>
      </div>

      <div
        :if={@error == :invalid}
        class="rounded-xl border border-shad-destructive bg-card text-card-foreground"
      >
        <div class="p-8 text-center">
          <.icon name="hero-exclamation-triangle" class="size-12 text-shad-destructive mx-auto" />
          <h2 class="text-lg font-semibold mt-3">Invalid invitation</h2>
          <p class="text-sm text-muted-foreground mt-2">
            This invitation link is invalid or has already been used.
          </p>
          <.link
            navigate="/invoices"
            class="inline-flex items-center justify-center gap-2 h-9 px-4 text-sm font-medium rounded-md bg-shad-primary text-shad-primary-foreground hover:bg-shad-primary/90 shadow-xs transition-colors cursor-pointer mt-4"
          >
            Continue
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
