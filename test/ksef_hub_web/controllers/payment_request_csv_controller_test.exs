defmodule KsefHubWeb.PaymentRequestCsvControllerTest do
  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-csv-owner",
        email: "csv-owner@example.com",
        name: "CSV Owner"
      })

    company = insert(:company, name: "CSV Corp")
    insert(:membership, user: user, company: company, role: :owner)
    insert(:company_bank_account, company: company, currency: "PLN")
    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "download" do
    test "downloads CSV for selected payment requests", %{
      conn: conn,
      company: company,
      user: user
    } do
      pr = insert(:payment_request, company: company, created_by: user, recipient_name: "Test Co")
      conn = get(conn, ~p"/c/#{company.id}/payment-requests/csv?ids=#{pr.id}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
      assert conn.resp_body =~ "Test Co"
      assert conn.resp_body =~ "kwota"
    end

    test "redirects with flash when no IDs provided", %{conn: conn, company: company} do
      conn = get(conn, ~p"/c/#{company.id}/payment-requests/csv")
      assert redirected_to(conn) =~ "/payment-requests"
    end

    test "redirects with flash when no payment requests found", %{conn: conn, company: company} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/c/#{company.id}/payment-requests/csv?ids=#{fake_id}")
      assert redirected_to(conn) =~ "/payment-requests"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not found"
    end

    test "redirects with error when IDs contain invalid UUIDs", %{conn: conn, company: company} do
      conn = get(conn, ~p"/c/#{company.id}/payment-requests/csv?ids=not-a-uuid")
      assert redirected_to(conn) =~ "/payment-requests"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid"
    end

    test "redirects with error when no bank account for currency", %{
      conn: conn,
      company: company,
      user: user
    } do
      pr =
        insert(:payment_request,
          company: company,
          created_by: user,
          currency: "EUR"
        )

      conn = get(conn, ~p"/c/#{company.id}/payment-requests/csv?ids=#{pr.id}")
      assert redirected_to(conn) =~ "/payment-requests"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No bank account configured"
    end

    test "redirects with error when mixed currencies", %{
      conn: conn,
      company: company,
      user: user
    } do
      pr1 = insert(:payment_request, company: company, created_by: user, currency: "PLN")
      pr2 = insert(:payment_request, company: company, created_by: user, currency: "EUR")

      ids = "#{pr1.id},#{pr2.id}"

      conn =
        get(conn, ~p"/c/#{company.id}/payment-requests/csv?ids=#{ids}")

      assert redirected_to(conn) =~ "/payment-requests"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "same currency"
    end

    test "accountant cannot download CSV", %{company: company} do
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-csv-accountant",
          email: "csv-acc@example.com",
          name: "Accountant"
        })

      insert(:membership, user: accountant, company: company, role: :accountant)

      conn =
        build_conn()
        |> log_in_user(accountant, %{current_company_id: company.id})
        |> get(~p"/c/#{company.id}/payment-requests/csv?ids=#{Ecto.UUID.generate()}")

      assert redirected_to(conn) =~ "/payment-requests"
    end
  end
end
