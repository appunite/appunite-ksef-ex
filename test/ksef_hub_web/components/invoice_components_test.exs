defmodule KsefHubWeb.InvoiceComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHubWeb.InvoiceComponents

  describe "format_date/1" do
    test "returns dash for nil" do
      assert InvoiceComponents.format_date(nil) == "-"
    end

    test "formats a Date" do
      assert InvoiceComponents.format_date(~D[2025-03-15]) == "2025-03-15"
    end
  end

  describe "format_datetime/1" do
    test "returns dash for nil" do
      assert InvoiceComponents.format_datetime(nil) == "-"
    end

    test "formats a DateTime" do
      dt = ~U[2025-03-15 14:30:00Z]
      assert InvoiceComponents.format_datetime(dt) == "2025-03-15 14:30 UTC"
    end
  end

  describe "format_amount/1" do
    test "returns dash for nil" do
      assert InvoiceComponents.format_amount(nil) == "-"
    end

    test "formats a Decimal" do
      assert InvoiceComponents.format_amount(Decimal.new("1234.56")) == "1234.56"
    end

    test "formats an integer" do
      assert InvoiceComponents.format_amount(100) == "100"
    end

    test "formats a float" do
      assert InvoiceComponents.format_amount(99.99) == "99.99"
    end
  end

  describe "type_badge/1" do
    test "renders income badge with success style" do
      html = render_component(&InvoiceComponents.type_badge/1, type: "income")
      assert html =~ "badge-success"
      assert html =~ "income"
    end

    test "renders expense badge with warning style" do
      html = render_component(&InvoiceComponents.type_badge/1, type: "expense")
      assert html =~ "badge-warning"
      assert html =~ "expense"
    end
  end

  describe "status_badge/1" do
    test "renders pending badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: "pending")
      assert html =~ "badge-warning"
      assert html =~ "pending"
    end

    test "renders approved badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: "approved")
      assert html =~ "badge-success"
      assert html =~ "approved"
    end

    test "renders rejected badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: "rejected")
      assert html =~ "badge-error"
      assert html =~ "rejected"
    end
  end
end
