defmodule KsefHubWeb.PaymentRequestCsvController do
  @moduledoc "Controller for downloading payment requests as CSV."

  use KsefHubWeb, :controller

  alias KsefHub.PaymentRequests

  @doc "Downloads a CSV file of selected payment requests."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"ids" => ids_param} = _params) do
    company_id = conn.assigns.current_company.id
    user_id = conn.assigns.current_user.id
    ids = ids_param |> String.split(",") |> Enum.reject(&(&1 == ""))

    payment_requests = PaymentRequests.get_payment_requests_by_ids(company_id, ids)

    if payment_requests == [] do
      conn
      |> put_flash(:error, "No payment requests found.")
      |> redirect(to: ~p"/c/#{company_id}/payment-requests")
    else
      csv = PaymentRequests.build_csv(payment_requests)
      PaymentRequests.record_csv_download(company_id, user_id, ids)

      filename = "payment_requests_#{Date.to_iso8601(Date.utc_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_resp(200, csv)
    end
  end

  def download(conn, _params) do
    company_id = conn.assigns.current_company.id

    conn
    |> put_flash(:error, "No payment requests selected.")
    |> redirect(to: ~p"/c/#{company_id}/payment-requests")
  end
end
