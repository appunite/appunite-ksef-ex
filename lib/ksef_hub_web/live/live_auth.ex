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
  Validates the session value as a UUID before querying.
  Redirects to `/` with an error flash if the user is not found or session is missing.
  """
  @spec on_mount(atom(), map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, session, socket) do
    with raw_id when is_binary(raw_id) <- session["user_id"],
         {:ok, _} <- Ecto.UUID.cast(raw_id),
         %{} = user <- Accounts.get_user(raw_id) do
      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:current_path, nil)
        |> attach_hook(:set_current_path, :handle_params, fn _params, uri, socket ->
          path = URI.parse(uri).path
          {:cont, assign(socket, :current_path, path)}
        end)

      {:cont, socket}
    else
      _ ->
        socket =
          socket
          |> put_flash(:error, "You must be logged in to access this page.")
          |> redirect(to: "/")

        {:halt, socket}
    end
  end
end
