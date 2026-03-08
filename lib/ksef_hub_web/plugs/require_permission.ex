defmodule KsefHubWeb.Plugs.RequirePermission do
  @moduledoc """
  API-only plug that checks `Authorization.can?/2` against the current role.

  Returns a JSON 403 Forbidden response if `conn.assigns[:current_role]` is nil or
  lacks the required permission. Intended for use in API controller pipelines — not
  browser/HTML pipelines (which expect redirects, not JSON error bodies).

  Callers must ensure `:current_role` is set on the connection (e.g., via API token
  authentication) before this plug runs. A nil role is treated as unauthorized.

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
