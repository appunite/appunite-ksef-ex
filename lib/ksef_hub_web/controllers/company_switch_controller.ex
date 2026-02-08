defmodule KsefHubWeb.CompanySwitchController do
  @moduledoc """
  Controller for switching the current company context.
  Stores the selected company_id in the session and redirects back.
  """

  use KsefHubWeb, :controller

  alias KsefHub.Companies

  @doc "Switches the current company context and redirects."
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"id" => id} = params) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %{} <- Companies.get_company(uuid) do
      return_to = params["return_to"] || ~p"/dashboard"

      conn
      |> put_session(:current_company_id, uuid)
      |> redirect(to: return_to)
    else
      _ ->
        conn
        |> put_flash(:error, "Company not found.")
        |> redirect(to: ~p"/dashboard")
    end
  end
end
