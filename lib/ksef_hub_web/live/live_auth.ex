defmodule KsefHubWeb.LiveAuth do
  @moduledoc """
  LiveView on_mount hook that loads the current user into socket assigns.
  Redirects unauthenticated users to the home page.
  """

  import Phoenix.LiveView
  import Phoenix.Component

  alias KsefHub.Accounts

  @doc """
  Assigns `:current_user` to the socket from the session's `user_id`.
  Redirects to `/` if the user is not found or session is missing.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, redirect(socket, to: "/")}

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            {:halt, redirect(socket, to: "/")}

          user ->
            {:cont, assign(socket, :current_user, user)}
        end
    end
  end
end
