defmodule KsefHub.InvoiceExtractor.Client do
  @moduledoc """
  HTTP client for the au-ksef-unstructured PDF extraction sidecar.

  Sends PDF files via multipart upload to the extraction service and returns
  structured invoice data.
  """

  @behaviour KsefHub.InvoiceExtractor.Behaviour

  require Logger

  @receive_timeout 120_000

  @doc "Extracts structured invoice data from a PDF binary."
  @spec extract(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  @impl true
  def extract(pdf_binary, opts) when is_binary(pdf_binary) do
    with {:ok, base_url} <- fetch_url(),
         {:ok, token} <- fetch_token() do
      filename = opts |> Keyword.get(:filename, "invoice.pdf") |> sanitize_filename()
      context = Keyword.get(opts, :context)
      do_extract(base_url, token, pdf_binary, filename, context)
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
          {:error, {:extractor_error, status}}

        {:error, reason} ->
          {:error, {:request_failed, reason}}
      end
    end
  end

  @spec do_extract(String.t(), String.t(), binary(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  defp do_extract(base_url, token, pdf_binary, filename, context) do
    case base_url
         |> build_req()
         |> Req.post(
           url: "/extract",
           form_multipart: build_form_parts(pdf_binary, filename, context),
           headers: [{"authorization", "Bearer #{token}"}]
         ) do
      {:ok, %{status: 200, body: %{"success" => true, "data" => data}}} when is_map(data) ->
        {:ok, data}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        Logger.error("Invoice extractor returned #{status} for /extract")

        {:error, {:extractor_error, status}}

      {:error, %{__struct__: struct_name} = reason} ->
        Logger.error("Invoice extractor request failed for /extract: #{inspect(struct_name)}")
        {:error, {:request_failed, reason}}

      {:error, reason} ->
        Logger.error("Invoice extractor request failed for /extract")
        {:error, {:request_failed, reason}}
    end
  end

  @spec build_form_parts(binary(), String.t(), String.t() | nil) :: keyword()
  defp build_form_parts(pdf_binary, filename, nil) do
    [file: {pdf_binary, filename: filename, content_type: "application/pdf"}]
  end

  defp build_form_parts(pdf_binary, filename, context) do
    [
      file: {pdf_binary, filename: filename, content_type: "application/pdf"},
      context: context
    ]
  end

  @spec build_req(String.t()) :: Req.Request.t()
  defp build_req(base_url) do
    [base_url: base_url, receive_timeout: @receive_timeout]
    |> Keyword.merge(Application.get_env(:ksef_hub, :invoice_extractor_req_options, []))
    |> Req.new()
  end

  @spec fetch_url() :: {:ok, String.t()} | {:error, :extractor_not_configured}
  defp fetch_url do
    case Application.get_env(:ksef_hub, :invoice_extractor_url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, :extractor_not_configured}
    end
  end

  @spec fetch_token() :: {:ok, String.t()} | {:error, :extractor_token_not_configured}
  defp fetch_token do
    case Application.get_env(:ksef_hub, :invoice_extractor_api_token) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :extractor_token_not_configured}
    end
  end

  @spec sanitize_filename(String.t()) :: String.t()
  defp sanitize_filename(filename) do
    Regex.replace(~r/[\r\n\x00-\x1f]/, filename, "_")
  end
end
