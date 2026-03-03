defmodule KsefHubWeb.ExportController do
  @moduledoc "Controller for downloading export ZIP files."

  use KsefHubWeb, :controller

  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Exports

  @doc "Downloads the ZIP file for a completed export batch."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"company_id" => company_id, "id" => batch_id}) do
    with {:ok, _} <- Ecto.UUID.cast(company_id) do
      user_id = conn.assigns.current_user.id
      role = resolve_role(user_id, company_id)

      if role in [:owner, :accountant] do
        do_download(conn, company_id, user_id, batch_id)
      else
        conn
        |> put_flash(:error, "You don't have permission to download exports.")
        |> redirect(to: ~p"/c/#{company_id}/invoices")
      end
    else
      :error ->
        conn
        |> put_flash(:error, "Not found.")
        |> redirect(to: ~p"/companies")
    end
  end

  @spec do_download(Plug.Conn.t(), Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: Plug.Conn.t()
  defp do_download(conn, company_id, user_id, batch_id) do
    batch = Exports.get_batch_with_file!(company_id, user_id, batch_id)

    case batch do
      %{status: :completed, zip_file: %{content: content}} when is_binary(content) ->
        filename = "invoices_#{batch.date_from}_#{batch.date_to}.zip"
        send_attachment(conn, "application/zip", filename, content)

      %{status: :completed} ->
        conn
        |> put_flash(:error, "Export file not found.")
        |> redirect(to: ~p"/c/#{company_id}/exports")

      _ ->
        conn
        |> put_flash(:error, "Export is not yet ready.")
        |> redirect(to: ~p"/c/#{company_id}/exports")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Export not found.")
      |> redirect(to: ~p"/c/#{company_id}/exports")
  end
end
