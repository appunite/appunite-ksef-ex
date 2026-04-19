defmodule KsefHubWeb.ExportControllerTest do
  @moduledoc "Tests for the ExportController download action."

  use KsefHubWeb.ConnCase, async: true

  import KsefHub.Factory

  describe "download" do
    test "downloads ZIP for completed batch", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      file = insert(:file, content: "fake-zip-content", content_type: "application/zip")

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          status: :completed,
          zip_file: file
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{batch.id}/download")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/zip"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "attachment"
      assert get_resp_header(conn, "content-disposition") |> hd() =~ "invoices_"
      assert conn.resp_body == "fake-zip-content"
    end

    test "redirects when batch not found", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      fake_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{fake_id}/download")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/exports"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Export not found"
    end

    test "redirects when batch not yet completed", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          status: :processing
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{batch.id}/download")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/exports"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not yet ready"
    end

    test "redirects when batch completed but no zip_file associated", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :owner)

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          status: :completed,
          zip_file: nil
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{batch.id}/download")

      assert redirected_to(conn) == ~p"/c/#{company.id}/settings/exports"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "file not found"
    end

    test "redirects when user has no permission (reviewer)", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      insert(:membership, user: user, company: company, role: :approver)

      batch =
        insert(:export_batch,
          user: user,
          company: company,
          status: :completed
        )

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{batch.id}/download")

      assert redirected_to(conn) == ~p"/c/#{company.id}/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end

    test "redirects when user has no membership in company", %{conn: conn} do
      user = insert(:user)
      company = insert(:company)
      # No membership created

      batch_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/c/#{company.id}/exports/#{batch_id}/download")

      assert redirected_to(conn) == ~p"/c/#{company.id}/invoices"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "permission"
    end
  end
end
