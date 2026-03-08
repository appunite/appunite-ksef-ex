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

    test "returns dash for unexpected type" do
      assert InvoiceComponents.format_amount("not a number") == "-"
    end
  end

  describe "type_badge/1" do
    test "renders income badge with success style" do
      html = render_component(&InvoiceComponents.type_badge/1, type: :income)
      assert html =~ "text-success"
      assert html =~ "income"
    end

    test "renders expense badge with warning style" do
      html = render_component(&InvoiceComponents.type_badge/1, type: :expense)
      assert html =~ "text-warning"
      assert html =~ "expense"
    end

    test "renders unknown type with base badge only" do
      html = render_component(&InvoiceComponents.type_badge/1, type: :unknown)
      assert html =~ "rounded-md"
      assert html =~ "unknown"
      refute html =~ "text-success"
      refute html =~ "text-warning"
    end
  end

  describe "added_by_label/1" do
    test "returns KSeF label for ksef source" do
      assert InvoiceComponents.added_by_label(%{source: :ksef}) == "KSeF (automatic sync)"
    end

    test "returns email sender when inbound_email is loaded" do
      assert InvoiceComponents.added_by_label(%{
               source: :email,
               inbound_email: %{sender: "sender@example.com"}
             }) == "sender@example.com (email)"
    end

    test "returns Email when inbound_email is nil" do
      assert InvoiceComponents.added_by_label(%{source: :email, inbound_email: nil}) == "Email"
    end

    test "returns user name with source for manual invoice" do
      assert InvoiceComponents.added_by_label(%{
               source: :manual,
               created_by: %{name: "Jan Kowalski", email: "jan@example.com"}
             }) == "Jan Kowalski (manual)"
    end

    test "returns user name with source for pdf_upload" do
      assert InvoiceComponents.added_by_label(%{
               source: :pdf_upload,
               created_by: %{name: "Jan Kowalski", email: "jan@example.com"}
             }) == "Jan Kowalski (PDF upload)"
    end

    test "falls back to email when user name is empty" do
      assert InvoiceComponents.added_by_label(%{
               source: :manual,
               created_by: %{name: "", email: "jan@example.com"}
             }) == "jan@example.com (manual)"
    end

    test "falls back to email when user name is nil" do
      assert InvoiceComponents.added_by_label(%{
               source: :manual,
               created_by: %{name: nil, email: "jan@example.com"}
             }) == "jan@example.com (manual)"
    end

    test "falls back to source label when no creator" do
      assert InvoiceComponents.added_by_label(%{source: :manual, created_by: nil}) == "manual"
    end

    test "falls back to source label when created_by is not loaded" do
      assert InvoiceComponents.added_by_label(%{source: :pdf_upload}) == "PDF upload"
    end
  end

  describe "status_badge/1" do
    test "renders pending badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: :pending)
      assert html =~ "text-warning"
      assert html =~ "pending"
    end

    test "renders approved badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: :approved)
      assert html =~ "text-success"
      assert html =~ "approved"
    end

    test "renders rejected badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: :rejected)
      assert html =~ "text-error"
      assert html =~ "rejected"
    end

    test "renders unknown status with base badge only" do
      html = render_component(&InvoiceComponents.status_badge/1, status: :cancelled)
      assert html =~ "rounded-md"
      assert html =~ "cancelled"
      refute html =~ "text-warning"
      refute html =~ "text-success"
      refute html =~ "text-error"
    end
  end
end
