defmodule KsefHubWeb.HealthController do
  @moduledoc """
  Health check endpoints for Cloud Run probes and service verification.
  """

  use KsefHubWeb, :controller

  require Logger

  alias KsefHub.ServiceHealth

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

  @doc """
  Checks all companion services (pdf-renderer, invoice-extractor, invoice-classifier)
  in parallel and returns their status.

  Returns 200 if all services are healthy, 503 if any service is unhealthy.
  Error details are logged internally but not exposed in the response.
  """
  @spec services(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def services(conn, _params) do
    results = ServiceHealth.check_all()

    for {name, {:error, reason}} <- results do
      Logger.warning("[HealthCheck] #{name}: #{inspect(reason)}")
    end

    all_ok = Enum.all?(results, fn {_name, status} -> status == :ok end)
    status_code = if all_ok, do: 200, else: 503

    body =
      results
      |> Enum.map(fn
        {name, :ok} -> {name, "ok"}
        {name, {:error, _}} -> {name, "unhealthy"}
      end)
      |> Map.new()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(body))
  end
end
