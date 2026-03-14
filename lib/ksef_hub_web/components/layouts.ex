defmodule KsefHubWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KsefHubWeb, :html

  alias KsefHub.Authorization

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_company, :map, default: nil

  attr :current_role, :string,
    default: nil,
    doc: "the user's role for the current company membership"

  attr :companies, :list, default: []

  @doc "Renders the main application layout with top navbar navigation."
  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-background text-foreground">
      <header class="sticky top-0 z-50 w-full border-b border-border bg-background/95 backdrop-blur supports-backdrop-filter:bg-background/60">
        <div class="flex h-14 items-center px-4 lg:px-6">
          <!-- Logo -->
          <.logo
            href={
              if @current_company, do: ~p"/c/#{@current_company.id}/invoices", else: ~p"/companies"
            }
            class="mr-6"
          />

          <div class="flex-1" />
          
    <!-- Theme toggle + Company selector + avatar menu -->
          <div class="flex items-center gap-2">
            <.theme_toggle />

            <div :if={@current_company} class="dropdown dropdown-end">
              <div
                tabindex="0"
                role="button"
                class="inline-flex items-center gap-1.5 h-9 px-3 text-sm rounded-md border border-border bg-background hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
                data-testid="company-selector"
              >
                <.icon name="hero-building-office-2" class="size-3.5" />
                <span class="hidden sm:inline truncate max-w-32" data-testid="current-company-name">
                  {@current_company.name}
                </span>
                <.icon name="hero-chevron-down" class="size-3 opacity-50" />
              </div>
              <div
                tabindex="0"
                class="dropdown-content z-50 p-1 border border-border bg-popover text-popover-foreground rounded-md shadow-md w-56"
              >
                <form
                  :for={company <- @companies}
                  method="post"
                  action={~p"/switch-company/#{company.id}"}
                >
                  <input
                    type="hidden"
                    name="_csrf_token"
                    value={Plug.CSRFProtection.get_csrf_token()}
                  />
                  <input
                    type="hidden"
                    name="return_to"
                    value={rewrite_company_path(@current_path, company.id)}
                  />
                  <button
                    type="submit"
                    class={[
                      "w-full text-left px-2 py-1.5 rounded-sm transition-colors",
                      company.id == @current_company.id &&
                        "bg-shad-accent text-shad-accent-foreground",
                      company.id != @current_company.id &&
                        "hover:bg-shad-accent hover:text-shad-accent-foreground"
                    ]}
                  >
                    <span class="block truncate text-sm">{company.name}</span>
                    <span class="block text-xs text-muted-foreground">{company.nip}</span>
                  </button>
                </form>
              </div>
            </div>
            
    <!-- Mobile nav menu -->
            <div :if={@current_company} class="dropdown dropdown-end md:hidden">
              <div
                tabindex="0"
                role="button"
                class="inline-flex items-center justify-center h-8 w-8 rounded-md hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors cursor-pointer"
              >
                <.icon name="hero-bars-3" class="size-4" />
              </div>
              <div
                tabindex="0"
                class="dropdown-content z-50 p-1 border border-border bg-popover text-popover-foreground rounded-md shadow-md w-56"
              >
                <.nav_item_list
                  items={nav_items(@current_company, @current_role)}
                  current_path={@current_path}
                />
              </div>
            </div>

            <div :if={@current_user} class="dropdown dropdown-end">
              <div
                tabindex="0"
                role="button"
                class="flex items-center justify-center h-8 w-8 rounded-full bg-shad-primary text-shad-primary-foreground text-xs font-medium cursor-pointer hover:opacity-90 transition-opacity"
              >
                {initial(@current_user.email)}
              </div>
              <div
                tabindex="0"
                class="dropdown-content z-50 p-1 border border-border bg-popover text-popover-foreground rounded-md shadow-md w-56"
              >
                <div class="px-2 py-1.5 text-xs text-muted-foreground truncate">
                  {@current_user.email}
                </div>
                <div class="border-t border-border my-1"></div>
                <.nav_item_list
                  items={nav_items(@current_company, @current_role)}
                  current_path={@current_path}
                />
                <div class="border-t border-border my-1"></div>
                <.link
                  href={~p"/users/log-out"}
                  method="delete"
                  class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-sm hover:bg-shad-accent hover:text-shad-accent-foreground transition-colors"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                </.link>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main class="flex-1 p-4 sm:p-6 lg:p-8">
        <div class="mx-auto max-w-7xl">
          {@inner_content}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @spec nav_items(map() | nil, atom() | nil) :: [map()]
  defp nav_items(nil, _role), do: []

  defp nav_items(company, role) do
    id = company.id

    [
      {nil, nil, "Invoices", ~p"/c/#{id}/invoices", "hero-document-text"},
      {nil, :view_payment_requests, "Payments", ~p"/c/#{id}/payment-requests",
       "hero-banknotes"},
      {nil, nil, "Dashboard", ~p"/c/#{id}/dashboard", "hero-home"},
      {nil, :manage_categories, "Categories", ~p"/c/#{id}/categories", "hero-squares-2x2"},
      {nil, :manage_tags, "Tags", ~p"/c/#{id}/tags", "hero-tag"},
      {nil, :view_exports, "Exports", ~p"/c/#{id}/exports", "hero-arrow-down-tray"},
      {nil, :view_syncs, "Syncs", ~p"/c/#{id}/syncs", "hero-arrow-path"},
      {nil, :manage_company, "Companies", ~p"/companies", "hero-building-office-2"},
      {"Admin", :manage_certificates, "Certificates", ~p"/c/#{id}/certificates",
       "hero-shield-check"},
      {nil, :manage_tokens, "API Tokens", ~p"/c/#{id}/tokens", "hero-key"},
      {nil, :manage_team, "Team", ~p"/c/#{id}/team", "hero-user-group"}
    ]
    |> Enum.filter(fn {_section, perm, _label, _path, _icon} ->
      is_nil(perm) or Authorization.can?(role, perm)
    end)
    |> Enum.map(fn {section, _perm, label, path, icon} ->
      %{section: section, label: label, path: path, icon: icon}
    end)
  end

  @spec initial(String.t() | nil) :: String.t()
  defp initial(nil), do: "?"
  defp initial(""), do: "?"
  defp initial(email), do: email |> String.first() |> String.upcase()

  @spec rewrite_company_path(String.t() | nil, Ecto.UUID.t()) :: String.t()
  defp rewrite_company_path(nil, company_id), do: ~p"/c/#{company_id}/invoices"

  defp rewrite_company_path(path, company_id) do
    if String.match?(path, ~r"^/c/[^/]+") do
      Regex.replace(~r"^/c/[^/]+", path, "/c/#{company_id}")
    else
      ~p"/c/#{company_id}/invoices"
    end
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  @doc "Renders a minimal public layout with just the logo — no auth UI, no company selector."
  @spec public(map()) :: Phoenix.LiveView.Rendered.t()
  def public(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-background text-foreground">
      <header class="border-b border-border bg-background px-4">
        <div class="flex h-14 items-center">
          <.logo href={~p"/"} />
        </div>
      </header>

      <main class="flex-1 p-4 sm:p-6 lg:p-8">
        <div class="mx-auto max-w-7xl">
          {@inner_content}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  @spec flash_group(map()) :: Phoenix.LiveView.Rendered.t()
  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:warning} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  @spec theme_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center border border-border bg-muted rounded-full">
      <div class="absolute w-1/3 h-full rounded-full bg-background shadow-sm left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
