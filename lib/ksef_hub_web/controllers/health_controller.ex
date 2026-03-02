defmodule KsefHubWeb.HealthController do
  @moduledoc """
  Health check endpoints for Cloud Run probes and service verification.
  """

  use KsefHubWeb, :controller

  require Logger

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
  """
  @spec services(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def services(conn, _params) do
    checks = [
      {:pdf_renderer, &pdf_renderer().health/0},
      {:invoice_extractor, &invoice_extractor().health/0},
      {:invoice_classifier, &invoice_classifier().health/0}
    ]

    results =
      checks
      |> Task.async_stream(
        fn {name, check_fn} ->
          {name, safe_check(check_fn)}
        end,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {:unknown, {:error, :timeout}}
      end)
      |> Map.new()

    all_ok = Enum.all?(results, fn {_name, status} -> status == :ok end)
    status_code = if all_ok, do: 200, else: 503

    body =
      results
      |> Enum.map(fn
        {name, :ok} -> {name, "ok"}
        {name, {:error, reason}} -> {name, inspect(reason)}
      end)
      |> Map.new()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(body))
  end

  @spec safe_check((-> {:ok, map()} | {:error, term()})) :: :ok | {:error, term()}
  defp safe_check(check_fn) do
    case check_fn.() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @spec pdf_renderer() :: module()
  defp pdf_renderer,
    do: Application.get_env(:ksef_hub, :pdf_renderer, KsefHub.PdfRenderer.Client)

  @spec invoice_extractor() :: module()
  defp invoice_extractor,
    do: Application.get_env(:ksef_hub, :invoice_extractor, KsefHub.InvoiceExtractor.Client)

  @spec invoice_classifier() :: module()
  defp invoice_classifier,
    do: Application.get_env(:ksef_hub, :invoice_classifier, KsefHub.InvoiceClassifier.Client)
end
