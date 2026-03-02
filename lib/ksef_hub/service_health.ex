defmodule KsefHub.ServiceHealth do
  @moduledoc """
  Shared health-check logic for companion services.

  Used by both the startup health check task and the `/healthz/services` endpoint.
  """

  @type check_result :: :ok | {:error, term()}
  @type results :: [{atom(), check_result()}]

  @doc """
  Checks all companion services in parallel and returns results as a keyword list.

  Each check has a 10-second timeout. Timed-out services report `{:error, :timeout}`.
  """
  @spec check_all() :: results()
  def check_all do
    services = [
      {:pdf_renderer, &pdf_renderer().health/0},
      {:invoice_extractor, &invoice_extractor().health/0},
      {:invoice_classifier, &invoice_classifier().health/0}
    ]

    services
    |> Enum.map(fn {name, check_fn} ->
      {name, Task.async(fn -> safe_check(check_fn) end)}
    end)
    |> Enum.map(fn {name, task} ->
      case Task.yield(task, 10_000) || Task.shutdown(task) do
        {:ok, result} -> {name, result}
        nil -> {name, {:error, :timeout}}
      end
    end)
  end

  @spec safe_check((-> {:ok, map()} | {:error, term()})) :: check_result()
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
