defmodule KsefHubWeb.TeamLive do
  @moduledoc """
  LiveView for team management — owner-only page to view members,
  send invitations, cancel pending invitations, and remove members.
  """

  use KsefHubWeb, :live_view

  alias KsefHub.Companies
  alias KsefHub.Invitations
  alias KsefHub.Invitations.InvitationNotifier

  @doc "Mounts the team page. Redirects non-owners to dashboard."
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_role == "owner" do
      {:ok,
       socket
       |> assign(page_title: "Team")
       |> assign(invite_form: to_form(%{"email" => "", "role" => "accountant"}, as: :invitation))
       |> load_team_data()}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only the owner can manage the team.")
       |> redirect(to: "/dashboard")}
    end
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
        send_invitation_email(invitation, token, company)

        {:noreply,
         socket
         |> put_flash(:info, "Invitation sent to #{invitation.email}.")
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
  def handle_event("remove_member", %{"user-id" => member_user_id}, socket) do
    company = socket.assigns.current_company

    case Companies.get_membership(member_user_id, company.id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Member not found.")}

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
    |> assign(members: members, pending_invitations: pending_invitations)
  end

  @spec send_invitation_email(Invitations.Invitation.t(), String.t(), map()) :: :ok
  defp send_invitation_email(invitation, token, company) do
    url = url(~p"/invitations/accept/#{token}")

    InvitationNotifier.deliver_invitation(
      invitation.email,
      url,
      %{company_name: company.name, role: invitation.role}
    )

    :ok
  end

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
    <div class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
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
              options={[{"Accountant", "accountant"}, {"Invoice Reviewer", "invoice_reviewer"}]}
            />
          </div>
          <button type="submit" class="btn btn-primary">
            <.icon name="hero-paper-airplane" class="size-4" /> Invite
          </button>
        </.form>
      </div>
    </div>

    <!-- Pending Invitations -->
    <div :if={@pending_invitations != []} class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold mb-3">Pending invitations</h2>
        <div class="overflow-x-auto">
          <table class="table table-sm" data-testid="pending-invitations">
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Expires</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={inv <- @pending_invitations} id={"invitation-#{inv.id}"}>
                <td>{inv.email}</td>
                <td><span class="badge badge-sm badge-outline">{inv.role}</span></td>
                <td class="text-sm text-base-content/60">
                  {Calendar.strftime(inv.expires_at, "%Y-%m-%d %H:%M UTC")}
                </td>
                <td>
                  <button
                    phx-click="cancel_invitation"
                    phx-value-id={inv.id}
                    data-confirm="Cancel this invitation?"
                    data-testid={"cancel-invitation-#{inv.id}"}
                    class="btn btn-xs btn-ghost text-error"
                  >
                    Cancel
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Members -->
    <div class="card bg-base-100 border border-base-300 mt-6">
      <div class="p-5">
        <h2 class="text-base font-semibold mb-3">Members</h2>
        <div class="overflow-x-auto" data-testid="member-list">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>Name</th>
                <th>Email</th>
                <th>Role</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={member <- @members} id={"member-#{member.user.id}"}>
                <td>{member.user.name || "—"}</td>
                <td>{member.user.email}</td>
                <td><span class="badge badge-sm badge-outline">{member.role}</span></td>
                <td>
                  <button
                    :if={member.role != "owner"}
                    phx-click="remove_member"
                    phx-value-user-id={member.user.id}
                    data-confirm="Remove this member from the company?"
                    data-testid={"remove-member-#{member.user.id}"}
                    class="btn btn-xs btn-ghost text-error"
                  >
                    Remove
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
