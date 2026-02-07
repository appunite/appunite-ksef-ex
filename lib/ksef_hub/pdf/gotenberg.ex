defmodule KsefHub.Pdf.Gotenberg do
  @moduledoc """
  HTTP client for Gotenberg — converts HTML to PDF via the Chromium route.
  """

  require Logger

  @doc """
  Converts HTML content to PDF via Gotenberg's Chromium endpoint.
  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  @spec convert(String.t()) :: {:ok, binary()} | {:error, term()}
  def convert(html_content) when is_binary(html_content) do
    case gotenberg_url() do
      nil ->
        {:error, :gotenberg_not_configured}

      base_url ->
        url = "#{base_url}/forms/chromium/convert/html"

        case Req.post(url,
               form_multipart: [
                 {"files", html_content, filename: "index.html", content_type: "text/html"}
               ],
               receive_timeout: 30_000
             ) do
          {:ok, %{status: 200, body: body}} ->
            {:ok, body}

          {:ok, %{status: status, body: body}} ->
            Logger.error("Gotenberg returned #{status} (body: #{safe_size(body)} bytes)")
            {:error, {:gotenberg_error, status}}

          {:error, reason} ->
            Logger.error("Gotenberg request failed: #{inspect(reason)}")
            {:error, {:request_failed, reason}}
        end
    end
  end

  defp gotenberg_url do
    Application.get_env(:ksef_hub, :gotenberg_url)
  end

  defp safe_size(val) when is_binary(val), do: byte_size(val)

  defp safe_size(val) when is_list(val) do
    :erlang.iolist_size(val)
  rescue
    ArgumentError -> val |> inspect() |> byte_size()
  end

  defp safe_size(val), do: val |> inspect() |> byte_size()
end
