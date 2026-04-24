defmodule KsefHubWeb.TrainingCsvController do
  @moduledoc "Controller for downloading training CSV files with extended invoice data."

  use KsefHubWeb, :controller

  import KsefHubWeb.AuthHelpers, only: [resolve_role: 2]
  import KsefHubWeb.FilenameHelpers, only: [send_attachment: 4]

  alias KsefHub.Authorization
  alias KsefHub.Exports

  @doc "Downloads an extended CSV of invoices for ML training."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"company_id" => company_id, "date_from" => from, "date_to" => to}) do
    user_id = conn.assigns.current_user.id
    role = resolve_role(user_id, company_id)

    if Authorization.can?(role, :manage_services) do
      do_download(conn, company_id, from, to)
    else
      conn
      |> put_flash(:error, "You don't have permission to export training data.")
      |> redirect(to: ~p"/c/#{company_id}/settings/services")
    end
  end

  def download(conn, %{"company_id" => company_id}) do
    conn
    |> put_flash(:error, "Date range is required.")
    |> redirect(to: ~p"/c/#{company_id}/settings/services")
  end

  @spec do_download(Plug.Conn.t(), String.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp do_download(conn, company_id, date_from_str, date_to_str) do
    with {:ok, date_from} <- Date.from_iso8601(date_from_str),
         {:ok, date_to} <- Date.from_iso8601(date_to_str),
         :ok <- validate_date_order(date_from, date_to) do
      invoices = Exports.list_training_invoices(company_id, date_from, date_to)
      csv_binary = Exports.build_training_csv(invoices, extended: true)
      filename = "training_#{date_from}_#{date_to}.csv"
      send_attachment(conn, "text/csv", filename, csv_binary)
    else
      _ ->
        conn
        |> put_flash(:error, "Invalid date range.")
        |> redirect(to: ~p"/c/#{company_id}/settings/services")
    end
  end

  @spec validate_date_order(Date.t(), Date.t()) :: :ok | :error
  defp validate_date_order(from, to) do
    if Date.compare(to, from) != :lt, do: :ok, else: :error
  end
end
