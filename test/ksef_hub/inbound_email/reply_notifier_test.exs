defmodule KsefHub.InboundEmail.ReplyNotifierTest do
  @moduledoc "Tests for ReplyNotifier: success, needs-review, and rejection email building."

  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.ReplyNotifier

  @sender "user@appunite.com"

  describe "success/3" do
    test "builds email for successful invoice creation" do
      invoice = %{
        id: "abc-123",
        invoice_number: "FV/2026/001",
        seller_name: "Seller Sp. z o.o."
      }

      email = ReplyNotifier.success(@sender, invoice)
      assert email.to == [{@sender, @sender}]
      assert email.subject =~ "FV/2026/001"
      assert email.text_body =~ "added and is ready"
      assert email.text_body =~ "FV/2026/001"
    end

    test "includes CC when configured" do
      invoice = %{id: "abc", invoice_number: "FV/1", seller_name: "Seller"}
      email = ReplyNotifier.success(@sender, invoice, cc: "team@appunite.com")
      assert email.cc == [{"team@appunite.com", "team@appunite.com"}]
    end

    test "sets In-Reply-To and References headers when in_reply_to is provided" do
      invoice = %{id: "abc", invoice_number: "FV/1", seller_name: "Seller"}
      msg_id = "<original-msg-id@mailgun.org>"
      email = ReplyNotifier.success(@sender, invoice, in_reply_to: msg_id)

      assert email.headers["In-Reply-To"] == msg_id
      assert email.headers["References"] == msg_id
    end

    test "omits threading headers when in_reply_to is not provided" do
      invoice = %{id: "abc", invoice_number: "FV/1", seller_name: "Seller"}
      email = ReplyNotifier.success(@sender, invoice)

      assert email.headers == %{}
    end
  end

  describe "needs_review/3" do
    test "builds email for needs-review invoice" do
      invoice = %{id: "abc-123"}
      email = ReplyNotifier.needs_review(@sender, invoice)
      assert email.text_body =~ "needs human review"
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
