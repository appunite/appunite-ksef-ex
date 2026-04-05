defmodule KsefHubWeb.SettingsComponents do
  @moduledoc """
  Shared layout component for the Settings pages.

  Renders a two-column layout with a sidebar for navigation between
  settings tabs (General, Exports, Syncs, Categories, Tags, Bank Accounts, Team, API Tokens, Certificates)
  and a content area for the active tab.
  """
  use KsefHubWeb, :html

  alias KsefHub.Authorization

  @doc """
  Renders the settings layout with a sidebar and content area.

  All three attributes are automatically available in LiveView assigns
  via `LiveAuth`, so callers just forward them through.
  """
  attr :current_path, :string, required: true
  attr :current_company, :map, required: true
  attr :current_role, :atom, default: nil

  slot :inner_block, required: true

  @spec settings_layout(map()) :: Phoenix.LiveView.Rendered.t()
  def settings_layout(assigns) do
    assigns = assign(assigns, :tabs, settings_tabs(assigns.current_company, assigns.current_role))

    ~H"""
    <div class="flex flex-col md:flex-row gap-6">
      <%!-- Sidebar: horizontal scroll on mobile, vertical on desktop --%>
      <nav class="md:w-56 shrink-0" aria-label="Settings">
        <div class="flex md:flex-col gap-1 overflow-x-auto md:overflow-x-visible pb-2 md:pb-0">
          <.link
            :for={tab <- @tabs}
            navigate={tab.path}
            class={[
              "flex items-center gap-2 px-3 py-2 text-sm rounded-md whitespace-nowrap transition-colors",
              if(active_tab?(@current_path, tab.path),
                do: "bg-shad-accent text-shad-accent-foreground font-medium",
                else: "text-muted-foreground hover:bg-shad-accent hover:text-shad-accent-foreground"
              )
            ]}
          >
            <.icon name={tab.icon} class="size-4 shrink-0" />
            {tab.label}
          </.link>
        </div>
      </nav>

      <%!-- Content area --%>
      <div class="flex-1 min-w-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @spec settings_tabs(map(), atom() | nil) :: [map()]
  defp settings_tabs(company, role) do
    id = company.id

    [
      {nil, "General", ~p"/c/#{id}/settings", "hero-cog-6-tooth"},
      {:view_exports, "Exports", ~p"/c/#{id}/settings/exports", "hero-arrow-down-tray"},
      {:view_syncs, "Syncs", ~p"/c/#{id}/settings/syncs", "hero-arrow-path"},
      {:manage_categories, "Categories", ~p"/c/#{id}/settings/categories", "hero-squares-2x2"},
      {:manage_bank_accounts, "Bank Accounts", ~p"/c/#{id}/settings/bank-accounts",
       "hero-building-library"},
      {:manage_team, "Team", ~p"/c/#{id}/settings/team", "hero-user-group"},
      {:manage_tokens, "API Tokens", ~p"/c/#{id}/settings/tokens", "hero-key"},
      {:manage_certificates, "Certificates", ~p"/c/#{id}/settings/certificates",
       "hero-shield-check"},
      {:manage_team, "Activity Log", ~p"/c/#{id}/settings/activity-log", "hero-clock"}
    ]
    |> Enum.filter(fn {perm, _label, _path, _icon} ->
      is_nil(perm) or Authorization.can?(role, perm)
    end)
    |> Enum.map(fn {_perm, label, path, icon} ->
      %{label: label, path: path, icon: icon}
    end)
  end

  @spec active_tab?(String.t() | nil, String.t()) :: boolean()
  defp active_tab?(nil, _tab_path), do: false

  defp active_tab?(current_path, tab_path) do
    # Exact match for General (/settings), prefix match for others
    if String.ends_with?(tab_path, "/settings") do
      current_path == tab_path
    else
      String.starts_with?(current_path, tab_path)
    end
  end
end
