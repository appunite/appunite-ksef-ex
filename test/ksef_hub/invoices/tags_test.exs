defmodule KsefHub.Invoices.TagsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "set_invoice_tags/2" do
    test "sets tags on an invoice", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, ["alpha", "beta"])
      assert updated.tags == ["alpha", "beta"]
    end

    test "replaces existing tags", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["old"])

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, ["new"])
      assert updated.tags == ["new"]
    end

    test "clears tags with empty list", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["alpha"])

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, [])
      assert updated.tags == []
    end

    test "trims whitespace", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, ["  alpha  ", "beta "])
      assert updated.tags == ["alpha", "beta"]
    end

    test "rejects blank strings", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, ["alpha", "", "  ", "beta"])
      assert updated.tags == ["alpha", "beta"]
    end

    test "deduplicates tags", %{company: company} do
      invoice = insert(:invoice, company: company)

      assert {:ok, updated} = Invoices.set_invoice_tags(invoice, ["alpha", "alpha", "beta"])
      assert updated.tags == ["alpha", "beta"]
    end

    test "rejects more than 50 tags", %{company: company} do
      invoice = insert(:invoice, company: company)
      tags = Enum.map(1..51, &"tag-#{&1}")

      assert {:error, changeset} = Invoices.set_invoice_tags(invoice, tags)
      assert errors_on(changeset).tags != []
    end

    test "rejects tags longer than 100 characters", %{company: company} do
      invoice = insert(:invoice, company: company)
      long_tag = String.duplicate("a", 101)

      assert {:error, changeset} = Invoices.set_invoice_tags(invoice, [long_tag])
      assert errors_on(changeset).tags != []
    end
  end

  describe "add_invoice_tag/2" do
    test "adds a tag to an invoice", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["existing"])

      assert {:ok, updated} = Invoices.add_invoice_tag(invoice, "new")
      assert "new" in updated.tags
      assert "existing" in updated.tags
    end

    test "is idempotent for existing tags", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["existing"])

      assert {:ok, returned} = Invoices.add_invoice_tag(invoice, "existing")
      assert returned.id == invoice.id
      assert returned.tags == ["existing"]
    end

    test "trims whitespace", %{company: company} do
      invoice = insert(:invoice, company: company, tags: [])

      assert {:ok, updated} = Invoices.add_invoice_tag(invoice, "  spaced  ")
      assert updated.tags == ["spaced"]
    end

    test "no-ops for blank string", %{company: company} do
      invoice = insert(:invoice, company: company, tags: ["existing"])

      assert {:ok, returned} = Invoices.add_invoice_tag(invoice, "  ")
      assert returned.tags == ["existing"]
    end
  end

  describe "list_distinct_tags/2" do
    test "returns distinct tags across invoices", %{company: company} do
      insert(:invoice, company: company, type: :expense, tags: ["alpha", "beta"])
      insert(:invoice, company: company, type: :expense, tags: ["beta", "gamma"])

      result = Invoices.list_distinct_tags(company.id)
      assert Enum.sort(result) == ["alpha", "beta", "gamma"]
    end

    test "filters by invoice type", %{company: company} do
      insert(:invoice, company: company, type: :expense, tags: ["expense-tag"])
      insert(:invoice, company: company, type: :income, tags: ["income-tag"])

      assert Invoices.list_distinct_tags(company.id, :expense) == ["expense-tag"]
      assert Invoices.list_distinct_tags(company.id, :income) == ["income-tag"]
    end

    test "returns empty list when no tags exist", %{company: company} do
      insert(:invoice, company: company, tags: [])

      assert Invoices.list_distinct_tags(company.id) == []
    end

    test "scoped to company", %{company: company} do
      other = insert(:company)
      insert(:invoice, company: company, tags: ["mine"])
      insert(:invoice, company: other, tags: ["theirs"])

      assert Invoices.list_distinct_tags(company.id) == ["mine"]
    end

    test "orders by most recently used", %{company: company} do
      now = NaiveDateTime.utc_now()
      earlier = NaiveDateTime.add(now, -60)

      insert(:invoice, company: company, tags: ["old-tag"], updated_at: earlier)
      insert(:invoice, company: company, tags: ["recent-tag"], updated_at: now)

      assert Invoices.list_distinct_tags(company.id) == ["recent-tag", "old-tag"]
    end
  end
end
