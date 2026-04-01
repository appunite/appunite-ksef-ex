defmodule KsefHubWeb.PaymentRequestCsvController do
  @moduledoc "Controller for downloading payment requests as CSV."

  use KsefHubWeb, :controller

  require Logger

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

    raw_ids = ids_param |> String.split(",") |> Enum.reject(&(&1 == ""))
    ids = Enum.filter(raw_ids, &valid_uuid?/1)

    if length(ids) != length(raw_ids) do
      conn
      |> put_flash(:error, "Some payment request IDs are invalid.")
      |> redirect(to: ~p"/c/#{company_id}/payment-requests")
    else
      payment_requests = PaymentRequests.get_payment_requests_by_ids(company_id, ids)
      found_ids = MapSet.new(payment_requests, & &1.id)
      requested_ids = MapSet.new(ids)

      cond do
        MapSet.size(found_ids) != MapSet.size(requested_ids) ->
          conn
          |> put_flash(:error, "Some payment request IDs were not found.")
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
        pr_ids = Enum.map(payment_requests, & &1.id)

        case PaymentRequests.record_csv_download(company_id, user_id, pr_ids) do
          {:ok, _record} ->
            filename = "payment_requests_#{Date.to_iso8601(Date.utc_today())}.csv"

            conn
            |> put_resp_content_type("text/csv")
            |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
            |> send_resp(200, csv)

          {:error, reason} ->
            Logger.error(
              "Failed to record CSV download for company=#{company_id} user=#{user_id}: #{inspect(reason)}"
            )

            conn
            |> put_flash(:error, "Failed to process CSV download. Please try again.")
            |> redirect(to: ~p"/c/#{company_id}/payment-requests")
        end
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
