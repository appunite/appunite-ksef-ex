defmodule KsefHub.ServiceHealthCheck do
  @moduledoc """
  Runs a one-time health check of companion services after application startup.

  Checks pdf-renderer, invoice-extractor, and invoice-classifier, logging the
  results so operators can verify services are reachable in Cloud Run logs.
  """

  use Task, restart: :temporary

  require Logger

  alias KsefHub.ServiceHealth

  @delay_ms 5_000

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  @spec run() :: :ok
  def run do
    Process.sleep(@delay_ms)

    ServiceHealth.check_all()
    |> log_results()
  end

  @spec log_results(ServiceHealth.results()) :: :ok
  defp log_results(results) do
    {healthy, unhealthy} = Enum.split_with(results, fn {_, status} -> status == :ok end)

    for {name, :ok} <- healthy do
      Logger.info("[ServiceHealthCheck] #{name}: OK")
    end

    for {name, {:error, reason}} <- unhealthy do
      Logger.warning("[ServiceHealthCheck] #{name}: FAILED (#{sanitize_reason(reason)})")
    end

    if unhealthy == [] do
      Logger.info("[ServiceHealthCheck] All services healthy")
    else
      names = Enum.map_join(unhealthy, ", ", fn {name, _} -> name end)
      Logger.warning("[ServiceHealthCheck] Unhealthy services: #{names}")
    end

    :ok
  end

  @spec sanitize_reason(term()) :: String.t()
  defp sanitize_reason(:timeout), do: "timeout"
  defp sanitize_reason(:econnrefused), do: "connection_refused"
  defp sanitize_reason(:nxdomain), do: "dns_not_found"
  defp sanitize_reason({:ssl, _}), do: "ssl_error"

  defp sanitize_reason({tag, status})
       when tag in [:pdf_renderer_error, :extractor_error, :classifier_error] and
              is_integer(status),
       do: "http_#{status}"

  defp sanitize_reason({:request_failed, inner}), do: "request_failed:#{sanitize_reason(inner)}"
  defp sanitize_reason(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp sanitize_reason(msg) when is_binary(msg), do: "error"
  defp sanitize_reason(_), do: "unknown_error"
end
