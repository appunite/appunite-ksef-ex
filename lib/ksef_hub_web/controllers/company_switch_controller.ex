defmodule KsefHubWeb.CompanySwitchController do
  @moduledoc """
  Controller for switching the current company context.
  Verifies the user has a membership for the target company,
  stores the selected company_id in the session, and redirects back.
  """

  use KsefHubWeb, :controller

  alias KsefHub.Companies

  @doc "Switches the current company context and redirects."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    user_id = get_session(conn, :user_id)

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} <- Companies.get_membership(user_id, uuid) do
      conn
      |> put_session(:current_company_id, uuid)
      |> redirect(to: safe_return_to(params["return_to"]))
    else
      _ ->
        conn
        |> put_flash(:error, "Company not found.")
        |> redirect(to: ~p"/dashboard")
    end
  end

  @spec safe_return_to(String.t() | nil) :: String.t()
  defp safe_return_to(nil), do: ~p"/dashboard"

  defp safe_return_to(path) do
    uri = URI.parse(path)

    if uri.host == nil && uri.scheme == nil && String.starts_with?(path, "/") &&
         !String.starts_with?(path, "//") do
      path
    else
      ~p"/dashboard"
    end
  end
end
