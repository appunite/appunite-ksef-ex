defmodule KsefHubWeb.TrainingCsvControllerTest do
  @moduledoc "Tests for the TrainingCsvController download action."

  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  describe "download" do
    test "downloads extended CSV with matching invoices", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        expense_approval_status: :approved
      )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=2026-01-01&date_to=2026-01-31")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") |> hd() =~
               "training_2026-01-01_2026-01-31.csv"

      body = conn.resp_body
      # Starts with UTF-8 BOM
      assert String.starts_with?(body, <<0xEF, 0xBB, 0xBF>>)
      # Includes extended headers
      assert body =~ "Invoice ID"
      assert body =~ "Company ID"
      assert body =~ "Prediction Status"
      assert body =~ "Category Confidence %"
    end

    test "returns CSV with only headers when no invoices match", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=2026-01-01&date_to=2026-01-31")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/csv"

      lines =
        conn.resp_body
        |> String.replace_prefix(<<0xEF, 0xBB, 0xBF>>, "")
        |> String.split("\r\n", trim: true)

      assert length(lines) == 1
    end

    test "redirects with error for invalid date format", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=bad&date_to=2026-01-31")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid date range"
    end

    test "redirects with error when date_to is before date_from", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=2026-02-01&date_to=2026-01-01")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid date range"
    end

    test "redirects with error when date params are missing", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Date range is required"
    end

    test "redirects when user lacks manage_services permission", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :approver)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=2026-01-01&date_to=2026-01-31")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end

    test "redirects when user has no membership in company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/training-csv?date_from=2026-01-01&date_to=2026-01-31")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/services"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end
  end
end
