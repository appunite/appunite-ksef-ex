defmodule KsefHub.InboundEmail.InboundEmailWorkerTest do
  @moduledoc "Tests for InboundEmailWorker: extraction, NIP verification, and error handling."

  use KsefHub.DataCase, async: true

  import KsefHub.Factory
  import Mox

  alias KsefHub.InboundEmail
  alias KsefHub.InboundEmail.InboundEmailWorker

  setup :verify_on_exit!

  setup do
    company = insert(:company, nip: "1234567890")
    %{company: company}
  end

  @spec create_inbound_email(map(), keyword()) :: InboundEmail.InboundEmail.t()
  defp create_inbound_email(company, opts \\ []) do
    pdf_content = Keyword.get(opts, :pdf_content, "%PDF-1.4 test content")
    filename = Keyword.get(opts, :filename, "invoice.pdf")

    {:ok, record} =
      InboundEmail.create_inbound_email(company.id, %{
        sender: "user@appunite.com",
        recipient: "inv-test@inbound.ksef-hub.com",
        status: :received,
        pdf_content: pdf_content,
        original_filename: filename
      })

    record
  end

  describe "perform/1" do
    test "creates invoice on successful extraction with matching buyer NIP", %{company: company} do
      record = create_inbound_email(company)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "9999999999",
           "seller_name" => "Seller Sp. z o.o.",
           "buyer_nip" => "1234567890",
           "buyer_name" => "Buyer S.A.",
           "invoice_number" => "FV/2026/001",
           "issue_date" => "2026-02-25",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :completed
      assert updated.invoice_id != nil
    end

    test "creates invoice with needs_review when extraction is partial", %{company: company} do
      record = create_inbound_email(company)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok, %{"seller_name" => "Partial Seller"}}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :completed
      assert updated.invoice_id != nil
    end

    test "creates invoice with failed extraction when extraction service fails", %{
      company: company
    } do
      record = create_inbound_email(company)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:error, {:unstructured_service_error, 500}}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :completed
      assert updated.invoice_id != nil
    end

    test "rejects when seller NIP matches company (income invoice)", %{company: company} do
      record = create_inbound_email(company)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1234567890",
           "seller_name" => "Our Company",
           "buyer_nip" => "9999999999",
           "buyer_name" => "Customer",
           "invoice_number" => "FV/2026/002",
           "issue_date" => "2026-02-25",
           "net_amount" => "500.00",
           "gross_amount" => "615.00"
         }}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :rejected
      assert updated.error_message =~ "Income invoice"
    end

    test "rejects when neither NIP matches company", %{company: company} do
      record = create_inbound_email(company)

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "1111111111",
           "seller_name" => "Other Seller",
           "buyer_nip" => "2222222222",
           "buyer_name" => "Other Buyer",
           "invoice_number" => "FV/2026/003",
           "issue_date" => "2026-02-25",
           "net_amount" => "300.00",
           "gross_amount" => "369.00"
         }}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :rejected
      assert updated.error_message =~ "doesn't match"
    end

    test "cancels when inbound email record not found" do
      assert {:cancel, "inbound email not found"} =
               perform_job(Ecto.UUID.generate(), Ecto.UUID.generate())
    end

    test "cancels when company not found", %{company: company} do
      record = create_inbound_email(company)

      assert {:cancel, "company not found"} =
               perform_job(record.id, Ecto.UUID.generate())
    end

    test "sets status to failed when invoice creation fails", %{company: company} do
      # Create record without pdf_content — invoice creation requires it for :email source
      {:ok, record} =
        InboundEmail.create_inbound_email(company.id, %{
          sender: "user@appunite.com",
          recipient: "inv-test@inbound.ksef-hub.com",
          status: :received,
          pdf_content: nil,
          original_filename: "invoice.pdf"
        })

      KsefHub.Unstructured.Mock
      |> expect(:extract, fn _pdf, _opts ->
        {:ok,
         %{
           "seller_nip" => "9999999999",
           "seller_name" => "Seller Sp. z o.o.",
           "buyer_nip" => "1234567890",
           "buyer_name" => "Buyer S.A.",
           "invoice_number" => "FV/2026/001",
           "issue_date" => "2026-02-25",
           "net_amount" => "1000.00",
           "gross_amount" => "1230.00"
         }}
      end)

      assert :ok = perform_job(record.id, company.id)

      updated = InboundEmail.get_inbound_email!(record.id)
      assert updated.status == :failed
      assert updated.error_message != nil
    end
  end

  @spec perform_job(Ecto.UUID.t(), Ecto.UUID.t()) ::
          :ok | {:cancel, String.t()} | {:error, term()}
  defp perform_job(inbound_email_id, company_id) do
    job = %Oban.Job{
      args: %{
        "inbound_email_id" => inbound_email_id,
        "company_id" => company_id
      }
    }

    InboundEmailWorker.perform(job)
  end
end
