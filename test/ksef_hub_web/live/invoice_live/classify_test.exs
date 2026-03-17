defmodule KsefHubWeb.InvoiceLive.ClassifyTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.Invoices

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-classify-1",
        email: "classify@example.com",
        name: "Classifier"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders grouped categories and tags", %{conn: conn, company: company} do
      insert(:category, company: company, name: "finance:invoices", emoji: "💰")
      insert(:category, company: company, name: "finance:payroll", emoji: "💵")
      insert(:category, company: company, name: "ops:hosting", emoji: "🖥")
      insert(:tag, company: company, name: "monthly")
      insert(:tag, company: company, name: "quarterly")

      invoice = insert(:invoice, company: company)

      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert html =~ "Classification"
      assert has_element?(view, ~s([data-testid="group-finance"]))
      assert has_element?(view, ~s([data-testid="group-ops"]))
      assert html =~ "monthly"
      assert html =~ "quarterly"
    end

    test "redirects when invoice not found", %{conn: conn, company: company} do
      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/c/#{company.id}/invoices/#{Ecto.UUID.generate()}/classify")

      assert path =~ "/invoices"
    end
  end

  describe "category selection" do
    test "selecting a category updates local state", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "finance:invoices")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Expand finance group
      view |> element(~s([data-testid="group-finance"])) |> render_click()

      # Select category
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()

      # The category should be highlighted (has primary color class)
      html = render(view)
      assert html =~ "bg-shad-primary/10"
    end

    test "clearing category removes selection", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "finance:invoices")
      invoice = insert(:invoice, company: company, category: cat)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s([data-testid="clear-category"]))
      view |> element(~s([data-testid="clear-category"])) |> render_click()

      refute has_element?(view, ~s([data-testid="clear-category"]))
    end
  end

  describe "tag toggling" do
    test "toggling a tag updates local state", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "monthly")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Toggle tag on
      view
      |> element(~s(input[phx-value-tag-id="#{tag.id}"]))
      |> render_click()

      # Tag should now be checked
      assert has_element?(view, ~s(input[phx-value-tag-id="#{tag.id}"][checked]))
    end
  end

  describe "save" do
    test "persists category and tags, redirects to show", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "finance:invoices")
      tag = insert(:tag, company: company, name: "monthly")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Expand and select category
      view |> element(~s([data-testid="group-finance"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()

      # Toggle tag
      view |> element(~s(input[phx-value-tag-id="#{tag.id}"])) |> render_click()

      # Save
      view |> element(~s([data-testid="save-classification"])) |> render_click()

      assert_redirected(view, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Verify persistence
      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert updated.category_id == cat.id
      assert Enum.any?(updated.tags, &(&1.id == tag.id))
    end

    test "marks predicted invoice as manual on save", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "ops:hosting")

      invoice =
        insert(:invoice,
          company: company,
          prediction_status: :predicted,
          prediction_predicted_at: ~U[2026-03-11 12:00:00Z]
        )

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view |> element(~s([data-testid="group-ops"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()
      view |> element(~s([data-testid="save-classification"])) |> render_click()

      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert updated.prediction_status == :manual
    end
  end

  describe "cancel" do
    test "navigates back without saving", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "finance:invoices")
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Select category but cancel
      view |> element(~s([data-testid="group-finance"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()
      view |> element("button", "Cancel") |> render_click()

      assert_redirected(view, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Verify no persistence
      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert is_nil(updated.category_id)
    end
  end

  describe "create tag" do
    test "creates tag inline and adds to selection", %{conn: conn, company: company} do
      invoice = insert(:invoice, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view
      |> element("form[phx-submit=create_tag]")
      |> render_submit(%{"name" => "brand-new-tag"})

      html = render(view)
      assert html =~ "brand-new-tag"
      assert has_element?(view, ~s(input[checked]))
    end
  end

  describe "permissions" do
    setup do
      {:ok, reviewer} =
        Accounts.get_or_create_google_user(%{
          uid: "g-classify-rev-1",
          email: "classify-reviewer@example.com",
          name: "Reviewer"
        })

      company = insert(:company)
      insert(:membership, user: reviewer, company: company, role: :reviewer)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
      %{conn: conn, company: company}
    end

    test "reviewer can view expense invoice classify page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")
      assert html =~ "Classification"
    end
  end
end
