defmodule KsefHubWeb.SettingsLive.ActivityLogTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  setup %{conn: conn} do
    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, company: company, user: user}
  end

  describe "resource links" do
    test "invoice entries link to the invoice page", %{conn: conn, company: company, user: user} do
      invoice_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.created",
        resource_type: "invoice",
        resource_id: invoice_id,
        metadata: %{"source" => "manual"}
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "a[href*='invoices/#{invoice_id}']", "Invoice")
    end

    test "payment request entries link to the associated invoice", %{
      conn: conn,
      company: company,
      user: user
    } do
      invoice_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company,
        user: user,
        action: "payment_request.paid",
        resource_type: "payment_request",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"invoice_id" => invoice_id}
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "a[href*='invoices/#{invoice_id}']", "Payment Request")
    end

    test "credential entries link to the certificates settings", %{
      conn: conn,
      company: company,
      user: user
    } do
      insert(:audit_log,
        company: company,
        user: user,
        action: "credential.uploaded",
        resource_type: "credential",
        resource_id: Ecto.UUID.generate()
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "a[href*='settings/certificates']", "Credential")
    end

    test "entries without a navigable page show plain text", %{
      conn: conn,
      company: company,
      user: user
    } do
      insert(:audit_log,
        company: company,
        user: user,
        action: "sync.triggered",
        resource_type: "sync",
        resource_id: nil
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      # Resource column renders a <span>, not a link, for non-navigable resources
      assert has_element?(view, "#activity-log-table span", "Sync")
      refute has_element?(view, "#activity-log-table a", "Sync")
    end
  end

  describe "action descriptions" do
    test "shows human-readable action for status change", %{
      conn: conn,
      company: company,
      user: user
    } do
      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.status_changed",
        resource_type: "invoice",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"old_status" => "pending", "new_status" => "approved"}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Changed status to approved"
      assert html =~ "was pending"
    end

    test "shows category change with names", %{conn: conn, company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.classification_changed",
        resource_type: "invoice",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"field" => "category", "old_name" => "Operations", "new_name" => "Growth"}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Changed category from Operations to Growth"
    end

    test "shows tag changes with added/removed detail", %{
      conn: conn,
      company: company,
      user: user
    } do
      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.classification_changed",
        resource_type: "invoice",
        resource_id: Ecto.UUID.generate(),
        metadata: %{
          "field" => "tags",
          "old_value" => ["payroll"],
          "new_value" => ["payroll", "q1"]
        }
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Updated tags"
      assert html =~ "added: q1"
    end

    test "shows invitation with email", %{conn: conn, company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "team.invitation_sent",
        resource_type: "invitation",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"email" => "new@example.com", "role" => "reviewer"}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Sent invitation to new@example.com"
      assert html =~ "as reviewer"
    end

    test "shows category CRUD with name", %{conn: conn, company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "category.created",
        resource_type: "category",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"name" => "Marketing"}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ ~s(Created category &quot;Marketing&quot;)
    end

    test "gracefully handles unknown action types", %{conn: conn, company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "some.future_action",
        resource_type: "mystery",
        resource_id: Ecto.UUID.generate()
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Some Future Action"
    end

    test "falls back to 'Updated classification' for old events without names", %{
      conn: conn,
      company: company,
      user: user
    } do
      insert(:audit_log,
        company: company,
        user: user,
        action: "invoice.classification_changed",
        resource_type: "invoice",
        resource_id: Ecto.UUID.generate(),
        metadata: %{"field" => "category"}
      )

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert html =~ "Updated category"
    end
  end
end
