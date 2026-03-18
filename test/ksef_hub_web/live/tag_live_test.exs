defmodule KsefHubWeb.TagLiveTest do
  use KsefHubWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import KsefHub.Factory

  alias KsefHub.Accounts

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.get_or_create_google_user(%{
        uid: "g-tag-1",
        email: "tag@example.com",
        name: "Test"
      })

    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)

    conn = conn |> log_in_user(user, %{current_company_id: company.id})
    %{conn: conn, user: user, company: company}
  end

  describe "Index" do
    test "renders tags page with expense tab active by default", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "Tags"
      assert html =~ "New Tag"
      assert html =~ "Expense"
      assert html =~ "Income"
    end

    test "lists existing expense tags on default tab", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "monthly", type: :expense)
      insert(:tag, company: company, name: "income-only", type: :income)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "monthly"
      refute html =~ "income-only"
    end

    test "lists income tags on income tab", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "expense-only", type: :expense)
      insert(:tag, company: company, name: "income-only", type: :income)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags?type=income")
      assert html =~ "income-only"
      refute html =~ "expense-only"
    end

    test "shows usage count", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "counted")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "counted"
      assert html =~ ">1</span>"
    end

  describe "create" do
    test "creates an expense tag on expense tab", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "quarterly", description: "Quarterly reports"}})

      html = render(view)
      assert html =~ "quarterly"
      assert html =~ "Tag created."
    end

    test "creates an income tag on income tab", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags?type=income")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "revenue-tag", description: "Revenue"}})

      html = render(view)
      assert html =~ "revenue-tag"
      assert html =~ "Tag created."
    end

    test "shows error for duplicate name within same type", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "duplicate", type: :expense)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "duplicate", description: ""}})

      html = render(view)
      assert html =~ "already been taken"
    end

    test "allows same name on different type tabs", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "shared", type: :expense)

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags?type=income")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "shared", description: ""}})

      html = render(view)
      assert html =~ "shared"
      assert html =~ "Tag created."
    end
  end

  describe "edit" do
    test "populates form for editing", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "edit-me")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view |> element("button", "Edit") |> render_click(%{"id" => tag.id})

      html = render(view)
      assert html =~ "Edit Tag"
      assert html =~ "edit-me"
    end

    test "updates tag", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "old-name")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view |> element("button", "Edit") |> render_click(%{"id" => tag.id})

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "new-name", description: "Updated"}})

      html = render(view)
      assert html =~ "new-name"
      assert html =~ "Tag updated."
    end

    test "cancel edit resets form", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "cancel-test")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view |> element("button", "Edit") |> render_click(%{"id" => tag.id})
      assert render(view) =~ "Edit Tag"

      view |> element("button", "Cancel") |> render_click()
      assert render(view) =~ "New Tag"
    end
  end

  describe "delete" do
    test "deletes a tag", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "delete-me")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")
      assert render(view) =~ "delete-me"

      view |> element("button", "Delete") |> render_click(%{"id" => tag.id})

      html = render(view)
      assert html =~ "Tag deleted."
      refute html =~ "delete-me"
    end

    test "does not show tags from other companies", %{conn: conn, company: company} do
      other_company = insert(:company)
      insert(:tag, company: other_company, name: "other-secret")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      refute html =~ "other-secret"
    end
  end

  describe "Form - new" do
    test "renders new tag form", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags/new")
      assert html =~ "New Tag"
      assert html =~ "Create Tag"
    end

    test "creates a tag with valid data", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags/new")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "quarterly", description: "Quarterly reports"}})

      flash = assert_redirect(view, ~p"/c/#{company.id}/tags")
      assert flash["info"] == "Tag created."
    end

    test "shows error for duplicate name", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "duplicate")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags/new")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "duplicate", description: ""}})

      html = render(view)
      assert html =~ "already been taken"
    end
  end

  describe "Form - edit" do
    test "renders edit form with tag data", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "edit-me")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags/#{tag.id}/edit")
      assert html =~ "Edit Tag"
      assert html =~ "edit-me"
    end

    test "updates tag", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "old-name")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags/#{tag.id}/edit")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "new-name", description: "Updated"}})

      flash = assert_redirect(view, ~p"/c/#{company.id}/tags")
      assert flash["info"] == "Tag updated."
    end

    test "redirects for non-existent tag", %{conn: conn, company: company} do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/c/#{company.id}/tags/#{Ecto.UUID.generate()}/edit")

      assert to == "/c/#{company.id}/tags"
      assert flash["error"] == "Tag not found."
    end
  end
end
