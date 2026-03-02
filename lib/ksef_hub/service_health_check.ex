defmodule KsefHub.ServiceHealthCheck do
  @moduledoc """
  Runs a one-time health check of companion services after application startup.

  Checks pdf-renderer, invoice-extractor, and invoice-classifier, logging the
  results so operators can verify services are reachable in Cloud Run logs.
  """

  use Task, restart: :temporary

  require Logger

  @delay_ms 5_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  @spec run() :: :ok
  def run do
    Process.sleep(@delay_ms)

    services = [
      {:pdf_renderer, &pdf_renderer().health/0},
      {:invoice_extractor, &invoice_extractor().health/0},
      {:invoice_classifier, &invoice_classifier().health/0}
    ]

    results =
      services
      |> Task.async_stream(
        fn {name, check_fn} -> {name, safe_check(check_fn)} end,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _} -> {:unknown, {:error, :timeout}}
      end)

    log_results(results)
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

  @spec log_results([{atom(), :ok | {:error, term()}}]) :: :ok
  defp log_results(results) do
    {healthy, unhealthy} = Enum.split_with(results, fn {_, status} -> status == :ok end)

    for {name, :ok} <- healthy do
      Logger.info("[ServiceHealthCheck] #{name}: OK")
    end

    for {name, {:error, reason}} <- unhealthy do
      Logger.warning("[ServiceHealthCheck] #{name}: FAILED (#{inspect(reason)})")
    end

    if unhealthy == [] do
      Logger.info("[ServiceHealthCheck] All services healthy")
    else
      names = Enum.map_join(unhealthy, ", ", fn {name, _} -> name end)
      Logger.warning("[ServiceHealthCheck] Unhealthy services: #{names}")
    end

    :ok
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
