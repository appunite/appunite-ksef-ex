defmodule KsefHub.InboundEmail.ReplyNotifierTest do
  @moduledoc "Tests for ReplyNotifier: success, needs-review, and rejection email building."

  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.ReplyNotifier

  @sender "user@appunite.com"

  describe "success/3" do
    test "builds email for successful invoice creation" do
      invoice = %{
        id: "abc-123",
        company_id: "company-456",
        invoice_number: "FV/2026/001",
        seller_name: "Seller Sp. z o.o."
      }

      email = ReplyNotifier.success(@sender, invoice)
      assert email.to == [{@sender, @sender}]
      assert email.subject =~ "FV/2026/001"
      assert email.text_body =~ "added and is ready"
      assert email.text_body =~ "FV/2026/001"
      assert email.text_body =~ "/c/company-456/invoices/abc-123"
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
    test "builds email for needs-review invoice" do
      invoice = %{id: "abc-123", company_id: "company-456"}
      email = ReplyNotifier.needs_review(@sender, invoice)
      assert email.text_body =~ "needs human review"
      assert email.text_body =~ "/c/company-456/invoices/abc-123"
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
