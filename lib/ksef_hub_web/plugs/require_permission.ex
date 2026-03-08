defmodule KsefHubWeb.Plugs.RequirePermission do
  @moduledoc """
  Plug that checks `Authorization.can?/2` against the current role.

  Returns 403 Forbidden if the user's role does not have the required permission.

  ## Usage

      plug KsefHubWeb.Plugs.RequirePermission, :create_invoice when action in [:create, :upload]
  """

  import Plug.Conn
  import Phoenix.Controller

  alias KsefHub.Authorization

  @doc false
  @spec init(Authorization.permission()) :: Authorization.permission()
  def init(permission), do: permission

  @doc false
  @spec call(Plug.Conn.t(), Authorization.permission()) :: Plug.Conn.t()
  def call(conn, permission) do
    role = conn.assigns[:current_role]

    if role && Authorization.can?(role, permission) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden — insufficient permissions"})
      |> halt()
    end
  end
end
