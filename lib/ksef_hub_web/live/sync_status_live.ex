defmodule KsefHubWeb.SyncStatusLive do
  @moduledoc """
  Shared sync-state tracking for LiveViews that render a KSeF sync trigger.

  The sync button must be disabled whenever a sync is running — whether the
  current user triggered it, another user did, or the hourly dispatcher did.
  This module provides the PubSub subscription, the initial `sync_running`
  assign, and a helper for flipping the flag from received messages.
  """

  import Phoenix.Component, only: [assign: 3]

  alias KsefHub.Sync.History

  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(company_id), do: "sync:status:#{company_id}"

  @doc """
  Subscribes the LiveView to its company's sync topic (only when connected)
  and assigns the current `sync_running` flag based on Oban state.
  """
  @spec mount(Phoenix.LiveView.Socket.t(), Ecto.UUID.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  def mount(socket, nil), do: assign(socket, :sync_running, false)

  def mount(socket, company_id) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(KsefHub.PubSub, topic(company_id))
    end

    assign(socket, :sync_running, History.sync_running?(company_id))
  end

  @doc """
  Updates the `sync_running` assign from a `{:sync_running_changed, bool}`
  PubSub message.
  """
  @spec handle_running_changed(Phoenix.LiveView.Socket.t(), boolean()) ::
          Phoenix.LiveView.Socket.t()
  def handle_running_changed(socket, running?) when is_boolean(running?) do
    assign(socket, :sync_running, running?)
  end
end
