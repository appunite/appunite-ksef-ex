defmodule KsefHub.Invoices.DuplicatesTest do
  use KsefHub.DataCase, async: true

  import KsefHub.Factory

  alias KsefHub.Invoices
  alias KsefHub.Invoices.Invoice

  setup do
    company = insert(:company)
    %{company: company}
  end

  describe "confirm_duplicate/1" do
    test "confirms a suspected duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert {:ok, %Invoice{duplicate_status: :confirmed}} =
               Invoices.confirm_duplicate(duplicate)
    end

    test "returns error for non-duplicate invoice", %{company: company} do
      invoice = insert(:invoice, company: company)
      assert {:error, :not_a_duplicate} = Invoices.confirm_duplicate(invoice)
    end

    test "returns invalid_status when already confirmed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-c1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-c1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      assert {:error, :invalid_status} = Invoices.confirm_duplicate(duplicate)
    end

    test "returns invalid_status when already dismissed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-c2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-c2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      assert {:error, :invalid_status} = Invoices.confirm_duplicate(duplicate)
    end
  end

  describe "dismiss_duplicate/1" do
    test "dismisses a suspected duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :suspected
        )

      assert {:ok, %Invoice{duplicate_status: :dismissed}} =
               Invoices.dismiss_duplicate(duplicate)
    end

    test "dismisses a confirmed duplicate", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-d1", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-d1",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :confirmed
        )

      assert {:ok, %Invoice{duplicate_status: :dismissed}} =
               Invoices.dismiss_duplicate(duplicate)
    end

    test "returns error for non-duplicate invoice", %{company: company} do
      invoice = insert(:invoice, company: company)
      assert {:error, :not_a_duplicate} = Invoices.dismiss_duplicate(invoice)
    end

    test "returns invalid_status when already dismissed", %{company: company} do
      original = insert(:invoice, ksef_number: "orig-d2", company: company)

      duplicate =
        insert(:manual_invoice,
          ksef_number: "orig-d2",
          company: company,
          duplicate_of_id: original.id,
          duplicate_status: :dismissed
        )

      assert {:error, :invalid_status} = Invoices.dismiss_duplicate(duplicate)
    end
  end
end
