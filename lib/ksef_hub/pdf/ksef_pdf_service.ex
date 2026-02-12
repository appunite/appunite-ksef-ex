defmodule KsefHub.Pdf.KsefPdfService do
  @moduledoc """
  HTTP client for the ksef-pdf microservice (ghcr.io/appunite/ksef-pdf).
  Generates PDF and HTML from FA(3) XML via the sidecar service.
  """

  require Logger

  @receive_timeout 30_000

  @doc """
  Generates a PDF from FA(3) XML via the ksef-pdf microservice.
  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  @spec generate_pdf(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  def generate_pdf(xml_content, metadata \\ %{}) when is_binary(xml_content) do
    post("/generate/pdf", xml_content, metadata)
  end

  @doc """
  Generates HTML from FA(3) XML via the ksef-pdf microservice.
  Returns `{:ok, html_string}` or `{:error, reason}`.
  """
  @spec generate_html(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def generate_html(xml_content, metadata \\ %{}) when is_binary(xml_content) do
    post("/generate/html", xml_content, metadata)
  end

  @spec post(String.t(), String.t(), map()) :: {:ok, binary()} | {:error, term()}
  defp post(path, xml_content, metadata) do
    case ksef_pdf_url() do
      nil ->
        {:error, :ksef_pdf_not_configured}

      base_url ->
        url = "#{base_url}#{path}"
        headers = build_headers(metadata)

        case Req.post(url,
               body: xml_content,
               headers: headers,
               receive_timeout: @receive_timeout
             ) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status: status, body: body}} ->
            Logger.error("ksef-pdf returned #{status} (body: #{safe_size(body)} bytes)")
            {:error, {:ksef_pdf_error, status}}

          {:error, reason} ->
            Logger.error("ksef-pdf request failed: #{inspect(reason)}")
            {:error, {:request_failed, reason}}
        end
    end
  end

  @spec build_headers(map()) :: [{String.t(), String.t()}]
  defp build_headers(metadata) do
    headers = [{"content-type", "application/xml"}]

    headers =
      case metadata[:ksef_number] do
        nil -> headers
        number -> [{"x-ksef-number", number} | headers]
      end

    case metadata[:ksef_qrcode] do
      nil -> headers
      qrcode -> [{"x-ksef-qrcode", qrcode} | headers]
    end
  end

  @spec ksef_pdf_url() :: String.t() | nil
  defp ksef_pdf_url do
    Application.get_env(:ksef_hub, :ksef_pdf_url)
  end

  @spec safe_size(term()) :: non_neg_integer()
  defp safe_size(val) when is_binary(val), do: byte_size(val)

  defp safe_size(val) when is_list(val) do
    :erlang.iolist_size(val)
  rescue
    ArgumentError -> val |> inspect() |> byte_size()
  end

  defp safe_size(val), do: val |> inspect() |> byte_size()
end
