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

  describe "mount" do
    test "renders tags page", %{conn: conn, company: company} do
      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "Tags"
      assert html =~ "New Tag"
    end

    test "lists existing tags", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "monthly")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "monthly"
    end

    test "shows usage count", %{conn: conn, company: company} do
      tag = insert(:tag, company: company, name: "counted")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      assert html =~ "counted"
      # The usage count should show "1"
      assert html =~ ">1</span>"
    end
  end

  describe "create" do
    test "creates a tag with valid data", %{conn: conn, company: company} do
      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "quarterly", description: "Quarterly reports"}})

      html = render(view)
      assert html =~ "quarterly"
      assert html =~ "Tag created."
    end

    test "shows error for duplicate name", %{conn: conn, company: company} do
      insert(:tag, company: company, name: "duplicate")

      {:ok, view, _html} = live(conn, ~p"/c/#{company.id}/tags")

      view
      |> element("form#tag-form")
      |> render_submit(%{tag: %{name: "duplicate", description: ""}})

      html = render(view)
      assert html =~ "already been taken"
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
  end

  describe "company scoping" do
    test "does not show tags from other companies", %{conn: conn, company: company} do
      other_company = insert(:company)
      insert(:tag, company: other_company, name: "other-secret")

      {:ok, _view, html} = live(conn, ~p"/c/#{company.id}/tags")
      refute html =~ "other-secret"
    end
  end
end
