defmodule KsefHub.PaymentRequestsTest do
  use KsefHub.DataCase, async: true

  alias KsefHub.PaymentRequests
  alias KsefHub.PaymentRequests.PaymentRequest

  import KsefHub.Factory

  setup do
    user = insert(:user)
    company = insert(:company)
    insert(:membership, user: user, company: company, role: :owner)
    %{user: user, company: company}
  end

  describe "create_payment_request/3" do
    test "creates with valid attrs", %{company: company, user: user} do
      attrs = %{
        recipient_name: "Test Recipient",
        title: "Invoice FV/2026/001",
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("500.00"),
        currency: "PLN"
      }

      assert {:ok, pr} = PaymentRequests.create_payment_request(company.id, user.id, attrs)
      assert pr.recipient_name == "Test Recipient"
      assert pr.status == :pending
      assert pr.company_id == company.id
      assert pr.created_by_id == user.id
    end

    test "fails without required fields", %{company: company, user: user} do
      assert {:error, changeset} =
               PaymentRequests.create_payment_request(company.id, user.id, %{})

      assert errors_on(changeset) |> Map.has_key?(:recipient_name)
      assert errors_on(changeset) |> Map.has_key?(:title)
      assert errors_on(changeset) |> Map.has_key?(:iban)
      assert errors_on(changeset) |> Map.has_key?(:amount)
    end

    test "fails with invalid IBAN length", %{company: company, user: user} do
      attrs = %{
        recipient_name: "Test",
        title: "Test",
        iban: "PL12345",
        amount: Decimal.new("100.00"),
        currency: "PLN"
      }

      assert {:error, changeset} =
               PaymentRequests.create_payment_request(company.id, user.id, attrs)

      assert errors_on(changeset) |> Map.has_key?(:iban)
    end

    test "fails with non-positive amount", %{company: company, user: user} do
      attrs = %{
        recipient_name: "Test",
        title: "Test",
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("0"),
        currency: "PLN"
      }

      assert {:error, changeset} =
               PaymentRequests.create_payment_request(company.id, user.id, attrs)

      assert errors_on(changeset) |> Map.has_key?(:amount)
    end

    test "creates with invoice_id", %{company: company, user: user} do
      invoice = insert(:invoice, company: company)

      attrs = %{
        recipient_name: "Test",
        title: "Test",
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("100.00"),
        currency: "PLN",
        invoice_id: invoice.id
      }

      assert {:ok, pr} = PaymentRequests.create_payment_request(company.id, user.id, attrs)
      assert pr.invoice_id == invoice.id
    end

    test "normalizes address", %{company: company, user: user} do
      attrs = %{
        recipient_name: "Test",
        title: "Test",
        iban: "PL61109010140000071219812874",
        amount: Decimal.new("100.00"),
        currency: "PLN",
        recipient_address: %{"street" => " ul. Testowa 1 ", "city" => "Warszawa", "postal_code" => "", "country" => "PL"}
      }

      assert {:ok, pr} = PaymentRequests.create_payment_request(company.id, user.id, attrs)
      assert pr.recipient_address.street == "ul. Testowa 1"
      assert pr.recipient_address.postal_code == nil
    end
  end

  describe "list_payment_requests/2" do
    test "returns payment requests for a company", %{company: company, user: user} do
      pr = insert(:payment_request, company: company, created_by: user)
      _other = insert(:payment_request)

      results = PaymentRequests.list_payment_requests(company.id)
      assert length(results) == 1
      assert hd(results).id == pr.id
    end

    test "filters by status", %{company: company, user: user} do
      insert(:payment_request, company: company, created_by: user, status: :pending)
      insert(:payment_request, company: company, created_by: user, status: :paid)

      results = PaymentRequests.list_payment_requests(company.id, %{status: :pending})
      assert length(results) == 1
      assert hd(results).status == :pending
    end

    test "searches by query", %{company: company, user: user} do
      insert(:payment_request, company: company, created_by: user, recipient_name: "Alpha Corp")
      insert(:payment_request, company: company, created_by: user, recipient_name: "Beta Inc")

      results = PaymentRequests.list_payment_requests(company.id, %{query: "Alpha"})
      assert length(results) == 1
      assert hd(results).recipient_name == "Alpha Corp"
    end
  end

  describe "list_payment_requests_paginated/2" do
    test "returns paginated results", %{company: company, user: user} do
      for _ <- 1..3, do: insert(:payment_request, company: company, created_by: user)

      result = PaymentRequests.list_payment_requests_paginated(company.id, %{per_page: 2})
      assert length(result.entries) == 2
      assert result.total_count == 3
      assert result.total_pages == 2
    end
  end

  describe "get_payment_request!/2" do
    test "returns the payment request", %{company: company, user: user} do
      pr = insert(:payment_request, company: company, created_by: user)

      assert found = PaymentRequests.get_payment_request!(company.id, pr.id)
      assert found.id == pr.id
    end

    test "raises for wrong company" do
      other_company = insert(:company)
      pr = insert(:payment_request)

      assert_raise Ecto.NoResultsError, fn ->
        PaymentRequests.get_payment_request!(other_company.id, pr.id)
      end
    end
  end

  describe "mark_as_paid/2" do
    test "marks a pending payment request as paid", %{company: company, user: user} do
      pr = insert(:payment_request, company: company, created_by: user, status: :pending)

      assert {:ok, updated} = PaymentRequests.mark_as_paid(company.id, pr.id)
      assert updated.status == :paid
    end

    test "returns error for non-existent ID", %{company: company} do
      assert {:error, :not_found} =
               PaymentRequests.mark_as_paid(company.id, Ecto.UUID.generate())
    end
  end

  describe "mark_many_as_paid/2" do
    test "marks multiple pending requests as paid", %{company: company, user: user} do
      pr1 = insert(:payment_request, company: company, created_by: user, status: :pending)
      pr2 = insert(:payment_request, company: company, created_by: user, status: :pending)
      pr3 = insert(:payment_request, company: company, created_by: user, status: :paid)

      {count, _} = PaymentRequests.mark_many_as_paid(company.id, [pr1.id, pr2.id, pr3.id])
      assert count == 2
    end
  end

  describe "prefill_attrs_from_invoice/1" do
    test "prefills from expense invoice" do
      invoice = %KsefHub.Invoices.Invoice{
        id: Ecto.UUID.generate(),
        type: :expense,
        seller_name: "Seller Co",
        seller_address: %{street: "ul. Testowa 1", city: "Warszawa"},
        gross_amount: Decimal.new("1230.00"),
        currency: "PLN",
        invoice_number: "FV/2026/001",
        iban: "PL12345678901234567890123456"
      }

      attrs = PaymentRequests.prefill_attrs_from_invoice(invoice)
      assert attrs.recipient_name == "Seller Co"
      assert attrs.amount == Decimal.new("1230.00")
      assert attrs.iban == "PL12345678901234567890123456"
      assert attrs.title == "Invoice FV/2026/001"
      assert attrs.invoice_id == invoice.id
    end

    test "prefills from income invoice" do
      invoice = %KsefHub.Invoices.Invoice{
        id: Ecto.UUID.generate(),
        type: :income,
        buyer_name: "Buyer Co",
        buyer_address: %{city: "Krakow"},
        gross_amount: Decimal.new("500.00"),
        currency: "EUR",
        invoice_number: "FV/2026/002",
        iban: nil
      }

      attrs = PaymentRequests.prefill_attrs_from_invoice(invoice)
      assert attrs.recipient_name == "Buyer Co"
      assert attrs.iban == ""
    end
  end

  describe "payment_status_for_invoice/1" do
    test "returns nil when no payment requests", %{company: _company} do
      invoice = insert(:invoice)
      assert PaymentRequests.payment_status_for_invoice(invoice.id) == nil
    end

    test "returns :pending when all PRs are pending", %{company: company, user: user} do
      invoice = insert(:invoice, company: company)

      insert(:payment_request,
        company: company,
        created_by: user,
        invoice: invoice,
        status: :pending
      )

      assert PaymentRequests.payment_status_for_invoice(invoice.id) == :pending
    end

    test "returns :paid when any PR is paid", %{company: company, user: user} do
      invoice = insert(:invoice, company: company)

      insert(:payment_request,
        company: company,
        created_by: user,
        invoice: invoice,
        status: :pending
      )

      insert(:payment_request,
        company: company,
        created_by: user,
        invoice: invoice,
        status: :paid
      )

      assert PaymentRequests.payment_status_for_invoice(invoice.id) == :paid
    end
  end

  describe "payment_statuses_for_invoices/1" do
    test "returns batch statuses", %{company: company, user: user} do
      inv1 = insert(:invoice, company: company)
      inv2 = insert(:invoice, company: company)
      inv3 = insert(:invoice, company: company)

      insert(:payment_request, company: company, created_by: user, invoice: inv1, status: :paid)
      insert(:payment_request, company: company, created_by: user, invoice: inv2, status: :pending)

      result = PaymentRequests.payment_statuses_for_invoices([inv1.id, inv2.id, inv3.id])

      assert result[inv1.id] == :paid
      assert result[inv2.id] == :pending
      refute Map.has_key?(result, inv3.id)
    end

    test "returns empty map for empty list" do
      assert PaymentRequests.payment_statuses_for_invoices([]) == %{}
    end
  end
end
