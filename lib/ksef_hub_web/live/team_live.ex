defmodule KsefHubWeb.TeamLive do
  @moduledoc """
  LiveView for team management — page for owners and admins to view members,
  send invitations, and navigate to member/invitation detail pages.
  """

  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Companies
  alias KsefHub.Companies.Membership
  alias KsefHub.Invitations

  @doc "Mounts the team page. Permission check is enforced by the :require_permission on_mount hook."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Team")
     |> stream(:members, [])
     |> stream(:pending_invitations, [])
     |> load_team_data()}
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

  defp role_label(role), do: Membership.role_label(role)

  @spec member_path(Ecto.UUID.t(), Companies.Membership.t()) :: String.t()
  defp member_path(company_id, member) do
    ~p"/c/#{company_id}/settings/team/members/#{member.id}"
  end

  @spec invitation_path(Ecto.UUID.t(), Invitations.Invitation.t()) :: String.t()
  defp invitation_path(company_id, invitation) do
    ~p"/c/#{company_id}/settings/team/invitations/#{invitation.id}"
  end

  @doc "Renders the team management page."
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  @impl true
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        Team
        <:subtitle>Manage members and invitations for {@current_company.name}</:subtitle>
        <:actions>
          <.button navigate={~p"/c/#{@current_company.id}/settings/team/invite"}>
            Invite Member
          </.button>
        </:actions>
      </.header>
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
                  </td>
                  <td class="py-3.5 px-4">{member.user.name || "-"}</td>
                  <td class="py-3.5 px-4">
                    <.badge variant="muted">{role_label(member.role)}</.badge>
                    <.badge
                      :if={member.status == :blocked}
                      variant="error"
                      class="ml-2"
                      data-testid={"blocked-badge-#{member.user.id}"}
                    >
                      Blocked
                    </.badge>
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
                      {inv.email}
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
    </.settings_layout>
    """
  end
end
