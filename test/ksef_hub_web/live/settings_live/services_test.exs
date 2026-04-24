defmodule KsefHubWeb.SettingsLive.ServicesTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.ServiceConfig

  setup %{conn: conn} do
    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = log_in_user(conn, user, %{current_company_id: company.id})
    %{conn: conn, company: company, user: user}
  end

  describe "access control" do
    test "owner can access classifier page", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")
      assert html =~ "Invoice Classifier"
    end

    test "admin can access classifier page", %{conn: conn, company: company} do
      admin = insert(:user)
      insert(:membership, user: admin, company: company, role: :admin)
      admin_conn = log_in_user(conn, admin, %{current_company_id: company.id})

      {:ok, _view, html} = live(admin_conn, ~p"/c/#{company.id}/settings/services")
      assert html =~ "Invoice Classifier"
    end

    test "approver cannot access classifier page", %{conn: conn, company: company} do
      approver = insert(:user)
      insert(:membership, user: approver, company: company, role: :approver)
      approver_conn = log_in_user(conn, approver, %{current_company_id: company.id})

      expected_path = "/c/#{company.id}/invoices"

      assert {:error, {:redirect, %{to: ^expected_path}}} =
               live(approver_conn, ~p"/c/#{company.id}/settings/services")
    end

    test "classifier tab visible only to owner/admin", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings")
      assert has_element?(view, "nav[aria-label='Settings'] a", "Classifier")

      approver = insert(:user)
      insert(:membership, user: approver, company: company, role: :approver)
      approver_conn = log_in_user(conn, approver, %{current_company_id: company.id})

      {:ok, view, _html} = live(approver_conn, ~p"/c/#{company.id}/settings")
      refute has_element?(view, "nav[aria-label='Settings'] a", "Classifier")
    end
  end

  describe "page rendering" do
    test "renders classifier page with classification disabled by default", %{
      conn: conn,
      company: company
    } do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")

      assert html =~ "Invoice Classifier"
      assert html =~ "Classification is disabled"
    end

    test "shows threshold inputs", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")

      assert html =~ "Category confidence threshold"
      assert html =~ "Tag confidence threshold"
    end

    test "shows endpoint docs when expanded", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/services")

      refute render(view) =~ "/predict/category"

      view |> element("button", "API endpoints") |> render_click()

      html = render(view)
      assert html =~ "/predict/category"
      assert html =~ "/predict/tag"
      assert html =~ "/health"
    end
  end

  describe "saving" do
    test "shows required field errors when enabling override with empty fields", %{
      conn: conn,
      company: company
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/services")

      html =
        view
        |> form("form[phx-submit=save]", classifier: %{enabled: true})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "validates URL format", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/services")

      html =
        view
        |> form("form[phx-submit=save]", classifier: %{enabled: true, url: "not-a-url"})
        |> render_change()

      assert html =~ "must be a valid HTTP(S) URL"
    end

    test "saves classifier config via context", %{company: company, user: user} do
      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, updated} =
        ServiceConfig.update_classifier_config(
          config,
          %{
            "enabled" => true,
            "url" => "http://custom:9000",
            "category_confidence_threshold" => "0.85",
            "tag_confidence_threshold" => "0.90"
          },
          user_id: user.id
        )

      assert updated.enabled == true
      assert updated.url == "http://custom:9000"
      assert updated.category_confidence_threshold == 0.85
      assert updated.tag_confidence_threshold == 0.9
      assert updated.updated_by_id == user.id
    end

    test "private network URL shows save-anyway confirmation", %{
      conn: conn,
      company: company
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/services")

      form_params = %{
        enabled: true,
        url: "http://10.0.0.1:9999",
        category_confidence_threshold: "0.80",
        tag_confidence_threshold: "0.90"
      }

      # Submit with a private IP — shows confirmation dialog
      view
      |> form("form[phx-submit=save]", classifier: form_params)
      |> render_submit()

      # Wait for the async health-check task to deliver its result
      Process.sleep(50)
      html = render(view)

      assert html =~ "Save anyway"

      # Config not saved yet (pending confirmation)
      config = ServiceConfig.get_or_create_classifier_config(company.id)
      refute config.enabled

      # Confirm save succeeds
      view
      |> element("button", "Save anyway")
      |> render_click()

      config = ServiceConfig.get_or_create_classifier_config(company.id)
      assert config.enabled
      assert config.url == "http://10.0.0.1:9999"
    end

    test "company configs are isolated", %{conn: conn, company: company} do
      other_company = insert(:company)

      config = ServiceConfig.get_or_create_classifier_config(company.id)

      {:ok, _} =
        ServiceConfig.update_classifier_config(config, %{
          "enabled" => true,
          "url" => "http://a:9000",
          "category_confidence_threshold" => "0.71",
          "tag_confidence_threshold" => "0.95"
        })

      other_config = ServiceConfig.get_or_create_classifier_config(other_company.id)

      {:ok, _} =
        ServiceConfig.update_classifier_config(other_config, %{
          "enabled" => true,
          "url" => "http://b:9001",
          "category_confidence_threshold" => "0.71",
          "tag_confidence_threshold" => "0.95"
        })

      # Each company sees its own config
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")
      assert html =~ "http://a:9000"
      refute html =~ "http://b:9001"
    end
  end

  describe "training data export" do
    test "renders training data export section", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")
      assert html =~ "Training Data Export"
      assert html =~ "Export Training CSV"
    end

    test "download link includes date range params", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/services")

      assert html =~ ~r/href="[^"]*\/training-csv\?[^"]*date_from=[^&"]+[^"]*&amp;date_to=[^"]+"/
    end
  end
end
