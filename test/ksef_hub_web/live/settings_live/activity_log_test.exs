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

    test "payment request entries with resource_id link to the payment request", %{
      conn: conn,
      company: company,
      user: user
    } do
      pr_id = Ecto.UUID.generate()

      insert(:audit_log,
        company: company,
        user: user,
        action: "payment_request.paid",
        resource_type: "payment_request",
        resource_id: pr_id,
        metadata: %{"invoice_id" => Ecto.UUID.generate()}
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "a[href*='payment-requests/#{pr_id}/edit']", "Payment Request")
    end

    test "payment request entries without resource_id fall back to invoice link", %{
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
        resource_id: nil,
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Changed status to approved")
      assert has_element?(view, "#activity-log-table td", "was pending")
    end

    test "shows human-readable action for status change with atom-keyed metadata", %{
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
        metadata: %{old_status: "pending", new_status: "approved"}
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Changed status to approved")
      assert has_element?(view, "#activity-log-table td", "was pending")
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(
               view,
               "#activity-log-table td",
               "Changed category from Operations to Growth"
             )
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Updated tags")
      assert has_element?(view, "#activity-log-table td", "added: q1")
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Sent invitation to new@example.com")
      assert has_element?(view, "#activity-log-table td", "as reviewer")
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", ~s(Created category "Marketing"))
    end

    test "gracefully handles unknown action types", %{conn: conn, company: company, user: user} do
      insert(:audit_log,
        company: company,
        user: user,
        action: "some.future_action",
        resource_type: "mystery",
        resource_id: Ecto.UUID.generate()
      )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Some Future Action")
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

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/activity-log")

      assert has_element?(view, "#activity-log-table td", "Updated category")
    end
  end
end
