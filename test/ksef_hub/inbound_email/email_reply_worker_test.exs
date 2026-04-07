defmodule KsefHub.InboundEmail.EmailReplyWorkerTest do
  @moduledoc "Tests for EmailReplyWorker: one-shot email delivery with preloaded category."

  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Swoosh.TestAssertions

  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.EmailReplyWorker
  alias KsefHub.Invoices

  setup do
    company = insert(:company, nip: "1234567890")
    %{company: company}
  end

  @spec create_inbound_email(map()) :: InboundEmail.InboundEmail.t()
  defp create_inbound_email(company) do
    {:ok, record} =
      InboundEmail.create_inbound_email(company.id, %{
        sender: "user@appunite.com",
        recipient: "inv-test@inbound.ksef-hub.com",
        status: :completed,
        pdf_content: "%PDF-1.4 test content",
        original_filename: "invoice.pdf"
      })

    record
  end

  @spec create_invoice(map()) :: Invoices.Invoice.t()
  defp create_invoice(company) do
    {:ok, invoice} =
      Invoices.create_invoice(
        %{
          company_id: company.id,
          type: :expense,
          source: :email,
          seller_nip: "9999999999",
          seller_name: "Test Seller",
          buyer_nip: "1234567890",
          buyer_name: "Test Buyer",
          invoice_number: "FV/2026/TEST",
          issue_date: ~D[2026-03-01],
          net_amount: Decimal.new("1000.00"),
          gross_amount: Decimal.new("1230.00"),
          currency: "PLN",
          pdf_content: "%PDF-1.4 test content",
          extraction_status: :complete
        },
        actor_type: :email,
        actor_label: "user@appunite.com"
      )

    invoice
  end

  describe "perform/1" do
    test "sends success email with invoice details", %{company: company} do
      record = create_inbound_email(company)
      invoice = create_invoice(company)

      result = perform_job(record.id, company.id, invoice.id, "success")

      assert result == :ok

      assert_email_sent(fn email ->
        assert email.to == [{"user@appunite.com", "user@appunite.com"}]
        assert email.subject =~ "FV/2026/TEST"
        assert email.text_body =~ "added and is ready"
        assert email.text_body =~ "Test Seller"
        assert email.text_body =~ "1230.00 PLN"
      end)
    end

    test "sends needs_review email with missing fields", %{company: company} do
      record = create_inbound_email(company)

      {:ok, invoice} =
        Invoices.create_invoice(
          %{
            company_id: company.id,
            type: :expense,
            source: :email,
            seller_name: "Partial Seller",
            pdf_content: "%PDF-1.4 test content",
            extraction_status: :partial
          },
          actor_type: :email
        )

      result = perform_job(record.id, company.id, invoice.id, "needs_review")

      assert result == :ok

      assert_email_sent(fn email ->
        assert email.subject =~ "needs human review"
        assert email.text_body =~ "Seller: Partial Seller"
        assert email.text_body =~ "Missing fields:"
      end)
    end

    test "includes category with emoji when assigned", %{company: company} do
      record = create_inbound_email(company)
      invoice = create_invoice(company)

      category = insert(:category, company: company, name: "Travel", emoji: "✈️")

      invoice
      |> Invoices.Invoice.category_changeset(%{category_id: category.id})
      |> KsefHub.Repo.update!()

      invoice
      |> Invoices.Invoice.prediction_changeset(%{
        prediction_status: :predicted,
        prediction_category_name: "travel",
        prediction_category_confidence: 0.95
      })
      |> KsefHub.Repo.update!()

      result = perform_job(record.id, company.id, invoice.id, "success")

      assert result == :ok

      assert_email_sent(fn email ->
        assert email.text_body =~ "Category: ✈️ Travel (95% confidence)"
      end)
    end

    test "cancels when invoice not found", %{company: company} do
      record = create_inbound_email(company)

      assert {:cancel, "invoice not found"} =
               perform_job(record.id, company.id, Ecto.UUID.generate(), "success")
    end

    test "cancels when inbound email not found", %{company: company} do
      invoice = create_invoice(company)

      assert {:cancel, "inbound email not found"} =
               perform_job(Ecto.UUID.generate(), company.id, invoice.id, "success")
    end

    test "cancels when company not found", %{company: company} do
      record = create_inbound_email(company)
      invoice = create_invoice(company)

      assert {:cancel, "company not found"} =
               perform_job(record.id, Ecto.UUID.generate(), invoice.id, "success")
    end
  end

  @spec perform_job(String.t(), String.t(), String.t(), String.t()) :: term()
  defp perform_job(inbound_email_id, company_id, invoice_id, reply_type) do
    job = %Oban.Job{
      args: %{
        "inbound_email_id" => inbound_email_id,
        "company_id" => company_id,
        "invoice_id" => invoice_id,
        "reply_type" => reply_type
      }
    }

    EmailReplyWorker.perform(job)
  end
end
