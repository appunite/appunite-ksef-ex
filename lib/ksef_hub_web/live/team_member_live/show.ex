defmodule KsefHubWeb.TeamMemberLive.Show do
  @moduledoc """
  Detail page for team members and invitations.

  Supports two modes via the live_action:
  - `:member` — edit name, change role, block/unblock
  - `:invitation` — view details, cancel if pending
  """

  use KsefHubWeb, :live_view

  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  alias KsefHub.Accounts
  alias KsefHub.Companies
  alias KsefHub.Companies.Membership
  alias KsefHub.Invitations

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @spec apply_action(Phoenix.LiveView.Socket.t(), atom(), map()) :: Phoenix.LiveView.Socket.t()
  defp apply_action(socket, :member, %{"id" => id}) do
    company = socket.assigns.current_company

    case Companies.get_membership_with_user(id, company.id) do
      nil ->
        socket
        |> put_flash(:error, "Member not found.")
        |> push_navigate(to: ~p"/c/#{company.id}/settings/team")

      membership ->
        socket
        |> assign(page_title: membership.user.name || membership.user.email)
        |> assign(membership: membership)
        |> assign(name_form: build_member_form(membership.user, membership))
        |> assign(selected_role: membership.role)
        |> assign(assignable_roles: assignable_roles(socket.assigns.current_role))
    end
  end

  defp apply_action(socket, :invitation, %{"id" => id}) do
    company = socket.assigns.current_company

    case Invitations.get_invitation(id, company.id) do
      nil ->
        socket
        |> put_flash(:error, "Invitation not found.")
        |> push_navigate(to: ~p"/c/#{company.id}/settings/team")

      invitation ->
        socket
        |> assign(page_title: "Invitation — #{invitation.email}")
        |> assign(invitation: invitation)
    end
  end

  @impl true
  def handle_event("validate_member", %{"user" => params}, socket) do
    selected_role =
      case parse_role(params["role"] || "") do
        {:ok, role} -> role
        _ -> socket.assigns.selected_role
      end

    {:noreply,
     socket
     |> assign(selected_role: selected_role)
     |> assign(name_form: to_form(params, as: :user))}
  end

  @impl true
  def handle_event("save_member", %{"user" => params}, socket) do
    membership = socket.assigns.membership

    with :ok <- validate_role_change(membership, params["role"], socket),
         {:ok, role_atom} <- resolve_role(params["role"]),
         {:ok, %{user: updated_user, membership: updated_membership}} <-
           Companies.update_member(membership, params["name"], role_atom) do
      updated_membership = %{updated_membership | user: updated_user}

      {:noreply,
       socket
       |> assign(membership: updated_membership)
       |> assign(selected_role: updated_membership.role)
       |> assign(name_form: build_member_form(updated_user, updated_membership))
       |> put_flash(:info, "Changes saved.")}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _, _, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save changes.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save changes.")}
    end
  end

  @impl true
  def handle_event("block_member", _params, socket) do
    membership = socket.assigns.membership
    current_user = socket.assigns.current_user

    with :ok <- check_not_owner(membership),
         :ok <- check_not_self(membership.user_id, current_user.id) do
      case Companies.block_member(membership) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(membership: %{updated | user: membership.user})
           |> put_flash(:info, "Member blocked.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to block member.")}
      end
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_event("unblock_member", _params, socket) do
    membership = socket.assigns.membership

    if membership.status == :blocked do
      case Companies.unblock_member(membership) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(membership: %{updated | user: membership.user})
           |> put_flash(:info, "Member unblocked.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to unblock member.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Member is not blocked.")}
    end
  end

  @impl true
  def handle_event("cancel_invitation", _params, socket) do
    invitation = socket.assigns.invitation
    user = socket.assigns.current_user

    case Invitations.cancel_invitation(user.id, invitation.id) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(invitation: updated)
         |> put_flash(:info, "Invitation cancelled.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel invitation.")}
    end
  end

  # --- Private helpers ---

  @spec build_member_form(Accounts.User.t(), Membership.t()) :: Phoenix.HTML.Form.t()
  defp build_member_form(user, membership) do
    to_form(%{"name" => user.name || "", "role" => membership.role}, as: :user)
  end

  @spec validate_role_change(Membership.t(), String.t() | nil, Phoenix.LiveView.Socket.t()) ::
          :ok | {:error, String.t()}
  defp validate_role_change(_membership, nil, _socket), do: :ok

  defp validate_role_change(membership, role, socket) do
    current_user = socket.assigns.current_user
    allowed_roles = assignable_roles(socket.assigns.current_role)

    with {:ok, role_atom} <- parse_role(role),
         :ok <- check_not_self(membership.user_id, current_user.id),
         :ok <- check_not_owner(membership) do
      check_role_allowed(role_atom, allowed_roles)
    end
  end

  @spec resolve_role(String.t() | nil) :: {:ok, atom() | nil}
  defp resolve_role(nil), do: {:ok, nil}
  defp resolve_role(role), do: parse_role(role)

  @spec auth_method(Accounts.User.t()) :: String.t()
  defp auth_method(%{google_uid: uid}) when is_binary(uid), do: "Google"
  defp auth_method(%{hashed_password: pw}) when is_binary(pw), do: "Email"
  defp auth_method(_), do: "Unknown"

  defdelegate role_description(role), to: Membership

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

  @spec check_not_owner(Membership.t()) :: :ok | {:error, String.t()}
  defp check_not_owner(%{role: :owner}), do: {:error, "Cannot change owner's role."}
  defp check_not_owner(_), do: :ok

  @spec check_role_allowed(atom(), [atom()]) :: :ok | {:error, String.t()}
  defp check_role_allowed(role, allowed) do
    if role in allowed, do: :ok, else: {:error, "Invalid role."}
  end

  defdelegate assignable_roles(role), to: Membership

  defdelegate role_label(role), to: Membership

  @spec invitation_status_variant(atom()) :: String.t()
  defp invitation_status_variant(:pending), do: "warning"
  defp invitation_status_variant(:accepted), do: "success"
  defp invitation_status_variant(:cancelled), do: "error"
  defp invitation_status_variant(_), do: "muted"

  @spec can_block?(map()) :: boolean()
  defp can_block?(assigns) do
    membership = assigns.membership
    current_user = assigns.current_user

    membership.role != :owner &&
      membership.user_id != current_user.id &&
      membership.status == :active
  end

  @spec can_unblock?(map()) :: boolean()
  defp can_unblock?(assigns) do
    assigns.membership.status == :blocked
  end

  @spec can_manage_role?(map()) :: boolean()
  defp can_manage_role?(assigns) do
    membership = assigns.membership

    assigns.assignable_roles != [] &&
      membership.role != :owner &&
      membership.user_id != assigns.current_user.id &&
      membership.status == :active
  end

  @impl true
  def render(%{live_action: :member} = assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        <.link
          navigate={~p"/c/#{@current_company.id}/settings/team"}
          class="text-muted-foreground hover:text-foreground text-sm"
        >
          &larr; Back to team
        </.link>
      </.header>

      <.card class="mt-6">
        <h2 class="text-base font-semibold mb-4">Member details</h2>

        <div class="mb-4">
          <label class="block text-sm font-medium text-muted-foreground mb-1">Email</label>
          <div class="text-sm" data-testid="member-email">{@membership.user.email}</div>
        </div>

        <div class="mb-4 flex gap-6">
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">Auth method</label>
            <div class="text-sm" data-testid="auth-method">{auth_method(@membership.user)}</div>
          </div>
          <div>
            <label class="block text-sm font-medium text-muted-foreground mb-1">Joined</label>
            <div class="text-sm">{Calendar.strftime(@membership.inserted_at, "%Y-%m-%d")}</div>
          </div>
        </div>

        <div :if={@membership.status == :blocked} class="mb-4">
          <.badge variant="error" data-testid="blocked-badge">Blocked</.badge>
        </div>

        <.form
          for={@name_form}
          phx-submit="save_member"
          phx-change="validate_member"
          data-testid="name-form"
        >
          <div class="mb-4">
            <.input field={@name_form[:name]} type="text" label="Name" />
          </div>

          <div class="mb-1">
            <.input
              :if={can_manage_role?(assigns)}
              field={@name_form[:role]}
              type="select"
              label="Role"
              options={Enum.map(@assignable_roles, &{role_label(&1), &1})}
              value={@membership.role}
              data-testid="role-select"
            />
            <div :if={!can_manage_role?(assigns)}>
              <label class="block text-sm font-medium text-muted-foreground mb-1">Role</label>
              <.badge variant="muted">{role_label(@membership.role)}</.badge>
            </div>
          </div>

          <p class="text-xs text-muted-foreground mb-6">{role_description(@selected_role)}</p>

          <div class="flex items-center gap-3 pt-4 border-t border-border">
            <.button type="submit" size="sm">Save</.button>
            <.button
              :if={can_block?(assigns)}
              type="button"
              variant="outline-destructive"
              size="sm"
              phx-click="block_member"
              data-confirm="Block this member? They will lose all access to the company."
              data-testid="block-button"
            >
              Block member
            </.button>
            <.button
              :if={can_unblock?(assigns)}
              type="button"
              variant="outline"
              size="sm"
              phx-click="unblock_member"
              data-testid="unblock-button"
            >
              Unblock member
            </.button>
          </div>
        </.form>
      </.card>
    </.settings_layout>
    """
  end

  def render(%{live_action: :invitation} = assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        <.link
          navigate={~p"/c/#{@current_company.id}/settings/team"}
          class="text-muted-foreground hover:text-foreground text-sm"
        >
          &larr; Back to team
        </.link>
      </.header>

      <.card class="mt-6">
        <h2 class="text-base font-semibold mb-4">Invitation details</h2>

        <div class="mb-4">
          <label class="block text-sm font-medium text-muted-foreground mb-1">Email</label>
          <div class="text-sm" data-testid="invitation-email">{@invitation.email}</div>
        </div>

        <div class="mb-4">
          <label class="block text-sm font-medium text-muted-foreground mb-1">Role</label>
          <.badge variant="muted">{role_label(@invitation.role)}</.badge>
        </div>

        <div class="mb-4">
          <label class="block text-sm font-medium text-muted-foreground mb-1">Status</label>
          <.badge
            variant={invitation_status_variant(@invitation.status)}
            data-testid="invitation-status"
          >
            {Atom.to_string(@invitation.status) |> String.capitalize()}
          </.badge>
        </div>

        <div class="mb-4">
          <label class="block text-sm font-medium text-muted-foreground mb-1">Expires</label>
          <span class="text-sm">{Calendar.strftime(@invitation.expires_at, "%Y-%m-%d %H:%M")}</span>
        </div>

        <div :if={@invitation.status == :pending} class="mt-6 pt-4 border-t border-border">
          <.button
            variant="outline-destructive"
            size="sm"
            phx-click="cancel_invitation"
            data-confirm="Cancel this invitation?"
            data-testid="cancel-invitation-button"
          >
            Cancel invitation
          </.button>
        </div>
      </.card>
    </.settings_layout>
    """
  end
end
