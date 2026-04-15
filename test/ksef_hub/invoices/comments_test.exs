defmodule KsefHub.Invoices.CommentsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "list_invoice_comments/2" do
    test "returns comments ordered by inserted_at ascending", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      {:ok, _c1} =
        Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "first"})

      {:ok, _c2} =
        Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "second"})

      comments = Invoices.list_invoice_comments(company.id, invoice.id)
      assert length(comments) == 2

      sorted = Enum.sort_by(comments, &{&1.inserted_at, &1.id})
      assert Enum.map(comments, & &1.id) == Enum.map(sorted, & &1.id)
    end

    test "preloads user on each comment", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)
      Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "hello"})

      [comment] = Invoices.list_invoice_comments(company.id, invoice.id)
      assert comment.user.id == user.id
      assert comment.user.email == user.email
    end

    test "returns empty list when no comments exist", %{company: company} do
      invoice = insert(:invoice, company: company)
      assert [] == Invoices.list_invoice_comments(company.id, invoice.id)
    end

    test "only returns comments for the given invoice", %{company: company} do
      invoice1 = insert(:invoice, company: company)
      invoice2 = insert(:invoice, company: company)
      user = insert(:user)

      Invoices.create_invoice_comment(company.id, invoice1.id, user.id, %{body: "for invoice 1"})
      Invoices.create_invoice_comment(company.id, invoice2.id, user.id, %{body: "for invoice 2"})

      comments = Invoices.list_invoice_comments(company.id, invoice1.id)
      assert length(comments) == 1
      assert hd(comments).body == "for invoice 1"
    end

    test "returns empty list for invoice in different company", %{company: company} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)
      user = insert(:user)
      Invoices.create_invoice_comment(other_company.id, invoice.id, user.id, %{body: "hello"})

      assert [] == Invoices.list_invoice_comments(company.id, invoice.id)
    end
  end

  describe "create_invoice_comment/4" do
    test "creates a comment with valid attrs", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      assert {:ok, comment} =
               Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{
                 body: "Looks good"
               })

      assert comment.body == "Looks good"
      assert comment.invoice_id == invoice.id
      assert comment.user_id == user.id
      assert comment.user.id == user.id
    end

    test "rejects empty body", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      assert {:error, changeset} =
               Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: ""})

      assert errors_on(changeset).body
    end

    test "rejects body exceeding 10000 characters", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)
      long_body = String.duplicate("a", 10_001)

      assert {:error, changeset} =
               Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{
                 body: long_body
               })

      assert errors_on(changeset).body
    end

    test "returns not_found for invoice in different company", %{company: company} do
      other_company = insert(:company)
      invoice = insert(:invoice, company: other_company)
      user = insert(:user)

      assert {:error, :not_found} =
               Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{
                 body: "sneaky"
               })
    end
  end

  describe "update_invoice_comment/3" do
    test "updates the body when user owns the comment", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      {:ok, comment} =
        Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "old"})

      assert {:ok, updated} = Invoices.update_invoice_comment(comment, user, %{body: "new"})
      assert updated.body == "new"
      assert updated.user.id == user.id
    end

    test "rejects empty body", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      {:ok, comment} =
        Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "old"})

      assert {:error, changeset} = Invoices.update_invoice_comment(comment, user, %{body: ""})
      assert errors_on(changeset).body
    end

    test "returns unauthorized when user does not own the comment", %{company: company} do
      invoice = insert(:invoice, company: company)
      author = insert(:user)
      other_user = insert(:user)

      {:ok, comment} =
        Invoices.create_invoice_comment(company.id, invoice.id, author.id, %{body: "old"})

      assert {:error, :unauthorized} =
               Invoices.update_invoice_comment(comment, other_user, %{body: "hacked"})

      # Verify body unchanged
      [unchanged] = Invoices.list_invoice_comments(company.id, invoice.id)
      assert unchanged.body == "old"
    end
  end

  describe "delete_invoice_comment/2" do
    test "deletes a comment when user owns it", %{company: company} do
      invoice = insert(:invoice, company: company)
      user = insert(:user)

      {:ok, comment} =
        Invoices.create_invoice_comment(company.id, invoice.id, user.id, %{body: "bye"})

      assert {:ok, _} = Invoices.delete_invoice_comment(comment, user)
      assert [] == Invoices.list_invoice_comments(company.id, invoice.id)
    end

    test "returns unauthorized when user does not own the comment", %{company: company} do
      invoice = insert(:invoice, company: company)
      author = insert(:user)
      other_user = insert(:user)

      {:ok, comment} =
        Invoices.create_invoice_comment(company.id, invoice.id, author.id, %{body: "mine"})

      assert {:error, :unauthorized} = Invoices.delete_invoice_comment(comment, other_user)

      # Verify comment still exists
      assert [_] = Invoices.list_invoice_comments(company.id, invoice.id)
    end
  end
end
