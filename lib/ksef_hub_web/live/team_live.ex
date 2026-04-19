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
    |> assign(:pending_invitations_count, length(pending_invitations))
  end

  @spec role_label(Membership.role()) :: String.t()
  defp role_label(role), do: Membership.role_label(role)

  @spec invitation_expired?(Invitations.Invitation.t()) :: boolean()
  defp invitation_expired?(%{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

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
        <div data-testid="member-list">
          <.table_container>
            <table class="w-full text-sm" data-testid="team-table">
              <thead>
                <tr class="border-b border-border">
                  <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                    Email
                  </th>
                  <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                    Name
                  </th>
                  <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                    Role
                  </th>
                  <th class="w-0 py-2.5 pr-3 pl-0"></th>
                </tr>
              </thead>
              <tbody id="members-list" phx-update="stream">
                <tr
                  :for={{dom_id, member} <- @streams.members}
                  id={dom_id}
                  class="group border-b border-border hover:bg-shad-accent transition-colors cursor-pointer"
                  data-testid={"member-row-#{member.user.id}"}
                >
                  <td
                    class="py-3 px-4"
                    phx-click={JS.navigate(member_path(@current_company.id, member))}
                    data-testid={"member-link-#{member.user.id}"}
                  >
                    <span class="font-mono text-xs">{member.user.email}</span>
                  </td>
                  <td class="py-3 px-4 text-sm" phx-click={JS.navigate(member_path(@current_company.id, member))}>
                    {member.user.name || "-"}
                  </td>
                  <td class="py-3 px-4" phx-click={JS.navigate(member_path(@current_company.id, member))}>
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
                  <td class="w-0 py-3 pr-3 pl-0">
                    <.icon name="hero-chevron-right" class="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                  </td>
                </tr>
              </tbody>
            </table>
          </.table_container>
        </div>
      </.card>
      <.card :if={@pending_invitations_count > 0} class="mt-6">
        <h2 class="text-base font-semibold mb-3">Pending Invitations</h2>
        <.table_container>
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border">
                <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Email
                </th>
                <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Expires
                </th>
                <th class="text-left py-2.5 px-4 text-xs font-medium text-muted-foreground uppercase tracking-wide">
                  Role
                </th>
                <th class="w-0 py-2.5 pr-3 pl-0"></th>
              </tr>
            </thead>
            <tbody id="pending-invitations-list" phx-update="stream">
              <tr
                :for={{dom_id, inv} <- @streams.pending_invitations}
                id={dom_id}
                class="group border-b border-border hover:bg-shad-accent transition-colors cursor-pointer"
                data-testid={"invitation-row-#{inv.id}"}
              >
                <td
                  class="py-3 px-4"
                  phx-click={JS.navigate(invitation_path(@current_company.id, inv))}
                  data-testid={"invitation-link-#{inv.id}"}
                >
                  <span class="font-mono text-xs">{inv.email}</span>
                </td>
                <td class="py-3 px-4" phx-click={JS.navigate(invitation_path(@current_company.id, inv))}>
                  <span class="font-mono text-xs text-muted-foreground">
                    {Calendar.strftime(inv.expires_at, "%Y-%m-%d")}
                  </span>
                  <.badge
                    :if={invitation_expired?(inv)}
                    variant="error"
                    class="ml-2"
                    data-testid={"expired-badge-#{inv.id}"}
                  >
                    Expired
                  </.badge>
                </td>
                <td class="py-3 px-4" phx-click={JS.navigate(invitation_path(@current_company.id, inv))}>
                  <.badge variant="muted">{role_label(inv.role)}</.badge>
                </td>
                <td class="w-0 py-3 pr-3 pl-0">
                  <.icon name="hero-chevron-right" class="size-3.5 text-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" />
                </td>
              </tr>
            </tbody>
          </table>
        </.table_container>
      </.card>
    </.settings_layout>
    """
  end
end
