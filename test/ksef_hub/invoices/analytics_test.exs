defmodule KsefHub.Invoices.AnalyticsTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "count_by_type_and_status/1" do
    test "returns counts scoped to company", %{company: company} do
      insert(:invoice, type: :income, company: company)
      insert(:invoice, type: :expense, company: company)

      # Invoice in another company should not be counted
      other = insert(:company)
      insert(:invoice, type: :income, company: other)

      counts = Invoices.count_by_type_and_status(company.id)
      assert counts[{:income, :pending}] == 1
      assert counts[{:expense, :pending}] == 1
    end
  end

  describe "expense_monthly_totals/2" do
    test "returns monthly totals grouped by billing period", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("500.00")
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("300.00")
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-02-01],
        billing_date_to: ~D[2026-02-01],
        net_amount: Decimal.new("200.00")
      )

      result = Invoices.expense_monthly_totals(company.id)

      assert [jan, feb] = result
      assert jan.billing_date == ~D[2026-01-01]
      assert Decimal.equal?(jan.net_total, Decimal.new("800.00"))
      assert feb.billing_date == ~D[2026-02-01]
      assert Decimal.equal?(feb.net_total, Decimal.new("200.00"))
    end

    test "excludes invoices with nil billing_date_from", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: nil,
        billing_date_to: nil,
        net_amount: Decimal.new("100.00")
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("50.00")
      )

      result = Invoices.expense_monthly_totals(company.id)
      assert [row] = result
      assert Decimal.equal?(row.net_total, Decimal.new("50.00"))
    end

    test "excludes income invoices", %{company: company} do
      insert(:invoice,
        type: :income,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("1000.00")
      )

      assert [] == Invoices.expense_monthly_totals(company.id)
    end

    test "filters by billing_date range", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("100.00")
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-03-01],
        billing_date_to: ~D[2026-03-01],
        net_amount: Decimal.new("200.00")
      )

      result =
        Invoices.expense_monthly_totals(company.id, %{
          billing_date_from: ~D[2026-02-01],
          billing_date_to: ~D[2026-03-31]
        })

      assert [row] = result
      assert row.billing_date == ~D[2026-03-01]
    end

    test "filters by category_id", %{company: company} do
      category = insert(:category, company: company)

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        expense_category_id: category.id
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("200.00"),
        expense_category_id: nil
      )

      result = Invoices.expense_monthly_totals(company.id, %{expense_category_id: category.id})
      assert [row] = result
      assert Decimal.equal?(row.net_total, Decimal.new("100.00"))
    end

    test "does not double-count invoices matching multiple tags", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        tags: ["alpha", "beta"]
      )

      result = Invoices.expense_monthly_totals(company.id, %{tags: ["alpha", "beta"]})
      assert [row] = result
      assert Decimal.equal?(row.net_total, Decimal.new("100.00"))
    end

    test "allocates multi-month invoice across 2 months", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-02-01],
        net_amount: Decimal.new("100.00")
      )

      result = Invoices.expense_monthly_totals(company.id)
      assert [jan, feb] = result
      assert jan.billing_date == ~D[2026-01-01]
      assert feb.billing_date == ~D[2026-02-01]
      assert Decimal.equal?(jan.net_total, Decimal.new("50.00"))
      assert Decimal.equal?(feb.net_total, Decimal.new("50.00"))
    end

    test "combines single and multi-month invoices in same month", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-03-01],
        net_amount: Decimal.new("300.00")
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-02-01],
        billing_date_to: ~D[2026-02-01],
        net_amount: Decimal.new("50.00")
      )

      result = Invoices.expense_monthly_totals(company.id)
      assert length(result) == 3

      feb = Enum.find(result, &(&1.billing_date == ~D[2026-02-01]))
      # 100 (from 3-month) + 50 (from single) = 150
      assert Decimal.equal?(feb.net_total, Decimal.new("150.00"))
    end
  end

  describe "expense_by_category/2" do
    test "groups expense totals by category", %{company: company} do
      cat1 = insert(:category, company: company, name: "Office", emoji: "🏢")
      cat2 = insert(:category, company: company, name: "Travel", emoji: "✈️")

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("500.00"),
        expense_category_id: cat1.id
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("300.00"),
        expense_category_id: cat2.id
      )

      result = Invoices.expense_by_category(company.id)
      assert [first, second] = result
      assert first.category_name == "Office"
      assert Decimal.equal?(first.net_total, Decimal.new("500.00"))
      assert second.category_name == "Travel"
    end

    test "groups uncategorized invoices", %{company: company} do
      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        expense_category_id: nil
      )

      result = Invoices.expense_by_category(company.id)
      assert [row] = result
      assert row.category_name == "Uncategorized"
      assert row.emoji == nil
    end

    test "filters by billing_date range", %{company: company} do
      cat = insert(:category, company: company, name: "Office", emoji: "🏢")

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("100.00"),
        expense_category_id: cat.id
      )

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-03-01],
        billing_date_to: ~D[2026-03-01],
        net_amount: Decimal.new("200.00"),
        expense_category_id: cat.id
      )

      result =
        Invoices.expense_by_category(company.id, %{
          billing_date_from: ~D[2026-03-01]
        })

      assert [row] = result
      assert Decimal.equal?(row.net_total, Decimal.new("200.00"))
    end

    test "does not double-count invoices matching multiple tags", %{company: company} do
      cat = insert(:category, company: company, name: "Office", emoji: "🏢")

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-01-01],
        net_amount: Decimal.new("250.00"),
        expense_category_id: cat.id,
        tags: ["alpha", "beta"]
      )

      result = Invoices.expense_by_category(company.id, %{tags: ["alpha", "beta"]})
      assert [row] = result
      assert Decimal.equal?(row.net_total, Decimal.new("250.00"))
    end

    test "allocates multi-month invoice proportionally by category", %{company: company} do
      cat = insert(:category, company: company, name: "SaaS", emoji: "💻")

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: ~D[2026-01-01],
        billing_date_to: ~D[2026-03-01],
        net_amount: Decimal.new("300.00"),
        expense_category_id: cat.id
      )

      result = Invoices.expense_by_category(company.id)
      assert [row] = result
      assert row.category_name == "SaaS"
      # Full amount allocated (100/month x3 = 300)
      assert Decimal.equal?(row.net_total, Decimal.new("300.00"))
    end
  end

  describe "income_monthly_summary/1" do
    test "returns current and last month income totals", %{company: company} do
      current_month = Date.utc_today() |> Date.beginning_of_month()
      last_month = current_month |> Date.add(-1) |> Date.beginning_of_month()

      insert(:invoice,
        type: :income,
        company: company,
        billing_date_from: current_month,
        billing_date_to: current_month,
        net_amount: Decimal.new("1000.00")
      )

      insert(:invoice,
        type: :income,
        company: company,
        billing_date_from: last_month,
        billing_date_to: last_month,
        net_amount: Decimal.new("800.00")
      )

      result = Invoices.income_monthly_summary(company.id)
      assert Decimal.equal?(result.current_month, Decimal.new("1000.00"))
      assert Decimal.equal?(result.last_month, Decimal.new("800.00"))
    end

    test "returns zero for months with no data", %{company: company} do
      result = Invoices.income_monthly_summary(company.id)
      assert Decimal.equal?(result.current_month, Decimal.new(0))
      assert Decimal.equal?(result.last_month, Decimal.new(0))
    end

    test "excludes expense invoices", %{company: company} do
      current_month = Date.utc_today() |> Date.beginning_of_month()

      insert(:invoice,
        type: :expense,
        company: company,
        billing_date_from: current_month,
        billing_date_to: current_month,
        net_amount: Decimal.new("500.00")
      )

      result = Invoices.income_monthly_summary(company.id)
      assert Decimal.equal?(result.current_month, Decimal.new(0))
    end

    test "allocates multi-month invoice proportionally across current and last month", %{
      company: company
    } do
      current_month = Date.utc_today() |> Date.beginning_of_month()
      last_month = current_month |> Date.add(-1) |> Date.beginning_of_month()

      # Invoice spanning last month + current month
      insert(:invoice,
        type: :income,
        company: company,
        billing_date_from: last_month,
        billing_date_to: current_month,
        net_amount: Decimal.new("200.00")
      )

      result = Invoices.income_monthly_summary(company.id)
      assert Decimal.equal?(result.current_month, Decimal.new("100.00"))
      assert Decimal.equal?(result.last_month, Decimal.new("100.00"))
    end
  end
end
