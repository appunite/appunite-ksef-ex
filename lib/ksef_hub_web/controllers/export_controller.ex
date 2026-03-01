defmodule KsefHubWeb.ExportController do
  @moduledoc "Controller for downloading export ZIP files."

  use KsefHubWeb, :controller

  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Exports

  @doc "Downloads the ZIP file for a completed export batch."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"id" => batch_id}) do
    company_id = conn.assigns.current_company.id
    batch = Exports.get_batch_with_file!(company_id, batch_id)

    case batch do
      %{status: :completed, zip_file: %{content: content}} when is_binary(content) ->
        filename = "invoices_#{batch.date_from}_#{batch.date_to}.zip"
        send_attachment(conn, "application/zip", filename, content)

      %{status: :completed} ->
        conn
        |> put_flash(:error, "Export file not found.")
        |> redirect(to: ~p"/exports")

      _ ->
        conn
        |> put_flash(:error, "Export is not yet ready.")
        |> redirect(to: ~p"/exports")
    end
  end
end
