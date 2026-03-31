defmodule KsefHubWeb.TeamLive.Invite do
  @moduledoc """
  LiveView for inviting a new team member.

  Navigates back to the team list on success.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  require Logger

  alias KsefHub.Companies.Company
  alias KsefHub.Invitations
  alias KsefHub.Invitations.InvitationNotifier

  @doc "Initializes the invite form with default email and role fields."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Invite Member",
       form: to_form(%{"email" => "", "role" => "accountant"}, as: :invitation)
     )}
  end

  @doc "Handles `\"validate\"` (live form validation) and `\"invite\"` (submission) events."
  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("validate", %{"invitation" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :invitation))}
  end

  @impl true
  def handle_event("invite", %{"invitation" => params}, socket) do
    user = socket.assigns.current_user
    company = socket.assigns.current_company

    attrs = %{
      email: params["email"],
      role: params["role"]
    }

    case Invitations.create_invitation(user.id, company.id, attrs) do
      {:ok, %{invitation: invitation, token: token}} ->
        flash =
          case send_invitation_email(invitation, token, company) do
            :ok -> {:info, "Invitation sent to #{invitation.email}."}
            :email_failed -> {:error, "Invitation created but email delivery failed."}
          end

        {:noreply,
         socket
         |> put_flash(elem(flash, 0), elem(flash, 1))
         |> push_navigate(to: ~p"/c/#{company.id}/settings/team")}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, "This person is already a member of the company.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are not authorized to send invitations.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        message = format_changeset_errors(changeset)
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # --- Private helpers ---

  @spec send_invitation_email(Invitations.Invitation.t(), String.t(), Company.t()) ::
          :ok | :email_failed
  defp send_invitation_email(invitation, token, company) do
    url = url(~p"/invitations/accept/#{token}")

    case InvitationNotifier.deliver_invitation(
           invitation.email,
           url,
           %{company_name: company.name, role: invitation.role}
         ) do
      {:ok, _email} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to deliver invitation email for invitation_id=#{invitation.id}: #{sanitize_email_error(reason)}"
        )

        :email_failed
    end
  end

  @spec sanitize_email_error(term()) :: atom()
  defp sanitize_email_error(%{__exception__: true}), do: :provider_error
  defp sanitize_email_error(:timeout), do: :network_error
  defp sanitize_email_error({:network_error, _}), do: :network_error
  defp sanitize_email_error(_), do: :delivery_failed

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  @doc "Renders the invitation form with email, role select, and submit/cancel buttons."
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
        Invite Member
        <:subtitle>Send an invitation to join {@current_company.name}</:subtitle>
      </.header>

      <.form
        for={@form}
        phx-submit="invite"
        phx-change="validate"
        class="mt-6 space-y-6 max-w-xl"
        id="invite-form"
        data-testid="invite-form"
      >
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          placeholder="user@example.com"
          required
        />

        <.input
          field={@form[:role]}
          type="select"
          label="Role"
          options={role_options()}
        />

        <div class="flex items-center gap-3 pt-2">
          <.button type="submit">
            <.icon name="hero-paper-airplane" class="size-4" /> Send Invitation
          </.button>
          <.button variant="outline" navigate={~p"/c/#{@current_company.id}/settings/team"}>
            Cancel
          </.button>
        </div>
      </.form>
    </.settings_layout>
    """
  end

  @spec role_options() :: [{String.t(), String.t()}]
  defp role_options do
    [{"Admin", "admin"}, {"Accountant", "accountant"}, {"Reviewer", "reviewer"}]
  end
end
