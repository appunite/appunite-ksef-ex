defmodule KsefHubWeb.CategoryLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-cat-1",
        email: "cat@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "mount" do
    test "renders expense categories page", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")
      assert has_element?(view, "h1", "Expense Categories")
      assert has_element?(view, "h2", "New Category")
    end

    test "lists existing categories", %{conn: conn, company: company} do
      insert(:category, company: company, name: "finance:invoices", emoji: "💰")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/categories")
      assert html =~ "finance:invoices"
      assert html =~ "💰"
    end
  end

  describe "create" do
    test "creates a category with valid data", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{
          name: "ops:hosting",
          emoji: "🖥",
          description: "Hosting costs",
          sort_order: "1"
        }
      })

      html = render(view)
      assert html =~ "ops:hosting"
      assert html =~ "Category created."
    end

    test "shows error for invalid name format", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{name: "no-colon", emoji: "", description: "", sort_order: "0"}
      })

      html = render(view)
      assert html =~ "group:target"
    end
  end

  describe "edit" do
    test "populates form for editing", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "hr:salaries", emoji: "💼")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")

      view |> element("button", "Edit") |> render_click(%{"id" => cat.id})

      html = render(view)
      assert html =~ "Edit Category"
      assert html =~ "hr:salaries"
    end

    test "updates category", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "hr:salaries", emoji: "💼")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")

      view |> element("button", "Edit") |> render_click(%{"id" => cat.id})

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{name: "hr:benefits", emoji: "🎁", description: "Benefits", sort_order: "2"}
      })

      html = render(view)
      assert html =~ "hr:benefits"
      assert html =~ "Category updated."
    end

    test "cancel edit resets form", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "hr:salaries")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")

      view |> element("button", "Edit") |> render_click(%{"id" => cat.id})
      assert render(view) =~ "Edit Category"

      view |> element("button", "Cancel") |> render_click()
      assert render(view) =~ "New Category"
    end
  end

  describe "delete" do
    test "deletes a category", %{conn: conn, company: company} do
      cat = insert(:category, company: company, name: "delete:me")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/categories")
      assert render(view) =~ "delete:me"

      view |> element("button", "Delete") |> render_click(%{"id" => cat.id})

      html = render(view)
      assert html =~ "Category deleted."
      refute html =~ "delete:me"
    end
  end

  describe "company scoping" do
    test "does not show categories from other companies", %{conn: conn, company: company} do
      other_company = insert(:company)
      insert(:category, company: other_company, name: "other:secret")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/categories")
      refute html =~ "other:secret"
    end
  end
end
