defmodule KsefHubWeb.SettingsLive.General do
  @moduledoc """
  General settings page with theme toggle.
  """
  use KsefHubWeb, :live_view

  import KsefHubWeb.Layouts, only: [theme_toggle: 1]
  import KsefHubWeb.SettingsComponents, only: [settings_layout: 1]

  @doc "Mounts the General settings page."
  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings")}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <.settings_layout
      current_path={@current_path}
      current_company={@current_company}
      current_role={@current_role}
    >
      <.header>
        General
        <:subtitle>Application preferences</:subtitle>
      </.header>

      <div class="mt-6 space-y-6 max-w-md">
        <div>
          <label class="text-sm font-medium">Theme</label>
          <p class="text-sm text-muted-foreground mb-3">Choose your preferred color scheme</p>
          <.theme_toggle />
        </div>
      </div>
    </.settings_layout>
    """
  end
end
