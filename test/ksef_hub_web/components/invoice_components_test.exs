defmodule KsefHubWeb.InvoiceComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias KsefHub.Invoices.Invoice
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

    test "formats a Decimal with thousands separator" do
      assert InvoiceComponents.format_amount(Decimal.new("1234.56")) == "1\u00A0234.56"
    end

    test "formats a small Decimal without separator" do
      assert InvoiceComponents.format_amount(Decimal.new("99.99")) == "99.99"
    end

    test "formats an integer with .00 suffix" do
      assert InvoiceComponents.format_amount(100) == "100.00"
    end

    test "formats a float" do
      assert InvoiceComponents.format_amount(99.99) == "99.99"
    end

    test "returns dash for unexpected type" do
      assert InvoiceComponents.format_amount("not a number") == "-"
    end

    test "formats 7-digit amount with two separators" do
      assert InvoiceComponents.format_amount(Decimal.new("1234567.89")) ==
               "1\u00A0234\u00A0567.89"
    end

    test "formats negative amount preserving sign" do
      assert InvoiceComponents.format_amount(Decimal.new("-1234.56")) == "-1\u00A0234.56"
    end

    test "formats amount under 1000 with no separator" do
      assert InvoiceComponents.format_amount(Decimal.new("999.00")) == "999.00"
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
      assert html =~ "badge-warning-text"
      assert html =~ "expense"
    end

    test "renders unknown type with base badge only" do
      html = render_component(&InvoiceComponents.type_badge/1, type: :unknown)
      assert html =~ "rounded-md"
      assert html =~ "unknown"
      refute html =~ "text-success"
      refute html =~ "badge-warning-text"
    end
  end

  describe "invoice_kind_badge/1" do
    test "renders muted badge for :vat" do
      html = render_component(&InvoiceComponents.invoice_kind_badge/1, kind: :vat)
      assert html =~ "VAT"
      assert html =~ "text-muted"
    end

    test "renders nothing for nil" do
      html = render_component(&InvoiceComponents.invoice_kind_badge/1, kind: nil)
      assert html == ""
    end

    test "renders lowercase purple badge for :correction" do
      html = render_component(&InvoiceComponents.invoice_kind_badge/1, kind: :correction)
      assert html =~ "text-purple"
      assert html =~ "correction"
    end

    test "renders lowercase purple badge for :advance_correction" do
      html = render_component(&InvoiceComponents.invoice_kind_badge/1, kind: :advance_correction)
      assert html =~ "text-purple"
      assert html =~ "advance correction"
    end

    test "renders lowercase purple badge for :settlement_correction" do
      html =
        render_component(&InvoiceComponents.invoice_kind_badge/1, kind: :settlement_correction)

      assert html =~ "text-purple"
      assert html =~ "settlement correction"
    end

    test "renders lowercase info badge for :advance" do
      html = render_component(&InvoiceComponents.invoice_kind_badge/1, kind: :advance)
      assert html =~ "text-info"
      assert html =~ "advance"
      refute html =~ "text-purple"
    end
  end

  describe "correction_details/1" do
    test "renders nothing for a non-correction invoice" do
      html =
        render_component(&InvoiceComponents.correction_details/1,
          invoice: %Invoice{invoice_kind: :vat},
          company_id: "company-1"
        )

      assert html == ""
    end

    test "renders the correction panel with visible fields" do
      invoice = %Invoice{
        invoice_kind: :correction,
        corrected_invoice_number: "FV/2026/001",
        corrected_invoice_ksef_number: "1234567890-20260101-ABCD-01",
        corrected_invoice_date: ~D[2026-01-01],
        correction_reason: "Błąd rachunkowy",
        correction_type: 1,
        correction_period_from: nil,
        correction_period_to: nil,
        corrects_invoice_id: nil
      }

      html =
        render_component(&InvoiceComponents.correction_details/1,
          invoice: invoice,
          company_id: "company-1"
        )

      assert html =~ "correction-details"
      assert html =~ "FV/2026/001"
      assert html =~ "1234567890-20260101-ABCD-01"
      assert html =~ "2026-01-01"
      assert html =~ "Błąd rachunkowy"
      assert html =~ "Skutek na dacie faktury pierwotnej"
    end

    test "renders a link to the corrected invoice when corrects_invoice_id is set" do
      invoice = %Invoice{
        invoice_kind: :correction,
        corrected_invoice_number: "FV/2026/001",
        corrected_invoice_ksef_number: nil,
        corrected_invoice_date: nil,
        correction_reason: nil,
        correction_type: nil,
        correction_period_from: nil,
        correction_period_to: nil,
        corrects_invoice_id: "abc-123"
      }

      html =
        render_component(&InvoiceComponents.correction_details/1,
          invoice: invoice,
          company_id: "company-1"
        )

      assert html =~ ~r{href="[^"]*abc-123"}
      assert html =~ "FV/2026/001"
    end

    test "renders nothing for advance invoice (non-correction kind)" do
      html =
        render_component(&InvoiceComponents.correction_details/1,
          invoice: %Invoice{invoice_kind: :advance},
          company_id: "company-1"
        )

      assert html == ""
    end
  end

  describe "related_invoices/1" do
    test "renders nothing when there are no related invoices" do
      html =
        render_component(&InvoiceComponents.related_invoices/1,
          invoice: %Invoice{},
          company_id: "company-1"
        )

      assert html == ""
    end

    test "renders the original invoice for a correction" do
      original = %Invoice{
        id: "orig-1",
        invoice_number: "FV/2026/001",
        issue_date: ~D[2026-01-01],
        invoice_kind: :vat
      }

      invoice = %Invoice{invoice_kind: :correction, corrects_invoice: original}

      html =
        render_component(&InvoiceComponents.related_invoices/1,
          invoice: invoice,
          company_id: "company-1"
        )

      assert html =~ "related-invoices"
      assert html =~ "Original"
      assert html =~ "FV/2026/001"
    end

    test "renders correction invoices for an original" do
      correction = %Invoice{
        id: "corr-1",
        invoice_number: "KOR/2026/001",
        issue_date: ~D[2026-02-01],
        invoice_kind: :correction
      }

      invoice = %Invoice{invoice_kind: :vat, corrections: [correction]}

      html =
        render_component(&InvoiceComponents.related_invoices/1,
          invoice: invoice,
          company_id: "company-1"
        )

      assert html =~ "related-invoices"
      assert html =~ "Correction"
      assert html =~ "KOR/2026/001"
    end
  end

  describe "status_badge/1" do
    test "renders pending badge" do
      html = render_component(&InvoiceComponents.status_badge/1, status: :pending)
      assert html =~ "badge-warning-text"
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
