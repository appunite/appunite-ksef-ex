defmodule KsefHubWeb.TeamLive do
  @moduledoc """
  LiveView for team management — owner-only page to view members,
  send invitations, cancel pending invitations, and remove members.
  """

  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Authorization
  alias KsefHub.Companies
  alias KsefHub.Companies.Company
  alias KsefHub.Invitations
  alias KsefHub.Invitations.InvitationNotifier

  @doc "Mounts the team page. Permission check is enforced by the :require_permission on_mount hook."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Team")
     |> assign(invite_form: to_form(%{"email" => "", "role" => "accountant"}, as: :invitation))
     |> stream(:members, [])
     |> stream(:pending_invitations, [])
     |> load_team_data()}
  end

  @doc "Handles invite, cancel, remove, and validate events."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  @impl true
  def handle_event("validate_invite", %{"invitation" => params}, socket) do
    {:noreply, assign(socket, invite_form: to_form(params, as: :invitation))}
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
         |> assign(
           invite_form: to_form(%{"email" => "", "role" => "accountant"}, as: :invitation)
         )
         |> load_team_data()}

      {:error, :already_member} ->
        {:noreply, put_flash(socket, :error, "This person is already a member of the company.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only the owner can send invitations.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        message = format_changeset_errors(changeset)
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("cancel_invitation", %{"id" => invitation_id}, socket) do
    user = socket.assigns.current_user

    case Invitations.cancel_invitation(user.id, invitation_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Invitation cancelled.")
         |> load_team_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel invitation.")}
    end
  end

  @impl true
  def handle_event("change_role", %{"user-id" => member_user_id, "role" => role}, socket) do
    current_role = socket.assigns.current_role
    company = socket.assigns.current_company
    allowed_roles = assignable_roles(current_role)

    with true <- Authorization.can?(current_role, :manage_team),
         role_atom when role_atom in allowed_roles <- String.to_existing_atom(role),
         %{role: existing_role} = membership
         when existing_role != :owner <-
           Companies.get_membership(member_user_id, company.id),
         {:ok, _} <- Companies.update_membership_role(membership, role_atom) do
      {:noreply,
       socket
       |> put_flash(:info, "Role updated.")
       |> load_team_data()}
    else
      false -> {:noreply, put_flash(socket, :error, "You don't have permission to change roles.")}
      nil -> {:noreply, put_flash(socket, :error, "Member not found.")}
      %{role: :owner} -> {:noreply, put_flash(socket, :error, "Cannot change owner's role.")}
      _ -> {:noreply, put_flash(socket, :error, "Invalid role.")}
    end
  end

  @impl true
  def handle_event("remove_member", %{"user-id" => member_user_id}, socket) do
    company = socket.assigns.current_company

    case Companies.get_membership(member_user_id, company.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Member not found.")}

      %{role: :owner} ->
        {:noreply, put_flash(socket, :error, "Cannot remove company owner.")}

      membership ->
        case Companies.delete_membership(membership) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Member removed.")
             |> load_team_data()}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to remove member.")}
        end
    end
  end

  # --- Private helpers ---

  @spec load_team_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_team_data(socket) do
    company = socket.assigns.current_company
    members = Companies.list_members(company.id)
    pending_invitations = Invitations.list_pending_invitations(company.id)

    socket
    |> stream(:members, members, reset: true)
    |> stream(:pending_invitations, pending_invitations, reset: true)
  end

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
          "Failed to deliver invitation email to #{invitation.email}: #{inspect(reason)}"
        )

        :email_failed
    end
  end

  @spec assignable_roles(atom()) :: [atom()]
  defp assignable_roles(:owner), do: [:admin, :accountant, :reviewer]
  defp assignable_roles(:admin), do: [:admin, :accountant, :reviewer]
  defp assignable_roles(_), do: []

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  @doc "Renders the team management page."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      Team
      <:subtitle>Manage members and invitations for {@current_company.name}</:subtitle>
    </.header>

    <!-- Invite Form -->
    <.card class="mt-6">
      <h2 class="text-base font-semibold mb-3">Invite a new member</h2>
      <.form
        for={@invite_form}
        phx-submit="invite"
        phx-change="validate_invite"
        data-testid="invite-form"
        class="flex gap-3 items-end"
      >
        <div class="flex-1">
          <.input
            field={@invite_form[:email]}
            type="email"
            label="Email"
            placeholder="user@example.com"
            required
          />
        </div>
        <div class="w-48">
          <.input
            field={@invite_form[:role]}
            type="select"
            label="Role"
            options={[{"Admin", "admin"}, {"Accountant", "accountant"}, {"Reviewer", "reviewer"}]}
          />
        </div>
        <div class="fieldset mb-2">
          <span class="mb-1 invisible">_</span>
          <.button type="submit">
            <.icon name="hero-paper-airplane" class="size-4" /> Invite
          </.button>
        </div>
      </.form>
    </.card>

    <!-- Team members & pending invitations -->
    <.card class="mt-6">
      <h2 class="text-base font-semibold mb-3">Members</h2>
      <div class="rounded-lg border border-border overflow-hidden">
        <div class="overflow-x-auto" data-testid="member-list">
          <table class="w-full text-sm" data-testid="team-table">
            <thead>
              <tr class="border-b border-border">
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Email
                </th>
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Name
                </th>
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Role
                </th>
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Status
                </th>
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Expires
                </th>
                <th class="text-left py-3 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Action
                </th>
              </tr>
            </thead>
            <tbody id="members-list" phx-update="stream">
              <tr
                :for={{dom_id, member} <- @streams.members}
                id={dom_id}
                class="border-b border-border/50 hover:bg-muted/50 transition-colors"
              >
                <td class="py-3.5 px-4">{member.user.email}</td>
                <td class="py-3.5 px-4">{member.user.name || "-"}</td>
                <td class="py-3.5 px-4">
                  <.badge :if={member.role == :owner} variant="default">{member.role}</.badge>
                  <form
                    :if={member.role != :owner && assignable_roles(@current_role) != []}
                    phx-change="change_role"
                    phx-value-user-id={member.user.id}
                    data-testid={"role-form-#{member.user.id}"}
                  >
                    <select
                      name="role"
                      class="select select-sm select-bordered"
                      data-testid={"role-select-#{member.user.id}"}
                    >
                      <option
                        :for={role <- assignable_roles(@current_role)}
                        value={role}
                        selected={role == member.role}
                      >
                        {role |> Atom.to_string() |> String.capitalize()}
                      </option>
                    </select>
                  </form>
                  <.badge
                    :if={member.role != :owner && assignable_roles(@current_role) == []}
                    variant="default"
                  >
                    {member.role}
                  </.badge>
                </td>
                <td class="py-3.5 px-4"></td>
                <td class="py-3.5 px-4">-</td>
                <td class="py-3.5 px-4">
                  <.button
                    :if={member.role != :owner}
                    variant="outline"
                    size="sm"
                    class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
                    phx-click="remove_member"
                    phx-value-user-id={member.user.id}
                    data-confirm="Remove this member from the company?"
                    data-testid={"remove-member-#{member.user.id}"}
                  >
                    Remove
                  </.button>
                </td>
              </tr>
            </tbody>
            <tbody id="pending-invitations-list" phx-update="stream">
              <tr
                :for={{dom_id, inv} <- @streams.pending_invitations}
                id={dom_id}
                class="border-b border-border/50 hover:bg-muted/50 transition-colors"
              >
                <td class="py-3.5 px-4">{inv.email}</td>
                <td class="py-3.5 px-4">-</td>
                <td class="py-3.5 px-4">
                  <.badge variant="default" data-role={inv.role}>{inv.role}</.badge>
                </td>
                <td class="py-3.5 px-4">
                  <.badge variant="warning">pending</.badge>
                </td>
                <td class="py-3.5 px-4">{Calendar.strftime(inv.expires_at, "%Y-%m-%d")}</td>
                <td class="py-3.5 px-4">
                  <.button
                    variant="outline"
                    size="sm"
                    class="border-shad-destructive text-shad-destructive hover:bg-shad-destructive/10"
                    phx-click="cancel_invitation"
                    phx-value-id={inv.id}
                    data-confirm="Cancel this invitation?"
                    data-testid={"cancel-invitation-#{inv.id}"}
                  >
                    Cancel
                  </.button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </.card>
    """
  end
end
