defmodule KsefHubWeb.ExportLive.IndexTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Repo

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-export-#{unique}",
        email: "export-#{unique}@example.com",
        name: "Export User"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders exports page with form and empty state", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "Exports"
      assert html =~ "New Export"
      assert html =~ "No exports yet"
    end

    test "shows existing batches", %{conn: conn, user: user, company: company} do
      insert(:export_batch,
        user: user,
        company: company,
        date_from: ~D[2026-01-01],
        date_to: ~D[2026-01-31],
        invoice_type: "expense",
        status: :completed,
        invoice_count: 5
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "2026-01-01"
      assert html =~ "2026-01-31"
      assert html =~ "expense"
      assert html =~ "5 invoices"
      refute html =~ "No exports yet"
    end

    test "shows download button for completed batches", %{
      conn: conn,
      user: user,
      company: company
    } do
      insert(:export_batch, user: user, company: company, status: :completed)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "Download ZIP"
    end

    test "shows processing badge for pending batches", %{conn: conn, user: user, company: company} do
      insert(:export_batch, user: user, company: company, status: :pending)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "Processing"
    end

    test "shows failed badge with error message", %{conn: conn, user: user, company: company} do
      insert(:export_batch,
        user: user,
        company: company,
        status: :failed,
        error_message: "something went wrong"
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "Failed"
      assert html =~ "something went wrong"
    end

    test "does not show batches from other users", %{conn: conn, company: company} do
      other_user = insert(:user)

      insert(:export_batch,
        user: other_user,
        company: company,
        date_from: ~D[2026-02-01],
        date_to: ~D[2026-02-28]
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "No exports yet"
    end
  end

  describe "preview" do
    test "shows count of matching invoices", %{conn: conn, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-20],
        type: :expense,
        status: :approved
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-01-31", invoice_type: "expense"})

      html =
        view
        |> element("form[phx-submit=export]")
        |> render_submit(%{"_action" => "preview"})

      assert html =~ "2 invoices match"
    end

    test "shows singular form for 1 invoice", %{conn: conn, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-01-31", invoice_type: "expense"})

      html =
        view
        |> element("form[phx-submit=export]")
        |> render_submit(%{"_action" => "preview"})

      assert html =~ "1 invoice matches"
    end

    test "shows 0 when no invoices match", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-01-31", invoice_type: "expense"})

      html =
        view
        |> element("form[phx-submit=export]")
        |> render_submit(%{"_action" => "preview"})

      assert html =~ "0 invoices match"
    end
  end

  describe "export" do
    test "creates a batch and shows it in the list", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-01-31", invoice_type: "expense"})

      html = view |> element("form[phx-submit=export]") |> render_submit()

      assert html =~ "Export started"
      assert html =~ "2026-01-01"
      assert html =~ "Processing"
    end

    test "shows error for invalid date range", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-03-15", invoice_type: "expense"})

      html = view |> element("form[phx-submit=export]") |> render_submit()

      assert html =~ "Export failed"
    end
  end

  describe "PubSub" do
    test "updates batch status on export_status message", %{
      conn: conn,
      user: user,
      company: company
    } do
      batch =
        insert(:export_batch,
          user: user,
          company: company,
          status: :pending
        )

      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/settings/exports")
      assert html =~ "Processing"

      # Simulate worker completing the batch
      batch
      |> Ecto.Changeset.change(%{status: :completed, invoice_count: 3})
      |> Repo.update!()

      send(view.pid, {:export_status, batch.id, :completed})

      html = render(view)
      assert html =~ "Download ZIP"
      assert html =~ "3 invoices"
    end

    test "ignores export_status for non-existent batch", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      send(view.pid, {:export_status, Ecto.UUID.generate(), :completed})

      # Should not crash
      html = render(view)
      assert html =~ "Exports"
    end
  end

  describe "form changes" do
    test "update_form resets preview count", %{conn: conn, company: company} do
      insert(:invoice,
        company: company,
        issue_date: ~D[2026-01-15],
        type: :expense,
        status: :approved
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/exports")

      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-01-01", date_to: "2026-01-31", invoice_type: "expense"})

      # Show preview count
      view
      |> element("form[phx-submit=export]")
      |> render_submit(%{"_action" => "preview"})

      assert render(view) =~ "1 invoice matches"

      # Changing form should reset the preview
      view
      |> element("form[phx-submit=export]")
      |> render_change(%{date_from: "2026-02-01", date_to: "2026-02-28", invoice_type: "expense"})

      refute render(view) =~ "invoice matches"
      refute render(view) =~ "invoices match"
    end
  end
end
