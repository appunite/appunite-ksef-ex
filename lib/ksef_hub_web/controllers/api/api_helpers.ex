defmodule KsefHubWeb.Api.ApiHelpers do
  @moduledoc """
  Shared helper functions for API controllers.
  """

  @doc """
  Extracts actor options from the conn for activity log tracking.

  Returns a keyword list with `:user_id`, `:actor_type`, and `:actor_label`
  derived from `conn.assigns.api_token`.
  """
  @spec api_actor_opts(Plug.Conn.t()) :: keyword()
  def api_actor_opts(conn) do
    token = conn.assigns.api_token
    [user_id: token.created_by_id, actor_type: :api, actor_label: "API: #{token.name}"]
  end
end
