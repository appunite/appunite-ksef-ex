defmodule KsefHub.Invoices.CategoriesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  describe "list_categories/1" do
    test "returns categories ordered by sort_order then identifier" do
      company = insert(:company)
      insert(:category, company: company, identifier: "b:second", sort_order: 1)
      insert(:category, company: company, identifier: "a:first", sort_order: 0)
      insert(:category, company: company, identifier: "c:third", sort_order: 1)

      categories = Invoices.list_categories(company.id)

      assert [%{identifier: "a:first"}, %{identifier: "b:second"}, %{identifier: "c:third"}] =
               categories
    end

    test "returns only categories for the given company" do
      company = insert(:company)
      other = insert(:company)
      insert(:category, company: company, identifier: "ops:mine")
      insert(:category, company: other, identifier: "ops:other")

      categories = Invoices.list_categories(company.id)

      assert length(categories) == 1
      assert hd(categories).identifier == "ops:mine"
    end

    test "returns empty list when no categories exist" do
      company = insert(:company)

      assert Invoices.list_categories(company.id) == []
    end
  end

  describe "get_category/2" do
    test "returns category by id scoped to company" do
      company = insert(:company)
      category = insert(:category, company: company, identifier: "ops:test")

      assert {:ok, found} = Invoices.get_category(company.id, category.id)
      assert found.id == category.id
    end

    test "returns error for category from different company" do
      company = insert(:company)
      other = insert(:company)
      category = insert(:category, company: other)

      assert {:error, :not_found} = Invoices.get_category(company.id, category.id)
    end

    test "returns error for non-existent id" do
      company = insert(:company)

      assert {:error, :not_found} = Invoices.get_category(company.id, Ecto.UUID.generate())
    end
  end

  describe "get_category!/2" do
    test "returns category by id" do
      company = insert(:company)
      category = insert(:category, company: company)

      assert Invoices.get_category!(company.id, category.id).id == category.id
    end

    test "raises for non-existent id" do
      company = insert(:company)

      assert_raise Ecto.NoResultsError, fn ->
        Invoices.get_category!(company.id, Ecto.UUID.generate())
      end
    end
  end

  describe "create_category/2" do
    test "creates a category with valid attrs" do
      company = insert(:company)

      assert {:ok, category} =
               Invoices.create_category(company.id, %{
                 identifier: "finance:invoices",
                 name: "Invoices",
                 emoji: "💰"
               })

      assert category.identifier == "finance:invoices"
      assert category.name == "Invoices"
      assert category.emoji == "💰"
      assert category.company_id == company.id
    end

    test "returns error for invalid identifier format" do
      company = insert(:company)

      assert {:error, changeset} =
               Invoices.create_category(company.id, %{identifier: "no-colon"})

      assert errors_on(changeset).identifier
    end

    test "returns error for missing identifier" do
      company = insert(:company)

      assert {:error, changeset} = Invoices.create_category(company.id, %{emoji: "📦"})
      assert errors_on(changeset).identifier
    end

    test "returns error for duplicate identifier within company" do
      company = insert(:company)
      insert(:category, company: company, identifier: "ops:duplicate")

      assert {:error, changeset} =
               Invoices.create_category(company.id, %{identifier: "ops:duplicate"})

      assert "has already been taken" in errors_on(changeset).identifier
    end

    test "allows same identifier in different companies" do
      company1 = insert(:company)
      company2 = insert(:company)
      insert(:category, company: company1, identifier: "ops:shared")

      assert {:ok, _} = Invoices.create_category(company2.id, %{identifier: "ops:shared"})
    end

    test "defaults sort_order to 0" do
      company = insert(:company)

      {:ok, category} = Invoices.create_category(company.id, %{identifier: "ops:default"})
      assert category.sort_order == 0
    end

    test "accepts examples field" do
      company = insert(:company)

      {:ok, category} =
        Invoices.create_category(company.id, %{
          identifier: "ops:test",
          examples: "Electric bills, water bills"
        })

      assert category.examples == "Electric bills, water bills"
    end
  end

  describe "update_category/2" do
    test "updates category attributes" do
      company = insert(:company)
      category = insert(:category, company: company, identifier: "ops:old")

      assert {:ok, updated} =
               Invoices.update_category(category, %{
                 identifier: "ops:new",
                 name: "New Name",
                 emoji: "🔥"
               })

      assert updated.identifier == "ops:new"
      assert updated.name == "New Name"
      assert updated.emoji == "🔥"
    end

    test "returns error for invalid update" do
      company = insert(:company)
      category = insert(:category, company: company)

      assert {:error, changeset} =
               Invoices.update_category(category, %{identifier: "bad-format"})

      assert errors_on(changeset).identifier
    end
  end

  describe "delete_category/1" do
    test "deletes a category" do
      company = insert(:company)
      category = insert(:category, company: company)

      assert {:ok, _} = Invoices.delete_category(category)
      assert {:error, :not_found} = Invoices.get_category(company.id, category.id)
    end

    test "nilifies category_id on associated invoices" do
      company = insert(:company)
      category = insert(:category, company: company)
      invoice = insert(:invoice, company: company, category_id: category.id)

      assert {:ok, _} = Invoices.delete_category(category)

      updated = KsefHub.Repo.get!(KsefHub.Invoices.Invoice, invoice.id)
      assert is_nil(updated.category_id)
    end
  end
end
