defmodule KsefHub.PdfRenderer.Client do
  @moduledoc """
  HTTP client for the ksef-pdf microservice (ghcr.io/appunite/ksef-pdf).
  Generates PDF and HTML from FA(3) XML via the sidecar service.
  """

  @behaviour KsefHub.PdfRenderer.Behaviour

  require Logger

  @receive_timeout 30_000

  @doc """
  Generates a PDF from FA(3) XML via the ksef-pdf microservice.
  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  @spec generate_pdf(String.t()) :: {:ok, binary()} | {:error, term()}
  @spec generate_pdf(String.t(), map()) :: {:ok, binary()} | {:error, term()}
  @impl true
  def generate_pdf(xml_content, metadata \\ %{}) when is_binary(xml_content) do
    post("/generate/pdf", xml_content, metadata)
  end

  @doc """
  Generates HTML from FA(3) XML via the ksef-pdf microservice.
  Returns `{:ok, html_string}` or `{:error, reason}`.
  """
  @spec generate_html(String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec generate_html(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  @impl true
  def generate_html(xml_content, metadata \\ %{}) when is_binary(xml_content) do
    post("/generate/html", xml_content, metadata)
  end

  @spec post(String.t(), String.t(), map()) :: {:ok, binary()} | {:error, term()}
  defp post(path, xml_content, metadata) do
    with {:ok, base_url} <- fetch_url() do
      do_request(base_url, path, xml_content, metadata)
    end
  end

  @spec fetch_url() :: {:ok, String.t()} | {:error, :pdf_renderer_not_configured}
  defp fetch_url do
    case Application.get_env(:ksef_hub, :pdf_renderer_url) do
      url when is_binary(url) and url != "" -> {:ok, url}
      _ -> {:error, :pdf_renderer_not_configured}
    end
  end

  @spec do_request(String.t(), String.t(), String.t(), map()) ::
          {:ok, binary()} | {:error, term()}
  defp do_request(base_url, path, xml_content, metadata) do
    url = "#{base_url}#{path}"
    headers = build_headers(metadata)

    case Req.post(url, body: xml_content, headers: headers, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("ksef-pdf returned #{status} (body: #{safe_size(body)} bytes)")
        {:error, {:pdf_renderer_error, status}}

      {:error, reason} ->
        Logger.error("ksef-pdf request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  @spec build_headers(map()) :: [{String.t(), String.t()}]
  defp build_headers(metadata) do
    [{"content-type", "application/xml"}]
    |> maybe_add_header("x-ksef-number", Map.get(metadata, :ksef_number))
    |> maybe_add_header("x-ksef-qrcode", Map.get(metadata, :ksef_qrcode))
  end

  @spec maybe_add_header([{String.t(), String.t()}], String.t(), term()) ::
          [{String.t(), String.t()}]
  defp maybe_add_header(headers, _name, nil), do: headers
  defp maybe_add_header(headers, name, value), do: [{name, to_string(value)} | headers]

  @spec safe_size(term()) :: non_neg_integer()
  defp safe_size(val) when is_binary(val), do: byte_size(val)

  defp safe_size(val) when is_list(val) do
    :erlang.iolist_size(val)
  rescue
    ArgumentError -> val |> inspect() |> byte_size()
  end

  defp safe_size(val), do: val |> inspect() |> byte_size()
end
