defmodule KsefHubWeb.HealthController do
  @moduledoc """
  Minimal health check endpoint for Cloud Run probes.
  """

  use KsefHubWeb, :controller

  @doc """
  Returns 200 OK with a JSON status payload.

  Used by Cloud Run startup and liveness probes.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok"}))
  end
end
