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

  @doc "Sends a file download response with sanitized filename and Content-Disposition: attachment header."
  @spec send_attachment(Plug.Conn.t(), String.t(), String.t(), binary()) :: Plug.Conn.t()
  def send_attachment(conn, content_type, filename, body) do
    send_file_resp(conn, content_type, filename, body, "attachment")
  end

  @doc "Sends a file response with Content-Disposition: inline for in-browser rendering (e.g. iframe preview)."
  @spec send_inline(Plug.Conn.t(), String.t(), String.t(), binary()) :: Plug.Conn.t()
  def send_inline(conn, content_type, filename, body) do
    send_file_resp(conn, content_type, filename, body, "inline")
  end

  @spec send_file_resp(Plug.Conn.t(), String.t(), String.t(), binary(), String.t()) ::
          Plug.Conn.t()
  defp send_file_resp(conn, content_type, filename, body, disposition) do
    safe_filename = sanitize_filename(filename)

    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("content-disposition", ~s(#{disposition}; filename="#{safe_filename}"))
    |> send_resp(200, body)
  end
end
