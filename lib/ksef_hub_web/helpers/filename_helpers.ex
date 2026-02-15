defmodule KsefHubWeb.FilenameHelpers do
  @moduledoc "Shared filename and download utilities for file responses."

  import Plug.Conn

  @doc "Sanitizes a filename for safe use in Content-Disposition headers."
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(name) do
    sanitized =
      name
      |> String.replace(~r/[^\w\.\-]/u, "_")
      |> String.slice(0, 200)

    if sanitized == "", do: "download", else: sanitized
  end

  @doc "Sends a file download response with sanitized filename and Content-Disposition header."
  @spec send_attachment(Plug.Conn.t(), String.t(), String.t(), binary()) :: Plug.Conn.t()
  def send_attachment(conn, content_type, filename, body) do
    safe_filename = sanitize_filename(filename)

    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{safe_filename}"))
    |> send_resp(200, body)
  end
end
