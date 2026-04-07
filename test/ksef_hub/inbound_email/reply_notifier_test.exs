defmodule KsefHub.InboundEmail.ReplyNotifierTest do
  @moduledoc "Tests for ReplyNotifier: success, needs-review, and rejection email building."

  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.ReplyNotifier

  @sender "user@appunite.com"

  @full_invoice %{
    id: "abc-123",
    company_id: "company-456",
    invoice_number: "FV/2026/001",
    seller_name: "Seller Sp. z o.o.",
    seller_nip: "1234567890",
    buyer_name: "Buyer Corp",
    buyer_nip: "9876543210",
    gross_amount: Decimal.new("1234.56"),
    currency: "EUR",
    billing_date_from: ~D[2026-03-01],
    billing_date_to: ~D[2026-03-01],
    category: %{name: "Office Supplies", emoji: "📎"},
    tags: ["recurring", "monthly"],
    prediction_category_name: "Office Supplies",
    prediction_category_confidence: 0.92,
    prediction_tag_name: "recurring",
    prediction_tag_confidence: 0.85
  }

  describe "success/3" do
    test "builds email with full invoice details" do
      email = ReplyNotifier.success(@sender, @full_invoice)
      assert email.to == [{@sender, @sender}]
      assert email.subject =~ "FV/2026/001"
      assert email.text_body =~ "added and is ready"

      # Invoice details
      assert email.text_body =~ "Invoice number: FV/2026/001"
      assert email.text_body =~ "Seller: Seller Sp. z o.o. (NIP: 1234567890)"
      assert email.text_body =~ "Buyer: Buyer Corp (NIP: 9876543210)"
      assert email.text_body =~ "Amount: 1234.56 EUR"
      assert email.text_body =~ "Billing period: 2026-03-01 — 2026-03-01"
      assert email.text_body =~ "Category: 📎 Office Supplies (92% confidence)"
      assert email.text_body =~ "Tags: recurring, monthly"

      # URL
      assert email.text_body =~ "/c/company-456/invoices/abc-123"
    end

    test "omits nil fields from details" do
      invoice = %{
        id: "abc",
        company_id: "c1",
        invoice_number: "FV/1",
        seller_name: "Seller",
        seller_nip: nil,
        buyer_name: nil,
        buyer_nip: nil,
        gross_amount: nil,
        currency: nil,
        billing_date_from: nil,
        billing_date_to: nil,
        category: nil,
        tags: [],
        prediction_category_name: nil,
        prediction_category_confidence: nil,
        prediction_tag_name: nil,
        prediction_tag_confidence: nil
      }

      email = ReplyNotifier.success(@sender, invoice)
      assert email.text_body =~ "Invoice number: FV/1"
      assert email.text_body =~ "Seller: Seller"
      refute email.text_body =~ "Buyer:"
      refute email.text_body =~ "Amount:"
      refute email.text_body =~ "Billing period:"
      refute email.text_body =~ "Category:"
      refute email.text_body =~ "Tags:"
    end

    test "falls back to prediction_category_name when category not preloaded" do
      invoice = %{
        id: "abc",
        company_id: "c1",
        invoice_number: nil,
        seller_name: nil,
        seller_nip: nil,
        buyer_name: nil,
        buyer_nip: nil,
        gross_amount: nil,
        currency: nil,
        billing_date_from: nil,
        billing_date_to: nil,
        category: nil,
        tags: [],
        prediction_category_name: "Travel",
        prediction_category_confidence: nil,
        prediction_tag_name: "one-time",
        prediction_tag_confidence: 0.78
      }

      email = ReplyNotifier.success(@sender, invoice)
      # Category without confidence (nil confidence)
      assert email.text_body =~ "Category: Travel"
      refute email.text_body =~ "Category: Travel ("
      # Falls back to prediction tag when tags list is empty
      assert email.text_body =~ "Tags: one-time (78% confidence)"
    end

    test "formats amount with default PLN when currency is nil" do
      invoice = %{
        id: "abc",
        company_id: "c1",
        invoice_number: nil,
        seller_name: nil,
        seller_nip: nil,
        buyer_name: nil,
        buyer_nip: nil,
        gross_amount: Decimal.new("500.00"),
        currency: nil,
        billing_date_from: nil,
        billing_date_to: nil,
        category: nil,
        tags: [],
        prediction_category_name: nil,
        prediction_category_confidence: nil,
        prediction_tag_name: nil,
        prediction_tag_confidence: nil
      }

      email = ReplyNotifier.success(@sender, invoice)
      assert email.text_body =~ "Amount: 500.00 PLN"
    end

    test "works with map lacking optional keys" do
      invoice = %{id: "abc", company_id: "c1"}
      email = ReplyNotifier.success(@sender, invoice)
      assert email.text_body =~ "added and is ready"
    end

    test "includes CC when configured as list of tuples" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}

      cc_list = [{"Alice", "alice@co.com"}, {"bob@co.com", "bob@co.com"}]
      email = ReplyNotifier.success(@sender, invoice, cc: cc_list)
      assert email.cc == cc_list
    end

    test "omits CC when list is empty" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}
      email = ReplyNotifier.success(@sender, invoice, cc: [])
      assert email.cc == []
    end

    test "sets In-Reply-To and References headers when in_reply_to is provided" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}
      msg_id = "<original-msg-id@mailgun.org>"
      email = ReplyNotifier.success(@sender, invoice, in_reply_to: msg_id)

      assert email.headers["In-Reply-To"] == msg_id
      assert email.headers["References"] == msg_id
    end

    test "normalizes bare message-id by adding angle brackets" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}
      email = ReplyNotifier.success(@sender, invoice, in_reply_to: "msg-id@mailgun.org")

      assert email.headers["In-Reply-To"] == "<msg-id@mailgun.org>"
      assert email.headers["References"] == "<msg-id@mailgun.org>"
    end

    test "rejects malformed bracket message-ids" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}

      for malformed <- ["<msg-id", "msg-id>"] do
        email = ReplyNotifier.success(@sender, invoice, in_reply_to: malformed)
        assert email.headers == %{}, "expected no headers for #{inspect(malformed)}"
      end
    end

    test "uses Re: original_subject for threading when provided" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}

      email =
        ReplyNotifier.success(@sender, invoice, original_subject: "Invoice for February 2026")

      assert email.subject == "Re: Invoice for February 2026"
    end

    test "omits threading headers when in_reply_to is not provided" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}
      email = ReplyNotifier.success(@sender, invoice)

      assert email.headers == %{}
    end

    test "omits threading headers when in_reply_to contains control characters" do
      invoice = %{id: "abc", company_id: "c1", invoice_number: "FV/1", seller_name: "Seller"}

      for malformed <- ["<msg\r\nBcc: evil@hacker.com>", "<msg\nid>", "<msg\0id>"] do
        email = ReplyNotifier.success(@sender, invoice, in_reply_to: malformed)
        assert email.headers == %{}, "expected no headers for #{inspect(malformed)}"
      end
    end
  end

  describe "needs_review/3" do
    test "builds email for needs-review invoice with extracted details" do
      invoice = %{
        id: "abc-123",
        company_id: "company-456",
        invoice_number: "FV/2026/005",
        seller_name: "Vendor LLC",
        seller_nip: "5555555555",
        buyer_name: nil,
        buyer_nip: nil,
        gross_amount: nil,
        currency: nil,
        billing_date_from: nil,
        billing_date_to: nil,
        category: nil,
        tags: [],
        prediction_category_name: nil,
        prediction_category_confidence: nil,
        prediction_tag_name: nil,
        prediction_tag_confidence: nil
      }

      email = ReplyNotifier.needs_review(@sender, invoice)
      assert email.text_body =~ "needs human review"
      assert email.text_body =~ "Invoice number: FV/2026/005"
      assert email.text_body =~ "Seller: Vendor LLC (NIP: 5555555555)"
      assert email.text_body =~ "Missing fields: buyer, amount"
      assert email.text_body =~ "/c/company-456/invoices/abc-123"
    end

    test "no missing fields section when all required fields present" do
      invoice = %{
        id: "abc-123",
        company_id: "company-456",
        invoice_number: "FV/1",
        seller_name: "Seller",
        seller_nip: nil,
        buyer_name: "Buyer",
        buyer_nip: nil,
        gross_amount: Decimal.new("100"),
        currency: "PLN",
        billing_date_from: nil,
        billing_date_to: nil,
        category: nil,
        tags: [],
        prediction_category_name: nil,
        prediction_category_confidence: nil,
        prediction_tag_name: nil,
        prediction_tag_confidence: nil
      }

      email = ReplyNotifier.needs_review(@sender, invoice)
      refute email.text_body =~ "Missing fields"
    end

    test "works with minimal map" do
      invoice = %{id: "abc-123", company_id: "company-456"}
      email = ReplyNotifier.needs_review(@sender, invoice)
      assert email.text_body =~ "needs human review"
      assert email.text_body =~ "Missing fields: invoice number, seller, buyer, amount"
    end
  end

  describe "error/3" do
    test "builds error email for processing failure" do
      email = ReplyNotifier.error(@sender, :some_reason)
      assert email.to == [{@sender, @sender}]
      assert email.subject =~ "processing failed"
      assert email.text_body =~ "system error"
    end

    test "includes changeset error details" do
      changeset = %Ecto.Changeset{
        errors: [seller_nip: {"must be a 10-digit NIP", [validation: :format]}],
        valid?: false
      }

      email = ReplyNotifier.error(@sender, changeset)
      assert email.text_body =~ "seller_nip"
    end
  end

  describe "nip_warning/4" do
    test "builds NIP warning email for income_not_allowed" do
      invoice = %{id: "abc-123", company_id: "company-456"}

      email =
        ReplyNotifier.nip_warning(@sender, invoice, :income_not_allowed,
          company_name: "Acme",
          nip: "1234567890"
        )

      assert email.to == [{@sender, @sender}]
      assert email.subject =~ "NIP warning"
      assert email.text_body =~ "income invoice"
      assert email.text_body =~ "Acme"
    end

    test "builds NIP warning email for nip_mismatch" do
      invoice = %{id: "abc-123", company_id: "company-456"}

      email =
        ReplyNotifier.nip_warning(@sender, invoice, :nip_mismatch,
          company_name: "Acme",
          nip: "1234567890"
        )

      assert email.text_body =~ "doesn't match"
      assert email.text_body =~ "1234567890"
    end

    test "includes invoice URL with company_id" do
      invoice = %{id: "abc-123", company_id: "company-456"}
      email = ReplyNotifier.nip_warning(@sender, invoice, :income_not_allowed)
      assert email.text_body =~ "/c/company-456/invoices/abc-123"
    end
  end

  describe "rejection/3" do
    test "builds email for income_not_allowed rejection" do
      email = ReplyNotifier.rejection(@sender, :income_not_allowed)
      assert email.text_body =~ "income invoice"
      assert email.text_body =~ "seller NIP"
    end

    test "builds email for nip_mismatch rejection" do
      email =
        ReplyNotifier.rejection(@sender, :nip_mismatch, company_name: "Acme", nip: "1234567890")

      assert email.text_body =~ "doesn't match"
      assert email.text_body =~ "Acme"
      assert email.text_body =~ "1234567890"
    end

    test "builds email for no_attachment rejection" do
      email = ReplyNotifier.rejection(@sender, :no_attachment)
      assert email.text_body =~ "No PDF attachment"
    end

    test "builds email for multiple_attachments rejection" do
      email = ReplyNotifier.rejection(@sender, :multiple_attachments)
      assert email.text_body =~ "Multiple attachments"
    end

    test "builds email for non_pdf rejection" do
      email = ReplyNotifier.rejection(@sender, :non_pdf, filename: "invoice.docx")
      assert email.text_body =~ "invoice.docx"
      assert email.text_body =~ "not a PDF"
    end
  end
end
