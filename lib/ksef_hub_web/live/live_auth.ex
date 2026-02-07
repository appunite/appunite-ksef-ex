defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads current_user from session.
  Same logic as RequireAuth plug but for LiveView lifecycle.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias KsefHub.Accounts

  def on_mount(:require_auth, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/")}

      user_id ->
        try do
          user = Accounts.get_user!(user_id)
          {:cont, assign(socket, :current_user, user)}
        rescue
          Ecto.NoResultsError ->
            {:halt, redirect(socket, to: "/")}
        end
    end
  end
end
