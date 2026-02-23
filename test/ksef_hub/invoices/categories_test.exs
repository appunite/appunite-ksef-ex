defmodule KsefHub.Invoices.CategoriesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  describe "list_categories/1" do
    test "returns categories ordered by sort_order then name" do
      company = insert(:company)
      insert(:category, company: company, name: "b:second", sort_order: 1)
      insert(:category, company: company, name: "a:first", sort_order: 0)
      insert(:category, company: company, name: "c:third", sort_order: 1)

      categories = Invoices.list_categories(company.id)

      assert [%{name: "a:first"}, %{name: "b:second"}, %{name: "c:third"}] = categories
    end

    test "returns only categories for the given company" do
      company = insert(:company)
      other = insert(:company)
      insert(:category, company: company, name: "ops:mine")
      insert(:category, company: other, name: "ops:other")

      categories = Invoices.list_categories(company.id)

      assert length(categories) == 1
      assert hd(categories).name == "ops:mine"
    end

    test "returns empty list when no categories exist" do
      company = insert(:company)

      assert Invoices.list_categories(company.id) == []
    end
  end

  describe "get_category/2" do
    test "returns category by id scoped to company" do
      company = insert(:company)
      category = insert(:category, company: company, name: "ops:test")

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
               Invoices.create_category(company.id, %{name: "finance:invoices", emoji: "💰"})

      assert category.name == "finance:invoices"
      assert category.emoji == "💰"
      assert category.company_id == company.id
    end

    test "returns error for invalid name format" do
      company = insert(:company)

      assert {:error, changeset} = Invoices.create_category(company.id, %{name: "no-colon"})
      assert errors_on(changeset).name
    end

    test "returns error for missing name" do
      company = insert(:company)

      assert {:error, changeset} = Invoices.create_category(company.id, %{emoji: "📦"})
      assert errors_on(changeset).name
    end

    test "returns error for duplicate name within company" do
      company = insert(:company)
      insert(:category, company: company, name: "ops:duplicate")

      assert {:error, changeset} = Invoices.create_category(company.id, %{name: "ops:duplicate"})
      assert errors_on(changeset).company_id
    end

    test "allows same name in different companies" do
      company1 = insert(:company)
      company2 = insert(:company)
      insert(:category, company: company1, name: "ops:shared")

      assert {:ok, _} = Invoices.create_category(company2.id, %{name: "ops:shared"})
    end

    test "defaults sort_order to 0" do
      company = insert(:company)

      {:ok, category} = Invoices.create_category(company.id, %{name: "ops:default"})
      assert category.sort_order == 0
    end
  end

  describe "update_category/2" do
    test "updates category attributes" do
      company = insert(:company)
      category = insert(:category, company: company, name: "ops:old")

      assert {:ok, updated} =
               Invoices.update_category(category, %{name: "ops:new", emoji: "🔥"})

      assert updated.name == "ops:new"
      assert updated.emoji == "🔥"
    end

    test "returns error for invalid update" do
      company = insert(:company)
      category = insert(:category, company: company)

      assert {:error, changeset} = Invoices.update_category(category, %{name: "bad-format"})
      assert errors_on(changeset).name
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
