defmodule KsefHub.Invoices.ClassificationTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "cost line" do
    test "set_invoice_category auto-populates cost_line from category default", %{
      company: company
    } do
      category = insert(:category, company: company, default_cost_line: :growth)
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, updated} = Invoices.set_invoice_category(invoice, category.id)
      assert updated.cost_line == :growth
    end

    test "set_invoice_category preserves existing cost_line when category has no default", %{
      company: company
    } do
      category = insert(:category, company: company, default_cost_line: nil)
      invoice = insert(:invoice, company: company, type: :expense, cost_line: :heads)

      {:ok, updated} = Invoices.set_invoice_category(invoice, category.id)
      assert updated.cost_line == :heads
    end

    test "set_invoice_category does not clear cost_line when clearing category", %{
      company: company
    } do
      invoice = insert(:invoice, company: company, type: :expense, cost_line: :service)

      {:ok, updated} = Invoices.set_invoice_category(invoice, nil)
      assert updated.cost_line == :service
      assert updated.category_id == nil
    end

    test "set_invoice_cost_line sets cost_line independently on expense invoice", %{
      company: company
    } do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, updated} = Invoices.set_invoice_cost_line(invoice, :client_success)
      assert updated.cost_line == :client_success
    end

    test "set_invoice_cost_line clears cost_line with nil", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, cost_line: :growth)

      {:ok, updated} = Invoices.set_invoice_cost_line(invoice, nil)
      assert updated.cost_line == nil
    end

    test "set_invoice_cost_line returns error for income invoice", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      assert {:error, :expense_only} = Invoices.set_invoice_cost_line(invoice, :growth)
    end
  end

  describe "project tags" do
    test "set_invoice_project_tag sets tag on expense invoice", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)

      {:ok, updated} = Invoices.set_invoice_project_tag(invoice, "Project Alpha")
      assert updated.project_tag == "Project Alpha"
    end

    test "set_invoice_project_tag sets tag on income invoice", %{company: company} do
      invoice = insert(:invoice, company: company, type: :income)

      {:ok, updated} = Invoices.set_invoice_project_tag(invoice, "Project Beta")
      assert updated.project_tag == "Project Beta"
    end

    test "set_invoice_project_tag clears tag with nil", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense, project_tag: "Old Tag")

      {:ok, updated} = Invoices.set_invoice_project_tag(invoice, nil)
      assert is_nil(updated.project_tag)
    end

    test "set_invoice_project_tag validates max length", %{company: company} do
      invoice = insert(:invoice, company: company, type: :expense)
      long_tag = String.duplicate("a", 256)

      assert {:error, changeset} = Invoices.set_invoice_project_tag(invoice, long_tag)
      assert errors_on(changeset).project_tag
    end

    test "list_project_tags returns distinct values ordered by most recent", %{company: company} do
      older = insert(:invoice, company: company, type: :expense, project_tag: "Older")

      # Ensure the second invoice has a later inserted_at
      newer = insert(:invoice, company: company, type: :income, project_tag: "Newer")

      # Force ordering by updating inserted_at directly
      import Ecto.Query

      from(i in KsefHub.Invoices.Invoice, where: i.id == ^older.id)
      |> KsefHub.Repo.update_all(
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -3600, :second)]
      )

      from(i in KsefHub.Invoices.Invoice, where: i.id == ^newer.id)
      |> KsefHub.Repo.update_all(set: [inserted_at: DateTime.utc_now()])

      tags = Invoices.list_project_tags(company.id)
      assert tags == ["Newer", "Older"]
    end

    test "list_project_tags returns empty list when none set", %{company: company} do
      insert(:invoice, company: company, type: :expense, project_tag: nil)

      assert Invoices.list_project_tags(company.id) == []
    end

    test "list_project_tags deduplicates values", %{company: company} do
      insert(:invoice, company: company, type: :expense, project_tag: "Same")
      insert(:invoice, company: company, type: :income, project_tag: "Same")

      tags = Invoices.list_project_tags(company.id)
      assert tags == ["Same"]
    end
  end
end
