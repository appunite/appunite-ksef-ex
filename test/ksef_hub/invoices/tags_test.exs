defmodule KsefHub.Invoices.TagsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  describe "list_tags/2" do
    test "returns tags ordered by usage_count desc then name" do
      company = insert(:company)
      tag_a = insert(:tag, company: company, name: "alpha")
      tag_b = insert(:tag, company: company, name: "beta")
      _tag_c = insert(:tag, company: company, name: "gamma")

      invoice1 = insert(:invoice, company: company)
      invoice2 = insert(:invoice, company: company)

      insert(:invoice_tag, invoice: invoice1, tag: tag_b)
      insert(:invoice_tag, invoice: invoice2, tag: tag_b)
      insert(:invoice_tag, invoice: invoice1, tag: tag_a)

      tags = Invoices.list_tags(company.id)

      assert [
               %{name: "beta", usage_count: 2},
               %{name: "alpha", usage_count: 1},
               %{name: "gamma", usage_count: 0}
             ] =
               tags
    end

    test "returns only tags for the given company" do
      company = insert(:company)
      other = insert(:company)
      insert(:tag, company: company, name: "mine")
      insert(:tag, company: other, name: "other")

      tags = Invoices.list_tags(company.id)

      assert length(tags) == 1
      assert hd(tags).name == "mine"
    end

    test "filters by type when provided" do
      company = insert(:company)
      insert(:tag, company: company, name: "expense-tag", type: :expense)
      insert(:tag, company: company, name: "income-tag", type: :income)

      expense_tags = Invoices.list_tags(company.id, :expense)
      assert length(expense_tags) == 1
      assert hd(expense_tags).name == "expense-tag"

      income_tags = Invoices.list_tags(company.id, :income)
      assert length(income_tags) == 1
      assert hd(income_tags).name == "income-tag"

      all_tags = Invoices.list_tags(company.id)
      assert length(all_tags) == 2
    end
  end

  describe "get_tag/2" do
    test "returns tag by id scoped to company" do
      company = insert(:company)
      tag = insert(:tag, company: company)

      assert {:ok, found} = Invoices.get_tag(company.id, tag.id)
      assert found.id == tag.id
    end

    test "returns error for tag from different company" do
      company = insert(:company)
      other = insert(:company)
      tag = insert(:tag, company: other)

      assert {:error, :not_found} = Invoices.get_tag(company.id, tag.id)
    end
  end

  describe "get_tag!/2" do
    test "returns tag by id" do
      company = insert(:company)
      tag = insert(:tag, company: company)

      assert Invoices.get_tag!(company.id, tag.id).id == tag.id
    end

    test "raises for non-existent id" do
      company = insert(:company)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_tag!(company.id, Ecto.UUID.generate())
      end
    end
  end

  describe "create_tag/2" do
    test "creates a tag with valid attrs" do
      company = insert(:company)

      assert {:ok, tag} = Invoices.create_tag(company.id, %{name: "urgent"})
      assert tag.name == "urgent"
      assert tag.company_id == company.id
    end

    test "returns error for missing name" do
      company = insert(:company)

      assert {:error, changeset} = Invoices.create_tag(company.id, %{})
      assert errors_on(changeset).name
    end

    test "returns error for duplicate name within company and type" do
      company = insert(:company)
      insert(:tag, company: company, name: "duplicate", type: :expense)

      assert {:error, changeset} = Invoices.create_tag(company.id, %{name: "duplicate", type: :expense})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "allows same name in different companies" do
      company1 = insert(:company)
      company2 = insert(:company)
      insert(:tag, company: company1, name: "shared")

      assert {:ok, _} = Invoices.create_tag(company2.id, %{name: "shared"})
    end

    test "allows same name with different types in same company" do
      company = insert(:company)
      insert(:tag, company: company, name: "shared", type: :expense)

      assert {:ok, tag} = Invoices.create_tag(company.id, %{name: "shared", type: :income})
      assert tag.type == :income
    end

    test "creates tag with type" do
      company = insert(:company)

      assert {:ok, tag} = Invoices.create_tag(company.id, %{name: "income-tag", type: :income})
      assert tag.type == :income
    end

    test "defaults to expense type" do
      company = insert(:company)

      assert {:ok, tag} = Invoices.create_tag(company.id, %{name: "default-tag"})
      assert tag.type == :expense
    end
  end

  describe "update_tag/2" do
    test "updates tag attributes" do
      company = insert(:company)
      tag = insert(:tag, company: company, name: "old")

      assert {:ok, updated} = Invoices.update_tag(tag, %{name: "new"})
      assert updated.name == "new"
    end
  end

  describe "delete_tag/1" do
    test "deletes a tag and its join records" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      assert {:ok, _} = Invoices.delete_tag(tag)
      assert {:error, :not_found} = Invoices.get_tag(company.id, tag.id)

      # join records are cascade deleted
      assert KsefHub.Repo.all(KsefHub.Invoices.InvoiceTag) == []
    end
  end

  describe "set_invoice_category/2" do
    test "assigns a category to an expense invoice" do
      company = insert(:company)
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, type: :expense)

      assert {:ok, updated} = Invoices.set_invoice_category(invoice, category.id)
      assert updated.category_id == category.id
    end

    test "clears category when nil" do
      company = insert(:company)
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, type: :expense, category_id: category.id)

      assert {:ok, updated} = Invoices.set_invoice_category(invoice, nil)
      assert is_nil(updated.category_id)
    end

    test "returns error when invoice is income type" do
      company = insert(:company)
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, type: :income)

      assert {:error, :expense_only} = Invoices.set_invoice_category(invoice, category.id)
    end
  end

  describe "add_invoice_tag/2" do
    test "adds a tag to an invoice" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)

      assert {:ok, _} = Invoices.add_invoice_tag(invoice.id, tag.id)

      tags = Invoices.list_invoice_tags(invoice.id)
      assert length(tags) == 1
      assert hd(tags).id == tag.id
    end

    test "is idempotent for duplicate association" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      assert {:ok, _} = Invoices.add_invoice_tag(invoice.id, tag.id)
      assert length(Invoices.list_invoice_tags(invoice.id)) == 1
    end
  end

  describe "remove_invoice_tag/2" do
    test "removes a tag from an invoice" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      assert {:ok, _} = Invoices.remove_invoice_tag(invoice.id, tag.id)
      assert Invoices.list_invoice_tags(invoice.id) == []
    end

    test "returns error when association does not exist" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)

      assert {:error, :not_found} = Invoices.remove_invoice_tag(invoice.id, tag.id)
    end
  end

  describe "list_invoice_tags/1" do
    test "returns tags for an invoice ordered by name" do
      company = insert(:company)
      tag_b = insert(:tag, company: company, name: "bravo")
      tag_a = insert(:tag, company: company, name: "alpha")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag_b)
      insert(:invoice_tag, invoice: invoice, tag: tag_a)

      tags = Invoices.list_invoice_tags(invoice.id)

      assert [%{name: "alpha"}, %{name: "bravo"}] = tags
    end
  end

  describe "set_invoice_tags/2" do
    test "replaces all tags on an invoice" do
      company = insert(:company)
      tag1 = insert(:tag, company: company, name: "alpha")
      tag2 = insert(:tag, company: company, name: "beta")
      tag3 = insert(:tag, company: company, name: "gamma")
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag1)

      assert {:ok, tags} = Invoices.set_invoice_tags(invoice.id, [tag2.id, tag3.id])
      assert length(tags) == 2
      assert Enum.map(tags, & &1.name) |> Enum.sort() == ["beta", "gamma"]
    end

    test "clears all tags when given empty list" do
      company = insert(:company)
      tag = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)
      insert(:invoice_tag, invoice: invoice, tag: tag)

      assert {:ok, []} = Invoices.set_invoice_tags(invoice.id, [])
    end
  end

  describe "invoice filtering by category_id" do
    test "filters invoices by category_id" do
      company = insert(:company)
      category = insert(:category, company: company)
      insert(:invoice, company: company, category_id: category.id)
      insert(:invoice, company: company)

      invoices = Invoices.list_invoices(company.id, %{category_id: category.id})

      assert length(invoices) == 1
      assert hd(invoices).category_id == category.id
    end
  end

  describe "invoice filtering by tag_ids" do
    test "filters invoices by tag_ids" do
      company = insert(:company)
      tag1 = insert(:tag, company: company)
      tag2 = insert(:tag, company: company)
      invoice1 = insert(:invoice, company: company)
      invoice2 = insert(:invoice, company: company)
      insert(:invoice, company: company)

      insert(:invoice_tag, invoice: invoice1, tag: tag1)
      insert(:invoice_tag, invoice: invoice2, tag: tag2)

      invoices = Invoices.list_invoices(company.id, %{tag_ids: [tag1.id]})
      assert length(invoices) == 1
      assert hd(invoices).id == invoice1.id
    end

    test "returns distinct invoices when matching multiple tags" do
      company = insert(:company)
      tag1 = insert(:tag, company: company)
      tag2 = insert(:tag, company: company)
      invoice = insert(:invoice, company: company)

      insert(:invoice_tag, invoice: invoice, tag: tag1)
      insert(:invoice_tag, invoice: invoice, tag: tag2)

      invoices = Invoices.list_invoices(company.id, %{tag_ids: [tag1.id, tag2.id]})
      assert length(invoices) == 1
    end
  end
end
