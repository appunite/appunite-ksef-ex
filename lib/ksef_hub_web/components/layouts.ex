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
    <div class="min-h-screen flex flex-col">
      <div class="navbar bg-base-100 border-b border-base-300 px-4">
        <!-- navbar-start: logo -->
        <div class="navbar-start">
          <a
            href={
              if @current_company, do: ~p"/c/#{@current_company.id}/invoices", else: ~p"/companies"
            }
            class="btn btn-ghost gap-2 h-auto py-1"
          >
            <.icon name="hero-document-text" class="size-5 text-primary" />
            <span class="flex flex-col items-start leading-tight">
              <span class="text-lg font-bold">Invoi</span>
              <span class="text-[10px] text-base-content/50 font-normal">by Appunite</span>
            </span>
          </a>
        </div>
        
    <!-- navbar-end: company selector + avatar menu -->
        <div class="navbar-end gap-1">
          <div :if={@current_company} class="dropdown dropdown-end">
            <div
              tabindex="0"
              role="button"
              class="btn btn-ghost btn-sm gap-1"
              data-testid="company-selector"
            >
              <.icon name="hero-building-office-2" class="size-4" />
              <span class="hidden sm:inline truncate max-w-32" data-testid="current-company-name">
                {@current_company.name}
              </span>
              <.icon name="hero-chevron-down" class="size-3" />
            </div>
            <ul
              tabindex="0"
              class="dropdown-content z-50 menu p-2 border border-base-300 bg-base-100 rounded-box w-56"
            >
              <li :for={company <- @companies}>
                <form method="post" action={~p"/switch-company/#{company.id}"}>
                  <input
                    type="hidden"
                    name="_csrf_token"
                    value={Plug.CSRFProtection.get_csrf_token()}
                  />
                  <input
                    type="hidden"
                    name="return_to"
                    value={@current_path || ~p"/c/#{company.id}/invoices"}
                  />
                  <button
                    type="submit"
                    class={[
                      "w-full text-left min-w-0",
                      company.id == @current_company.id && "active"
                    ]}
                  >
                    <span class="block truncate">{company.name}</span>
                    <span class="block text-xs text-base-content/50">{company.nip}</span>
                  </button>
                </form>
              </li>
            </ul>
          </div>

          <div :if={@current_user} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-circle avatar placeholder">
              <div class="bg-neutral text-neutral-content rounded-full w-8">
                <span class="text-xs">{initial(@current_user.email)}</span>
              </div>
            </div>
            <ul
              tabindex="0"
              class="dropdown-content z-50 menu p-2 border border-base-300 bg-base-100 rounded-box w-64"
            >
              <li class="menu-title text-xs truncate">{@current_user.email}</li>
              <li :if={@current_company}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/invoices"}
                  current={@current_path}
                  icon="hero-document-text"
                >
                  Invoices
                </.nav_link>
              </li>
              <li :if={@current_company}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/dashboard"}
                  current={@current_path}
                  icon="hero-home"
                >
                  Dashboard
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_categories)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/categories"}
                  current={@current_path}
                  icon="hero-squares-2x2"
                >
                  Categories
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_tags)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/tags"}
                  current={@current_path}
                  icon="hero-tag"
                >
                  Tags
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :view_exports)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/exports"}
                  current={@current_path}
                  icon="hero-arrow-down-tray"
                >
                  Exports
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :view_syncs)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/syncs"}
                  current={@current_path}
                  icon="hero-arrow-path"
                >
                  Syncs
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_company)}>
                <.nav_link
                  path={~p"/companies"}
                  current={@current_path}
                  icon="hero-building-office-2"
                >
                  Companies
                </.nav_link>
              </li>
              <li
                :if={@current_company && Authorization.can?(@current_role, :manage_team)}
                class="menu-title text-xs pt-2"
              >
                Admin
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_certificates)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/certificates"}
                  current={@current_path}
                  icon="hero-shield-check"
                >
                  Certificates
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_tokens)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/tokens"}
                  current={@current_path}
                  icon="hero-key"
                >
                  API Tokens
                </.nav_link>
              </li>
              <li :if={@current_company && Authorization.can?(@current_role, :manage_team)}>
                <.nav_link
                  path={~p"/c/#{@current_company.id}/team"}
                  current={@current_path}
                  icon="hero-user-group"
                >
                  Team
                </.nav_link>
              </li>
              <div class="divider my-1"></div>
              <li class="flex flex-row items-center justify-center px-2 py-1">
                <.theme_toggle />
              </li>
              <div class="divider my-1"></div>
              <li>
                <.link href={~p"/users/log-out"} method="delete">
                  <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
                </.link>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <main class="flex-1 p-4 sm:p-6 lg:p-8">
        <div class="mx-auto max-w-7xl">
          {@inner_content}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :path, :string, required: true
  attr :current, :string, default: nil
  attr :icon, :string, required: true
  slot :inner_block, required: true

  @spec nav_link(map()) :: Phoenix.LiveView.Rendered.t()
  defp nav_link(assigns) do
    active =
      assigns.current &&
        (assigns.current == assigns.path ||
           String.starts_with?(assigns.current, assigns.path <> "/"))

    assigns = assign(assigns, :active, active)

    ~H"""
    <a href={@path} class={[@active && "active"]}>
      <.icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </a>
    """
  end

  @spec initial(String.t() | nil) :: String.t()
  defp initial(nil), do: "?"
  defp initial(""), do: "?"
  defp initial(email), do: email |> String.first() |> String.upcase()

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
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

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
