defmodule KsefHubWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use KsefHubWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :current_user, :map, default: nil
  attr :current_path, :string, default: nil
  attr :current_company, :map, default: nil
  attr :companies, :list, default: []

  @doc "Renders the main application layout with sidebar navigation."
  @spec app(map()) :: Phoenix.LiveView.Rendered.t()
  def app(assigns) do
    ~H"""
    <div class="drawer lg:drawer-open">
      <input id="sidebar-toggle" type="checkbox" class="drawer-toggle" />

      <div class="drawer-content flex flex-col min-h-screen">
        <!-- Mobile navbar -->
        <div class="navbar bg-base-100 border-b border-base-300 lg:hidden">
          <div class="flex-none">
            <label for="sidebar-toggle" aria-label="Toggle sidebar" class="btn btn-square btn-ghost">
              <.icon name="hero-bars-3" class="size-5" />
            </label>
          </div>
          <div class="flex-1">
            <span class="text-lg font-bold">KSeF Hub</span>
          </div>
        </div>
        
    <!-- Main content -->
        <main class="flex-1 p-4 sm:p-6 lg:p-8">
          <div class="mx-auto max-w-6xl">
            {@inner_content}
          </div>
        </main>
      </div>
      
    <!-- Sidebar -->
      <div class="drawer-side z-40">
        <label for="sidebar-toggle" aria-label="close sidebar" class="drawer-overlay"></label>
        <aside class="bg-base-200 min-h-full w-64 flex flex-col">
          <!-- Logo -->
          <div class="p-4 border-b border-base-300">
            <a href={~p"/dashboard"} class="flex items-center gap-2">
              <.icon name="hero-document-text" class="size-6 text-primary" />
              <span class="text-xl font-bold">KSeF Hub</span>
            </a>
          </div>
          
    <!-- Company Selector -->
          <div :if={@current_company} class="p-4 border-b border-base-300">
            <div class="dropdown w-full">
              <div tabindex="0" role="button" class="btn btn-ghost btn-sm w-full justify-start gap-2">
                <.icon name="hero-building-office-2" class="size-4" />
                <span class="flex-1 text-left truncate">{@current_company.name}</span>
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
                    <input type="hidden" name="return_to" value={@current_path || "/dashboard"} />
                    <button
                      type="submit"
                      class={["w-full text-left", company.id == @current_company.id && "active"]}
                    >
                      <span class="truncate">{company.name}</span>
                      <span class="text-xs text-base-content/50">{company.nip}</span>
                    </button>
                  </form>
                </li>
              </ul>
            </div>
          </div>
    <!-- Navigation -->
          <nav class="flex-1 p-4">
            <ul class="menu gap-1">
              <li>
                <.nav_link path={~p"/dashboard"} current={@current_path} icon="hero-home">
                  Dashboard
                </.nav_link>
              </li>
              <li>
                <.nav_link path={~p"/invoices"} current={@current_path} icon="hero-document-text">
                  Invoices
                </.nav_link>
              </li>
              <li>
                <.nav_link path={~p"/certificates"} current={@current_path} icon="hero-shield-check">
                  Certificates
                </.nav_link>
              </li>
              <li>
                <.nav_link path={~p"/tokens"} current={@current_path} icon="hero-key">
                  API Tokens
                </.nav_link>
              </li>
              <li>
                <.nav_link path={~p"/syncs"} current={@current_path} icon="hero-arrow-path">
                  Syncs
                </.nav_link>
              </li>
              <li>
                <.nav_link path={~p"/companies"} current={@current_path} icon="hero-building-office-2">
                  Companies
                </.nav_link>
              </li>
            </ul>
          </nav>
          
    <!-- Footer: theme toggle + user -->
          <div class="p-4 border-t border-base-300 space-y-3">
            <div class="flex justify-center">
              <.theme_toggle />
            </div>
            <div :if={@current_user} class="flex items-center gap-2 text-sm">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content rounded-full w-8">
                  <span class="text-xs">
                    {initial(@current_user.email)}
                  </span>
                </div>
              </div>
              <div class="flex-1 truncate">
                <p class="font-medium truncate">{@current_user.email}</p>
              </div>
              <.link
                href={~p"/auth/logout"}
                method="delete"
                aria-label="Log out"
                class="btn btn-ghost btn-xs"
              >
                <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
              </.link>
            </div>
          </div>
        </aside>
      </div>
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
