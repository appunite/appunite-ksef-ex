defmodule KsefHubWeb.TeamLive do
  @moduledoc """
  LiveView for team management — page for owners and admins to view members,
  send invitations, cancel pending invitations, change roles, and remove members.
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

  @doc "Handles invite, cancel, remove, change_role, and validate events."
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

    with {:ok, role_atom} <- parse_role(role),
         :ok <- check_permission(current_role),
         :ok <- check_role_allowed(role_atom, allowed_roles),
         :ok <- check_not_self(member_user_id, socket.assigns.current_user.id),
         {:ok, membership} <- fetch_non_owner_membership(member_user_id, company.id),
         {:ok, _} <- Companies.update_membership_role(membership, role_atom) do
      {:noreply,
       socket
       |> put_flash(:info, "Role updated.")
       |> load_team_data()}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, put_flash(socket, :error, "Failed to update role.")}
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
    |> assign(assignable_roles: assignable_roles(socket.assigns.current_role))
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

  @valid_roles ~w(owner admin accountant reviewer)a

  @spec parse_role(String.t()) :: {:ok, atom()} | {:error, String.t()}
  defp parse_role(role) when is_binary(role) do
    role_atom = String.to_existing_atom(role)

    if role_atom in @valid_roles do
      {:ok, role_atom}
    else
      {:error, "Invalid role."}
    end
  rescue
    ArgumentError -> {:error, "Invalid role."}
  end

  @spec check_not_self(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, String.t()}
  defp check_not_self(target_id, current_id) when target_id == current_id,
    do: {:error, "You cannot change your own role."}

  defp check_not_self(_, _), do: :ok

  @spec check_permission(atom()) :: :ok | {:error, String.t()}
  defp check_permission(role) do
    if Authorization.can?(role, :manage_team),
      do: :ok,
      else: {:error, "You don't have permission to change roles."}
  end

  @spec check_role_allowed(atom(), [atom()]) :: :ok | {:error, String.t()}
  defp check_role_allowed(role, allowed) do
    if role in allowed, do: :ok, else: {:error, "Invalid role."}
  end

  @spec fetch_non_owner_membership(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Companies.Membership.t()} | {:error, String.t()}
  defp fetch_non_owner_membership(user_id, company_id) do
    case Companies.get_membership(user_id, company_id) do
      nil -> {:error, "Member not found."}
      %{role: :owner} -> {:error, "Cannot change owner's role."}
      membership -> {:ok, membership}
    end
  end

  @spec assignable_roles(atom()) :: [atom()]
  defp assignable_roles(:owner), do: [:admin, :accountant, :reviewer]
  defp assignable_roles(:admin), do: [:admin, :accountant, :reviewer]
  defp assignable_roles(_), do: []

  @spec role_label(atom()) :: String.t()
  defp role_label(role), do: role |> Atom.to_string() |> String.capitalize()

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
                  <select
                    :if={member.role == :owner}
                    disabled
                    class="text-sm py-1 px-2 rounded-md border border-border bg-background opacity-60"
                  >
                    <option>{role_label(member.role)}</option>
                  </select>
                  <form
                    :if={member.role != :owner && @assignable_roles != []}
                    phx-change="change_role"
                    phx-value-user-id={member.user.id}
                    data-testid={"role-form-#{member.user.id}"}
                  >
                    <select
                      name="role"
                      class="text-sm py-1 px-2 rounded-md border border-border bg-background"
                      data-testid={"role-select-#{member.user.id}"}
                    >
                      <option
                        :for={role <- @assignable_roles}
                        value={role}
                        selected={role == member.role}
                      >
                        {role_label(role)}
                      </option>
                    </select>
                  </form>
                  <select
                    :if={member.role != :owner && @assignable_roles == []}
                    disabled
                    class="text-sm py-1 px-2 rounded-md border border-border bg-background opacity-60"
                  >
                    <option>{role_label(member.role)}</option>
                  </select>
                </td>
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
                <td class="py-3.5 px-4">
                  <div>{inv.email}</div>
                  <div class="text-xs text-muted-foreground mt-0.5">
                    Pending — expires {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
                  </div>
                </td>
                <td class="py-3.5 px-4">-</td>
                <td class="py-3.5 px-4">
                  <select
                    disabled
                    data-role={inv.role}
                    class="text-sm py-1 px-2 rounded-md border border-border bg-background opacity-60"
                  >
                    <option>{role_label(inv.role)}</option>
                  </select>
                </td>
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
