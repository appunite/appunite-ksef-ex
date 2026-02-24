defmodule KsefHub.Unstructured.Client do
  @moduledoc """
  HTTP client for the au-ksef-unstructured PDF extraction sidecar.

  Sends PDF files via multipart upload to the extraction service and returns
  structured invoice data. Follows the same pattern as `KsefHub.Predictions.PredictionService`.
  """

  @behaviour KsefHub.Unstructured.Behaviour

  require Logger

  @receive_timeout 120_000

  @doc "Extracts structured invoice data from a PDF binary."
  @spec extract(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  @impl true
  def extract(pdf_binary, opts) when is_binary(pdf_binary) do
    with {:ok, base_url} <- fetch_url(),
         {:ok, token} <- fetch_token() do
      filename = opts |> Keyword.get(:filename, "invoice.pdf") |> sanitize_filename()
      do_extract(base_url, token, pdf_binary, filename)
    end
  end

  def extract(_pdf_binary, _opts), do: {:error, :invalid_pdf}

  @doc "Checks the health of the extraction service."
  @spec health() :: {:ok, map()} | {:error, term()}
  @impl true
  def health do
    with {:ok, base_url} <- fetch_url() do
      case base_url |> build_req() |> Req.get(url: "/health") do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} ->
          {:error, {:invalid_payload, body}}

        {:ok, %{status: status}} ->
          {:error, {:unstructured_service_error, status}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @spec do_extract(String.t(), String.t(), binary(), String.t()) ::
          {:ok, map()} | {:error, term()}
  defp do_extract(base_url, token, pdf_binary, filename) do
    case base_url
         |> build_req()
         |> Req.post(
           url: "/extract",
           form_multipart: [
             file: {pdf_binary, filename: filename, content_type: "application/pdf"}
           ],
           headers: [{"authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.error("Unstructured service returned #{status} for /extract")

        {:error, {:unstructured_service_error, status}}

      {:error, %{__struct__: struct_name} = reason} ->
        Logger.error("Unstructured service request failed for /extract: #{inspect(struct_name)}")
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        Logger.error("Unstructured service request failed for /extract")
        {:error, {:request_failed, reason}}
    end
  end

  @spec build_req(String.t()) :: Req.Request.t()
  defp build_req(base_url) do
    options = [base_url: base_url, receive_timeout: @receive_timeout]

    case Application.get_env(:ksef_hub, :unstructured_req_options) do
      nil -> Req.new(options)
      extra -> Req.new(Keyword.merge(options, extra))
    end
  end

  @spec fetch_url() :: {:ok, String.t()} | {:error, :unstructured_service_not_configured}
  defp fetch_url do
    case Application.get_env(:ksef_hub, :unstructured_url) do
      nil -> {:error, :unstructured_service_not_configured}
      url -> {:ok, url}
    end
  end

  @spec fetch_token() :: {:ok, String.t()} | {:error, :unstructured_token_not_configured}
  defp fetch_token do
    case Application.get_env(:ksef_hub, :unstructured_api_token) do
      nil -> {:error, :unstructured_token_not_configured}
      token -> {:ok, token}
    end
  end

  @spec sanitize_filename(String.t()) :: String.t()
  defp sanitize_filename(filename) do
    Regex.replace(~r/[\r\n\x00-\x1f]/, filename, "_")
  end
end
