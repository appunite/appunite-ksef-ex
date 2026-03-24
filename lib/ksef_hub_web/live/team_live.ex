defmodule KsefHubWeb.TeamLive do
  @moduledoc """
  LiveView for team management — page for owners and admins to view members,
  send invitations, and navigate to member/invitation detail pages.
  """

  use KsefHubWeb, :live_view

  require Logger

  alias KsefHub.Companies
  alias KsefHub.Companies.{Company, Membership}
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

  @doc "Handles invite and validate events."
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

  defdelegate role_label(role), to: Membership

  @spec format_changeset_errors(Ecto.Changeset.t()) :: String.t()
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  @spec member_path(Ecto.UUID.t(), Companies.Membership.t()) :: String.t()
  defp member_path(company_id, member) do
    ~p"/c/#{company_id}/team/members/#{member.id}"
  end

  @spec invitation_path(Ecto.UUID.t(), Invitations.Invitation.t()) :: String.t()
  defp invitation_path(company_id, invitation) do
    ~p"/c/#{company_id}/team/invitations/#{invitation.id}"
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
        <div class="mb-2">
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
          <table class="w-full table-fixed text-sm" data-testid="team-table">
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
              </tr>
            </thead>
            <tbody id="members-list" phx-update="stream">
              <tr
                :for={{dom_id, member} <- @streams.members}
                id={dom_id}
                class="border-b border-border/50 hover:bg-muted/50 transition-colors"
                data-testid={"member-row-#{member.user.id}"}
              >
                <td class="py-3.5 px-4">
                  <.link
                    navigate={member_path(@current_company.id, member)}
                    class="hover:underline underline-offset-4"
                    data-testid={"member-link-#{member.user.id}"}
                  >
                    {member.user.email}
                  </.link>
                  <.badge
                    :if={member.status == :blocked}
                    variant="error"
                    class="ml-2"
                    data-testid={"blocked-badge-#{member.user.id}"}
                  >
                    Blocked
                  </.badge>
                </td>
                <td class="py-3.5 px-4">{member.user.name || "-"}</td>
                <td class="py-3.5 px-4">
                  <.badge variant="muted">{role_label(member.role)}</.badge>
                </td>
              </tr>
            </tbody>
            <tbody id="pending-invitations-list" phx-update="stream">
              <tr
                :for={{dom_id, inv} <- @streams.pending_invitations}
                id={dom_id}
                class="border-b border-border/50 hover:bg-muted/50 transition-colors"
                data-testid={"invitation-row-#{inv.id}"}
              >
                <td class="py-3.5 px-4">
                  <.link
                    navigate={invitation_path(@current_company.id, inv)}
                    class="hover:underline underline-offset-4"
                    data-testid={"invitation-link-#{inv.id}"}
                  >
                    <div>{inv.email}</div>
                  </.link>
                  <div class="text-xs text-muted-foreground mt-0.5">
                    Pending — expires {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
                  </div>
                </td>
                <td class="py-3.5 px-4">-</td>
                <td class="py-3.5 px-4">
                  <.badge variant="muted">{role_label(inv.role)}</.badge>
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
