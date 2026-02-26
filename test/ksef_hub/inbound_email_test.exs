defmodule KsefHub.InboundEmailTest do
  @moduledoc "Tests for the InboundEmail context: CRUD operations, status updates, and uniqueness."

  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.InboundEmail, as: InboundEmailRecord

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "create_inbound_email/2" do
    test "creates a record with valid attributes", %{company: company} do
      attrs = %{
        sender: "user@example.com",
        recipient: "inv-abc12345@inbound.ksef-hub.com",
        subject: "Invoice FV/2026/001",
        status: :received,
        mailgun_message_id: "<msg-123@mailgun.org>",
        pdf_content: "%PDF-1.4 content",
        original_filename: "invoice.pdf"
      }

      assert {:ok, %InboundEmailRecord{} = record} =
               InboundEmail.create_inbound_email(company.id, attrs)

      assert record.company_id == company.id
      assert record.sender == "user@example.com"
      assert record.status == :received
      assert record.pdf_content == "%PDF-1.4 content"
    end

    test "requires sender and recipient", %{company: company} do
      assert {:error, changeset} =
               InboundEmail.create_inbound_email(company.id, %{status: :received})

      errors = errors_on(changeset)
      assert errors.sender
      assert errors.recipient
    end

    test "enforces mailgun_message_id uniqueness", %{company: company} do
      attrs = %{
        sender: "a@example.com",
        recipient: "inv-abc@inbound.ksef-hub.com",
        status: :received,
        mailgun_message_id: "<unique-id>"
      }

      assert {:ok, _} = InboundEmail.create_inbound_email(company.id, attrs)

      assert {:error, changeset} =
               InboundEmail.create_inbound_email(company.id, %{attrs | sender: "b@example.com"})

      assert "has already been taken" in errors_on(changeset).mailgun_message_id
    end
  end

  describe "update_status/2" do
    test "updates status and sets invoice_id", %{company: company} do
      {:ok, record} =
        InboundEmail.create_inbound_email(company.id, %{
          sender: "a@example.com",
          recipient: "inv-abc@inbound.ksef-hub.com",
          status: :received
        })

      invoice = insert(:invoice, company: company)

      assert {:ok, updated} =
               InboundEmail.update_status(record, %{
                 status: :completed,
                 invoice_id: invoice.id
               })

      assert updated.status == :completed
      assert updated.invoice_id == invoice.id
    end

    test "updates status with error message", %{company: company} do
      {:ok, record} =
        InboundEmail.create_inbound_email(company.id, %{
          sender: "a@example.com",
          recipient: "inv-abc@inbound.ksef-hub.com",
          status: :processing
        })

      assert {:ok, updated} =
               InboundEmail.update_status(record, %{
                 status: :failed,
                 error_message: "NIP mismatch"
               })

      assert updated.status == :failed
      assert updated.error_message == "NIP mismatch"
    end
  end

  describe "get_inbound_email/1" do
    test "returns record by ID", %{company: company} do
      {:ok, record} =
        InboundEmail.create_inbound_email(company.id, %{
          sender: "a@example.com",
          recipient: "inv@inbound.ksef-hub.com",
          status: :received
        })

      assert %InboundEmailRecord{} = InboundEmail.get_inbound_email(record.id)
    end

    test "returns nil for unknown ID" do
      assert InboundEmail.get_inbound_email(Ecto.UUID.generate()) == nil
    end
  end
end
