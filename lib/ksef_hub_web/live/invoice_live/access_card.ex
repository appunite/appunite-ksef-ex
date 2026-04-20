defmodule KsefHubWeb.InvoiceLive.AccessCard do
  @moduledoc """
  Access-tab UI for the invoice show page.

  Renders the share-link banner (active or disabled state) and the
  access-grants card (mode toggle + grants table / empty state).

  The public entry point is `card/1`. Several small helpers (`role_palette/1`,
  `access_summary_label/2`, `granter_label/1`, etc.) are exposed so tests can
  exercise the branch logic without rendering a full template.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import KsefHubWeb.CoreComponents, only: [avatar: 1, button: 1, card: 1, icon: 1]

  # ---------------------------------------------------------------------------
  # Public entry point
  # ---------------------------------------------------------------------------

  attr :access_grants, :list, required: true
  attr :members_requiring_grants, :list, required: true
  attr :member_roles, :map, required: true
  attr :invoice, :map, required: true
  attr :public_link, :any, default: nil
  attr :can_manage_access, :boolean, default: false
  attr :can_share, :boolean, default: false

  @doc "Full access card: share link banner on top, grants card below."
  @spec access_card(map()) :: Phoenix.LiveView.Rendered.t()
  def access_card(assigns) do
    granted_user_ids = MapSet.new(assigns.access_grants, & &1.user_id)

    members_already_granted =
      Enum.reject(assigns.members_requiring_grants, &MapSet.member?(granted_user_ids, &1.user_id))

    assigns = assign(assigns, members_already_granted: members_already_granted)

    ~H"""
    <div class="space-y-4">
      <.share_link_banner :if={@can_share} public_link={@public_link} />

      <.card :if={@can_manage_access} padding="p-0">
        <div class="flex items-center justify-between px-4 py-3 border-b border-border">
          <div class="flex items-center gap-3">
            <span class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              {access_summary_label(@invoice, @access_grants)}
            </span>
            <.access_mode_toggle invoice={@invoice} />
          </div>
          <.button
            :if={@invoice.access_restricted && @members_already_granted != []}
            size="sm"
            variant="outline"
            phx-click={JS.toggle(to: "#grant-access-form")}
            data-testid="grant-access-toggle"
          >
            <.icon name="hero-user-plus" class="size-3.5" /> Grant access
          </.button>
        </div>

        <div
          :if={@invoice.access_restricted && @members_already_granted != []}
          id="grant-access-form"
          class="hidden px-4 py-3 border-b border-border bg-muted/40"
        >
          <form phx-submit="grant_access" class="flex items-center gap-2">
            <select
              name="user_id"
              class="h-8 flex-1 rounded-md border border-input bg-background px-2 text-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option :for={member <- @members_already_granted} value={member.user_id}>
                {member.user.name || member.user.email}
              </option>
            </select>
            <.button type="submit" size="sm">Invite</.button>
          </form>
        </div>

        <div :if={!@invoice.access_restricted} class="px-4 py-6 text-sm text-muted-foreground">
          Team members with invoice-viewing permission can see this invoice. Switch to
          <strong class="text-foreground">Invited only</strong>
          to restrict access to a specific list.
        </div>

        <div
          :if={@invoice.access_restricted && @access_grants == []}
          class="px-4 py-6 text-sm text-muted-foreground"
        >
          No one has been invited yet. Only owners, admins, and accountants can view this invoice.
        </div>

        <table
          :if={@invoice.access_restricted && @access_grants != []}
          class="w-full text-sm"
        >
          <thead class="text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="border-b border-border">
              <th class="text-left px-4 py-2 font-medium">User</th>
              <th class="text-left px-4 py-2 font-medium">Role</th>
              <th class="text-left px-4 py-2 font-medium">Granted by</th>
              <th class="text-left px-4 py-2 font-medium">On</th>
              <th class="w-8"></th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={grant <- @access_grants}
              class="border-b border-border/50 last:border-0 group"
            >
              <td class="px-4 py-3">
                <.user_cell user={grant.user} />
              </td>
              <td class="px-4 py-3">
                <.role_badge role={Map.get(@member_roles, grant.user_id)} />
              </td>
              <td class="px-4 py-3 text-muted-foreground">
                {granter_label(grant.granted_by)}
              </td>
              <td class="px-4 py-3 font-mono text-xs text-muted-foreground">
                {Calendar.strftime(grant.inserted_at, "%Y-%m-%d")}
              </td>
              <td class="w-8 pr-4 py-3 text-right">
                <button
                  phx-click="revoke_access"
                  phx-value-user_id={grant.user_id}
                  class="opacity-0 group-hover:opacity-100 focus:opacity-100 focus-visible:opacity-100 text-muted-foreground hover:text-shad-destructive transition-opacity"
                  aria-label={"Remove #{grant.user.name || grant.user.email}"}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </.card>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Share link banner (active / disabled)
  # ---------------------------------------------------------------------------

  attr :public_link, :any, default: nil

  @spec share_link_banner(map()) :: Phoenix.LiveView.Rendered.t()
  defp share_link_banner(%{public_link: url} = assigns) when is_binary(url) do
    ~H"""
    <div class="rounded-lg border border-blue-200 bg-blue-50/50 dark:border-blue-900/40 dark:bg-blue-900/10 px-4 py-3">
      <div class="flex items-start gap-3">
        <.icon name="hero-link" class="size-5 text-muted-foreground shrink-0 mt-0.5" />
        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium">Share link active</p>
          <p class="text-xs text-muted-foreground mb-2">
            Anyone with this link can view this invoice. Expires in 30 days.
          </p>
          <div class="flex items-center gap-2">
            <input
              id="public-link-url-input"
              type="text"
              readonly
              value={@public_link}
              class="h-8 flex-1 min-w-0 rounded-md border border-input bg-background px-2 text-xs font-mono focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
              data-testid="public-link-url"
              phx-hook="SelectOnClick"
            />
            <.button
              size="sm"
              variant="outline"
              phx-click="copy_public_link"
              data-testid="copy-public-link"
            >
              <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
            </.button>
            <.button
              size="sm"
              variant="outline"
              phx-click="revoke_public_link"
              data-confirm="Revoke this share link? Anyone who has it will lose access."
              data-testid="revoke-public-link"
            >
              <.icon name="hero-x-mark" class="size-3.5" /> Revoke
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp share_link_banner(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-4 rounded-lg border border-blue-200 bg-blue-50/50 dark:border-blue-900/40 dark:bg-blue-900/10 px-4 py-3">
      <div class="flex items-start gap-3 min-w-0">
        <.icon name="hero-link" class="size-5 text-muted-foreground shrink-0 mt-0.5" />
        <div class="min-w-0">
          <p class="text-sm font-medium">Share link disabled</p>
          <p class="text-xs text-muted-foreground">
            Click “Create link” to generate a shareable URL. Anyone with the link can view this invoice.
          </p>
        </div>
      </div>
      <.button
        size="sm"
        variant="outline"
        phx-click="create_public_link"
        data-testid="create-public-link"
      >
        <.icon name="hero-plus" class="size-3.5" /> Create link
      </.button>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Access mode toggle (Team default ↔ Invited only)
  # ---------------------------------------------------------------------------

  attr :invoice, :map, required: true

  @spec access_mode_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  defp access_mode_toggle(assigns) do
    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click={JS.toggle(to: "#access-mode-menu")}
        aria-haspopup="listbox"
        class="inline-flex items-center gap-1.5 rounded-md border border-input bg-background px-2.5 py-1 text-xs font-medium hover:bg-accent hover:text-accent-foreground"
      >
        <.icon
          name={if(@invoice.access_restricted, do: "hero-lock-closed", else: "hero-users")}
          class="size-3.5 text-muted-foreground"
        />
        {if @invoice.access_restricted, do: "Invited only", else: "Team default"}
        <.icon name="hero-chevron-down" class="size-3 text-muted-foreground" />
      </button>
      <div
        id="access-mode-menu"
        role="listbox"
        class="hidden absolute left-0 top-full mt-1 z-50 w-56 rounded-md border border-border bg-popover text-popover-foreground shadow-md"
        phx-click-away={JS.hide(to: "#access-mode-menu")}
      >
        <.access_mode_option
          label="Team default"
          icon="hero-users"
          active?={!@invoice.access_restricted}
          position="first"
        />
        <.access_mode_option
          label="Invited only"
          icon="hero-lock-closed"
          active?={@invoice.access_restricted}
          position="last"
        />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :active?, :boolean, required: true
  attr :position, :string, required: true, values: ~w(first last)

  @spec access_mode_option(map()) :: Phoenix.LiveView.Rendered.t()
  defp access_mode_option(assigns) do
    ~H"""
    <div
      :if={@active?}
      role="option"
      aria-selected="true"
      class={[
        "flex items-center gap-2.5 px-3 py-2 text-sm bg-shad-accent",
        @position == "first" && "rounded-t-md",
        @position == "last" && "rounded-b-md"
      ]}
    >
      <.icon name={@icon} class="size-4 text-muted-foreground" />
      <span>{@label}</span>
      <.icon name="hero-check" class="size-4 ml-auto" />
    </div>
    <button
      :if={!@active?}
      type="button"
      role="option"
      aria-selected="false"
      phx-click={JS.hide(to: "#access-mode-menu") |> JS.push("toggle_access_restricted")}
      class={[
        "flex w-full items-center gap-2.5 px-3 py-2 text-sm hover:bg-shad-accent",
        @position == "first" && "rounded-t-md",
        @position == "last" && "rounded-b-md"
      ]}
    >
      <.icon name={@icon} class="size-4 text-muted-foreground" />
      <span>{@label}</span>
    </button>
    """
  end

  # ---------------------------------------------------------------------------
  # User cell (avatar + name/email)
  # ---------------------------------------------------------------------------

  attr :user, :map, required: true

  @spec user_cell(map()) :: Phoenix.LiveView.Rendered.t()
  defp user_cell(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <.avatar user={@user} />
      <div class="min-w-0">
        <div class="font-medium truncate">{@user.name || @user.email}</div>
        <div :if={@user.name} class="text-xs text-muted-foreground truncate">{@user.email}</div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Role badge
  # ---------------------------------------------------------------------------

  attr :role, :atom, default: nil

  @spec role_badge(map()) :: Phoenix.LiveView.Rendered.t()
  defp role_badge(%{role: nil} = assigns) do
    ~H"""
    <span class="text-xs text-muted-foreground">—</span>
    """
  end

  defp role_badge(assigns) do
    assigns = assign(assigns, :palette, role_palette(assigns.role))

    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
      @palette
    ]}>
      {role_label(@role)}
    </span>
    """
  end

  # ---------------------------------------------------------------------------
  # Exposed helpers (public so they're unit-testable)
  # ---------------------------------------------------------------------------

  @doc "Short summary label rendered above the grants table."
  @spec access_summary_label(map(), [map()]) :: String.t()
  def access_summary_label(%{access_restricted: true}, grants) do
    case length(grants) do
      0 -> "No one invited"
      1 -> "1 person has access"
      n -> "#{n} people have access"
    end
  end

  def access_summary_label(%{access_restricted: false}, _grants), do: "Team default"

  @doc "Display label for the user who granted access, falling back to an em-dash."
  @spec granter_label(map() | nil) :: String.t()
  def granter_label(nil), do: "—"
  def granter_label(%Ecto.Association.NotLoaded{}), do: "—"
  def granter_label(%{name: name}) when is_binary(name) and name != "", do: name
  def granter_label(%{email: email}), do: email

  @doc "Returns a Tailwind class string for a role badge background/foreground."
  @spec role_palette(atom()) :: String.t()
  def role_palette(:owner),
    do: "bg-rose-100 text-rose-800 dark:bg-rose-900/40 dark:text-rose-300"

  def role_palette(:admin),
    do: "bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300"

  def role_palette(:accountant),
    do: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/40 dark:text-emerald-300"

  def role_palette(:approver),
    do: "bg-amber-100 text-amber-800 dark:bg-amber-900/40 dark:text-amber-300"

  def role_palette(:editor),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300"

  def role_palette(:viewer),
    do: "bg-slate-100 text-slate-700 dark:bg-slate-800/60 dark:text-slate-300"

  def role_palette(_), do: "bg-muted text-muted-foreground"

  @doc "Humanized role label (e.g. :owner → \"Owner\")."
  @spec role_label(atom()) :: String.t()
  def role_label(role) when is_atom(role) and not is_nil(role),
    do: role |> Atom.to_string() |> String.capitalize()

  def role_label(_), do: "—"
end
