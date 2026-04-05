defmodule KsefHubWeb.LiveHelpers do
  @moduledoc """
  Shared helper functions for LiveView modules.
  """

  @doc """
  Extracts actor options from the socket for activity log tracking.

  Returns a keyword list with `:user_id` and `:actor_label` derived from
  `socket.assigns.current_user`.
  """
  @spec actor_opts(Phoenix.LiveView.Socket.t()) :: keyword()
  def actor_opts(socket) do
    case socket.assigns[:current_user] do
      nil -> []
      user -> [user_id: user.id, actor_label: user.name || user.email]
    end
  end
end
