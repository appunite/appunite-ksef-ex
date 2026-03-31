defmodule KsefHubWeb.CategoryLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup :set_mox_from_context
  setup :verify_on_exit!

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

  describe "Index" do
    test "renders expense categories page", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/categories")
      assert html =~ "Expense Categories"
      assert html =~ "New Category"
    end

    test "lists existing categories", %{conn: conn, company: company} do
      insert(:category, company: company, identifier: "finance:invoices", emoji: "💰")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/categories")
      assert html =~ "finance:invoices"
      assert html =~ "💰"
    end

    test "deletes a category", %{conn: conn, company: company} do
      cat = insert(:category, company: company, identifier: "delete:me")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories")
      assert render(view) =~ "delete:me"

      view |> element("button", "Delete") |> render_click(%{"id" => cat.id})

      html = render(view)
      assert html =~ "Category deleted."
      refute html =~ "delete:me"
    end

    test "does not show categories from other companies", %{conn: conn, company: company} do
      other_company = insert(:company)
      insert(:category, company: other_company, identifier: "other:secret")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/categories")
      refute html =~ "other:secret"
    end
  end

  describe "Form - new" do
    test "renders new category form", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")
      assert html =~ "New Category"
      assert html =~ "Create Category"
    end

    test "creates a category with valid data", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{
          identifier: "ops:hosting",
          name: "Hosting",
          emoji: "🖥",
          description: "Hosting costs",
          sort_order: "1"
        }
      })

      flash = assert_redirect(view, ~p"/c/#{company.id}/settings/categories")
      assert flash["info"] == "Category created."
    end

    test "shows error for invalid identifier format", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{
          identifier: "no-colon",
          emoji: "",
          description: "",
          sort_order: "0"
        }
      })

      html = render(view)
      assert html =~ "group:target"
    end
  end

  describe "Form - edit" do
    test "renders edit form with category data", %{conn: conn, company: company} do
      cat = insert(:category, company: company, identifier: "hr:salaries", emoji: "💼")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/settings/categories/#{cat.id}/edit")
      assert html =~ "Edit Category"
      assert html =~ "hr:salaries"
    end

    test "updates category", %{conn: conn, company: company} do
      cat = insert(:category, company: company, identifier: "hr:salaries", emoji: "💼")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/#{cat.id}/edit")

      view
      |> element("form#category-form")
      |> render_submit(%{
        category: %{
          identifier: "hr:benefits",
          emoji: "🎁",
          description: "Benefits",
          sort_order: "2"
        }
      })

      flash = assert_redirect(view, ~p"/c/#{company.id}/settings/categories")
      assert flash["info"] == "Category updated."
    end

    test "redirects for non-existent category", %{conn: conn, company: company} do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/c/#{company.id}/settings/categories/#{Ecto.UUID.generate()}/edit")

      assert to == "/c/#{company.id}/settings/categories"
      assert flash["error"] == "Category not found."
    end
  end

  describe "Form - emoji generation" do
    test "generate_emoji updates form with emoji on success",
         %{conn: conn, company: company} do
      KsefHub.EmojiGenerator.Mock
      |> expect(:generate_emoji, fn context ->
        assert context.identifier == "finance:invoices"
        {:ok, "💰"}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      # Type identifier first (trigger validate so form has params)
      view
      |> element("form#category-form")
      |> render_change(%{category: %{identifier: "finance:invoices", sort_order: "5"}})

      # Click auto-generate — task runs async via Task.Supervisor.async_nolink
      view |> element("button", "Auto") |> render_click()

      # Wait for the async task result to be delivered
      Process.sleep(50)

      # Emoji should be in the form
      html = render(view)
      assert html =~ "💰"
      # sort_order should be preserved
      assert html =~ "5"
    end

    test "shows flash on emoji generation failure", %{conn: conn, company: company} do
      KsefHub.EmojiGenerator.Mock
      |> expect(:generate_emoji, fn _context ->
        {:error, :api_error}
      end)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      view
      |> element("form#category-form")
      |> render_change(%{category: %{identifier: "finance:invoices"}})

      view |> element("button", "Auto") |> render_click()

      # Wait for the async task result to be delivered
      Process.sleep(50)
      html = render(view)
      assert html =~ "Failed to generate emoji"
    end

    test "handles task crash gracefully via DOWN message", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      # Simulate a DOWN message arriving (e.g. task supervisor crash)
      send(view.pid, {:DOWN, make_ref(), :process, self(), :normal})

      # Should not crash the LiveView
      html = render(view)
      refute html =~ "Generating"
    end

    test "shows error when identifier is empty", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/settings/categories/new")

      view |> element("button", "Auto") |> render_click()

      assert render(view) =~ "Enter an identifier first"
    end
  end
end
