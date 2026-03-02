defmodule KsefHubWeb.ExportController do
  @moduledoc "Controller for downloading export ZIP files."

  use KsefHubWeb, :controller

  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Companies
  alias KsefHub.Exports

  @doc "Downloads the ZIP file for a completed export batch."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"id" => batch_id}) do
    user_id = conn.assigns.current_user.id

    case get_session(conn, :current_company_id) || Companies.first_company_id_for_user(user_id) do
      nil ->
        conn
        |> put_flash(:error, "Please select a company first.")
        |> redirect(to: ~p"/companies")

      company_id ->
        role = resolve_role(user_id, company_id)

        if role in [:owner, :accountant] do
          do_download(conn, company_id, user_id, batch_id)
        else
          conn
          |> put_flash(:error, "You don't have permission to download exports.")
          |> redirect(to: ~p"/invoices")
        end
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
        |> redirect(to: ~p"/exports")

      _ ->
        conn
        |> put_flash(:error, "Export is not yet ready.")
        |> redirect(to: ~p"/exports")
    end
  rescue
    Ecto.NoResultsError ->
      conn
      |> put_flash(:error, "Export not found.")
      |> redirect(to: ~p"/exports")
  end
end
