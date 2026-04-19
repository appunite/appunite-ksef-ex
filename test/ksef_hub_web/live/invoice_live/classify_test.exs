defmodule KsefHubWeb.InvoiceLive.ClassifyTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  import KsefHub.Factory

  alias KsefHub.Accounts
  alias KsefHub.ActivityLog.{Event, TestEmitter}
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
      insert(:category, company: company, identifier: "finance:invoices", emoji: "💰")
      insert(:category, company: company, identifier: "finance:payroll", emoji: "💵")
      insert(:category, company: company, identifier: "ops:hosting", emoji: "🖥")
      # Create invoices with tags so list_distinct_tags returns them
      insert(:invoice, type: :expense, company: company, tags: ["monthly"])
      insert(:invoice, type: :expense, company: company, tags: ["quarterly"])

      invoice = insert(:invoice, type: :expense, company: company)

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
      cat = insert(:category, company: company, identifier: "finance:invoices")
      invoice = insert(:invoice, type: :expense, company: company)

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
      cat = insert(:category, company: company, identifier: "finance:invoices")
      invoice = insert(:invoice, type: :expense, company: company, category: cat)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s([data-testid="clear-category"]))
      view |> element(~s([data-testid="clear-category"])) |> render_click()

      refute has_element?(view, ~s([data-testid="clear-category"]))
    end
  end

  describe "tag toggling" do
    test "toggling a tag updates local state", %{conn: conn, company: company} do
      insert(:invoice, type: :expense, company: company, tags: ["monthly"])
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Toggle tag on
      view
      |> element(~s(input[phx-value-tag-name="monthly"]))
      |> render_click()

      # Tag should now be checked
      assert has_element?(view, ~s(input[phx-value-tag-name="monthly"][checked]))
    end
  end

  describe "save" do
    test "persists category and tags, redirects to show", %{conn: conn, company: company} do
      cat = insert(:category, company: company, identifier: "finance:invoices")
      insert(:invoice, type: :expense, company: company, tags: ["monthly"])
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Expand and select category
      view |> element(~s([data-testid="group-finance"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()

      # Toggle tag
      view |> element(~s(input[phx-value-tag-name="monthly"])) |> render_click()

      # Save
      view |> element(~s([data-testid="save-classification"])) |> render_click()

      assert_redirected(view, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Verify persistence
      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert updated.expense_category_id == cat.id
      assert "monthly" in updated.tags
    end

    test "records activity events with the current user as actor", %{
      conn: conn,
      user: user,
      company: company
    } do
      TestEmitter.attach(self())

      cat = insert(:category, company: company, identifier: "finance:invoices")
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view |> element(~s([data-testid="group-finance"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()
      view |> element(~s([data-testid="save-classification"])) |> render_click()

      user_id = user.id

      assert_received {:activity_event,
                       %Event{
                         action: "invoice.classification_changed",
                         user_id: ^user_id,
                         actor_type: :user,
                         actor_label: "Classifier"
                       }}
    end

    test "marks predicted invoice as manual on save", %{conn: conn, company: company} do
      cat = insert(:category, company: company, identifier: "ops:hosting")

      invoice =
        insert(:invoice,
          type: :expense,
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
      cat = insert(:category, company: company, identifier: "finance:invoices")
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # Select category but cancel
      view |> element(~s([data-testid="group-finance"])) |> render_click()
      view |> element(~s([data-testid="category-#{cat.id}"])) |> render_click()
      view |> element("button", "Cancel") |> render_click()

      assert_redirected(view, ~p"/c/#{company.id}/invoices/#{invoice.id}")

      # Verify no persistence
      updated = Invoices.get_invoice_with_details!(company.id, invoice.id)
      assert is_nil(updated.expense_category_id)
    end
  end

  describe "create tag" do
    test "creates tag inline and adds to selection", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view
      |> element("form[phx-submit=create_tag]")
      |> render_submit(%{"name" => "brand-new-tag"})

      html = render(view)
      assert html =~ "brand-new-tag"
      assert has_element?(view, ~s(input[checked]))
    end
  end

  describe "tag visibility (show more / show less)" do
    test "with >8 tags, only first 8 are visible initially", %{conn: conn, company: company} do
      tag_names = for i <- 1..12, do: "tag-#{i}"

      # Create invoices with these tags so list_distinct_tags returns them
      for name <- tag_names do
        insert(:invoice, type: :expense, company: company, tags: [name])
      end

      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      visible_count =
        Enum.count(tag_names, fn name ->
          has_element?(view, ~s(input[phx-value-tag-name="#{name}"]))
        end)

      assert visible_count == 8

      # "Show more" button should be present
      assert has_element?(view, ~s([data-testid="toggle-show-all-tags"]))
      assert html =~ "Show more (4 more)"
    end

    test "clicking 'Show more' reveals all tags", %{conn: conn, company: company} do
      tag_names = for i <- 1..10, do: "tag-#{i}"

      for name <- tag_names do
        insert(:invoice, type: :expense, company: company, tags: [name])
      end

      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view |> element(~s([data-testid="toggle-show-all-tags"])) |> render_click()

      # All tags should be visible now
      for name <- tag_names do
        assert has_element?(view, ~s(input[phx-value-tag-name="#{name}"]))
      end

      # Button should now say "Show less"
      assert render(view) =~ "Show less"
    end

    test "selected tags beyond top 8 are always visible", %{conn: conn, company: company} do
      tag_names = for i <- 1..10, do: "tag-#{i}"

      for name <- tag_names do
        insert(:invoice, type: :expense, company: company, tags: [name])
      end

      # Pick a tag that will be beyond the top 8 — use the oldest one
      # (list_distinct_tags orders by most recently used, so first-inserted is last)
      oldest_tag = "tag-1"

      invoice = insert(:invoice, type: :expense, company: company, tags: [oldest_tag])

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      # The selected tag should be visible even if it's beyond the top 8
      assert has_element?(view, ~s(input[phx-value-tag-name="#{oldest_tag}"][checked]))
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
      insert(:membership, user: reviewer, company: company, role: :approver)

      conn = build_conn() |> log_in_user(reviewer, %{current_company_id: company.id})
      stub(KsefHub.PdfRenderer.Mock, :generate_html, fn _xml, _meta -> {:error, :no_xml} end)
      %{conn: conn, company: company}
    end

    test "reviewer can view expense invoice classify page", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")
      assert html =~ "Classification"
    end

    test "reviewer can add tags inline", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      html = render_click(view, "create_tag", %{"name" => "new-tag"})
      assert html =~ "new-tag"
    end

    test "accountant is redirected from classify page (requires :set_invoice_category)", ctx do
      {:ok, accountant} =
        Accounts.get_or_create_google_user(%{
          uid: "g-classify-acct",
          email: "classify-acct@example.com",
          name: "Accountant"
        })

      insert(:membership, user: accountant, company: ctx.company, role: :accountant)
      conn = build_conn() |> log_in_user(accountant, %{current_company_id: ctx.company.id})

      invoice = insert(:invoice, type: :expense, company: ctx.company)

      expected_path = "/c/#{ctx.company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(conn, ~p"/c/#{ctx.company.id}/invoices/#{invoice.id}/classify")
    end
  end

  describe "cost line" do
    test "renders cost line dropdown for expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s([data-testid="cost-line-section"]))
      assert has_element?(view, ~s([data-testid="cost-line-select"]))
      assert has_element?(view, ~s(option[value="growth"]))
      assert has_element?(view, ~s(option[value="service_delivery"]))
    end

    test "auto-updates cost line when selecting category with default", %{
      conn: conn,
      company: company
    } do
      category = insert(:category, company: company, default_cost_line: :service_delivery)
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "select_category", %{"id" => category.id})

      assert has_element?(view, ~s(option[value="service_delivery"][selected]))
    end

    test "persists cost line on save", %{conn: conn, company: company} do
      category = insert(:category, company: company, default_cost_line: :growth)
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "select_category", %{"id" => category.id})
      render_click(view, "save")

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.expense_cost_line == :growth
    end

    test "allows manual cost line override after category select", %{
      conn: conn,
      company: company
    } do
      category = insert(:category, company: company, default_cost_line: :growth)
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "select_category", %{"id" => category.id})
      render_change(view, "select_cost_line", %{"expense_cost_line" => "heads"})
      render_click(view, "save")

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.expense_cost_line == :heads
      assert updated.expense_category_id == category.id
    end

    test "persists cost line without category on save", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_change(view, "select_cost_line", %{"expense_cost_line" => "service"})
      render_click(view, "save")

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.expense_cost_line == :service
      assert is_nil(updated.expense_category_id)
    end

    test "does not render cost line section for income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      refute has_element?(view, ~s([data-testid="cost-line-section"]))
    end
  end

  describe "project tag" do
    test "renders project tag section for expense invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s([data-testid="project-tag-section"]))
    end

    test "renders project tag section for income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s([data-testid="project-tag-section"]))
    end

    test "shows existing project tags as radio buttons", %{conn: conn, company: company} do
      insert(:invoice, company: company, type: :expense, project_tag: "Alpha")
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      assert has_element?(view, ~s(input[type="radio"][value="Alpha"]))
    end

    test "selecting a project tag updates selection", %{conn: conn, company: company} do
      insert(:invoice, company: company, type: :expense, project_tag: "Alpha")
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "select_project_tag", %{"value" => "Alpha"})

      assert has_element?(
               view,
               ~s(input[type="radio"][value="Alpha"][checked])
             )
    end

    test "custom project tag adds to list and selects it", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view
      |> element("form[phx-submit=set_custom_project_tag]")
      |> render_submit(%{"name" => "New Project"})

      html = render(view)
      assert html =~ "New Project"
    end

    test "persists project tag on save", %{conn: conn, company: company} do
      insert(:invoice, company: company, type: :expense, project_tag: "Alpha")
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "select_project_tag", %{"value" => "Alpha"})
      render_click(view, "save")

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.project_tag == "Alpha"
    end

    test "persists project tag on income invoice", %{conn: conn, company: company} do
      invoice = insert(:invoice, type: :income, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      view
      |> element("form[phx-submit=set_custom_project_tag]")
      |> render_submit(%{"name" => "Revenue Project"})

      render_click(view, "save")

      updated = Invoices.get_invoice!(company.id, invoice.id)
      assert updated.project_tag == "Revenue Project"
    end

    test "shows only 8 project tags by default with show more button", %{
      conn: conn,
      company: company
    } do
      for i <- 1..12,
          do: insert(:invoice, company: company, type: :expense, project_tag: "P-#{i}")

      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      html = render(view)

      # Count rendered project tag radio buttons (excluding the "None" option with value="")
      visible_count =
        ~r/input[^>]*name="project_tag"[^>]*value="(?!")[^"]+"/
        |> Regex.scan(html)
        |> length()

      assert visible_count == 8

      assert has_element?(view, ~s([data-testid="toggle-show-all-project-tags"]))
      assert html =~ "Show more (4 more)"
    end

    test "toggle show all project tags reveals hidden tags", %{conn: conn, company: company} do
      tags = for i <- 1..12, do: "Project-#{String.pad_leading("#{i}", 2, "0")}"
      for tag <- tags, do: insert(:invoice, company: company, type: :expense, project_tag: tag)
      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      render_click(view, "toggle_show_all_project_tags")

      html = render(view)

      for tag <- tags do
        assert html =~ tag
      end

      assert html =~ "Show less"
    end

    test "selected project tag beyond top 8 is still visible", %{conn: conn, company: company} do
      tags = for i <- 1..12, do: "Project-#{String.pad_leading("#{i}", 2, "0")}"
      for tag <- tags, do: insert(:invoice, company: company, type: :expense, project_tag: tag)

      # Recency-descending: Project-12 at position 1, Project-09 at position 4 (visible),
      # Project-04 at position 9 (hidden). Project-01 is beyond the top 8 but remains
      # visible because it is the selected tag on the invoice being classified.
      invoice = insert(:invoice, type: :expense, company: company, project_tag: "Project-01")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      html = render(view)
      assert html =~ "Project-01"
    end

    test "does not show toggle button when 8 or fewer project tags", %{
      conn: conn,
      company: company
    } do
      for i <- 1..8,
          do: insert(:invoice, company: company, type: :expense, project_tag: "Tag-#{i}")

      invoice = insert(:invoice, type: :expense, company: company)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/invoices/#{invoice.id}/classify")

      refute has_element?(view, ~s([data-testid="toggle-show-all-project-tags"]))
    end
  end
end
