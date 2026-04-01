defmodule KsefHubWeb.PaymentRequestCsvController do
  @moduledoc "Controller for downloading payment requests as CSV."

  use KsefHubWeb, :controller

  alias KsefHub.Authorization
  alias KsefHub.Companies
  alias KsefHub.PaymentRequests
  alias KsefHubWeb.AuthHelpers

  plug :check_permission

  @doc "Downloads a CSV file of selected payment requests."
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def download(conn, %{"ids" => ids_param}) do
    company_id = conn.assigns.company_id
    user_id = conn.assigns.current_user.id

    ids =
      ids_param
      |> String.split(",")
      |> Enum.filter(&valid_uuid?/1)

    payment_requests = PaymentRequests.get_payment_requests_by_ids(company_id, ids)

    cond do
      payment_requests == [] ->
        conn
        |> put_flash(:error, "No payment requests found.")
        |> redirect(to: ~p"/c/#{company_id}/payment-requests")

      mixed_currencies?(payment_requests) ->
        conn
        |> put_flash(
          :error,
          "Select payment requests of the same currency for CSV export."
        )
        |> redirect(to: ~p"/c/#{company_id}/payment-requests")

      true ->
        currency = hd(payment_requests).currency
        export_csv(conn, company_id, user_id, payment_requests, currency)
    end
  end

  def download(conn, _params) do
    company_id = conn.assigns.company_id

    conn
    |> put_flash(:error, "No payment requests selected.")
    |> redirect(to: ~p"/c/#{company_id}/payment-requests")
  end

  @spec export_csv(Plug.Conn.t(), Ecto.UUID.t(), Ecto.UUID.t(), [map()], String.t()) ::
          Plug.Conn.t()
  defp export_csv(conn, company_id, user_id, payment_requests, currency) do
    case Companies.get_bank_account_for_currency(company_id, currency) do
      nil ->
        conn
        |> put_flash(
          :error,
          "No bank account configured for #{currency}. Please add one in Settings."
        )
        |> redirect(to: ~p"/c/#{company_id}/payment-requests")

      bank_account ->
        csv = PaymentRequests.build_csv(payment_requests, bank_account.iban)

        PaymentRequests.record_csv_download(
          company_id,
          user_id,
          Enum.map(payment_requests, & &1.id)
        )

        filename = "payment_requests_#{Date.to_iso8601(Date.utc_today())}.csv"

        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, csv)
    end
  end

  @spec valid_uuid?(String.t()) :: boolean()
  defp valid_uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  @spec mixed_currencies?([map()]) :: boolean()
  defp mixed_currencies?([first | rest]) do
    Enum.any?(rest, &(&1.currency != first.currency))
  end

  @spec check_permission(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp check_permission(conn, _opts) do
    company_id = conn.params["company_id"]
    user_id = conn.assigns.current_user.id
    role = AuthHelpers.resolve_role(user_id, company_id)

    if Authorization.can?(role, :view_payment_requests) do
      assign(conn, :company_id, company_id)
    else
      conn
      |> put_flash(:error, "You do not have permission to download payment requests.")
      |> redirect(to: ~p"/c/#{company_id}/payment-requests")
      |> halt()
    end
  end
end
