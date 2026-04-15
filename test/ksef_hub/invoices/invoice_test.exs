defmodule KsefHub.Invoices.InvoiceTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.Invoice

  describe "source_label/1" do
    test "returns display labels for all known sources" do
      assert Invoice.source_label(:ksef) == "KSeF"
      assert Invoice.source_label(:manual) == "manual"
      assert Invoice.source_label(:pdf_upload) == "PDF upload"
      assert Invoice.source_label(:email) == "email"
    end

    test "returns unknown for unrecognized source" do
      assert Invoice.source_label(:something_else) == "unknown"
    end
  end

  describe "added_by_label/1" do
    test "returns KSeF label for ksef source" do
      assert Invoice.added_by_label(%{source: :ksef}) == "KSeF (automatic sync)"
    end

    test "returns email sender when inbound_email is loaded with sender" do
      assert Invoice.added_by_label(%{
               source: :email,
               inbound_email: %{sender: "sender@example.com"}
             }) == "sender@example.com (email)"
    end

    test "returns Email when inbound_email is nil" do
      assert Invoice.added_by_label(%{source: :email, inbound_email: nil}) == "Email"
    end

    test "returns Email when inbound_email is not loaded" do
      assert Invoice.added_by_label(%{
               source: :email,
               inbound_email: %Ecto.Association.NotLoaded{
                 __field__: :inbound_email,
                 __owner__: Invoice,
                 __cardinality__: :one
               }
             }) == "Email"
    end

    test "returns user name with source label for manual invoice" do
      assert Invoice.added_by_label(%{
               source: :manual,
               created_by: %{name: "Jan Kowalski", email: "jan@example.com"}
             }) == "Jan Kowalski (manual)"
    end

    test "returns user name with source label for pdf_upload" do
      assert Invoice.added_by_label(%{
               source: :pdf_upload,
               created_by: %{name: "Jan Kowalski", email: "jan@example.com"}
             }) == "Jan Kowalski (PDF upload)"
    end

    test "falls back to email when user name is empty string" do
      assert Invoice.added_by_label(%{
               source: :manual,
               created_by: %{name: "", email: "jan@example.com"}
             }) == "jan@example.com (manual)"
    end

    test "falls back to email when user name is nil" do
      assert Invoice.added_by_label(%{
               source: :manual,
               created_by: %{name: nil, email: "jan@example.com"}
             }) == "jan@example.com (manual)"
    end

    test "falls back to source label when created_by is nil" do
      assert Invoice.added_by_label(%{source: :manual, created_by: nil}) == "manual"
    end

    test "falls back to source label when created_by is not preloaded" do
      assert Invoice.added_by_label(%{
               source: :pdf_upload,
               created_by: %Ecto.Association.NotLoaded{
                 __field__: :created_by,
                 __owner__: Invoice,
                 __cardinality__: :one
               }
             }) == "PDF upload"
    end

    test "falls back to source label when created_by key is absent" do
      assert Invoice.added_by_label(%{source: :pdf_upload}) == "PDF upload"
    end
  end

  describe "correction?/1" do
    test "returns true for correction invoices" do
      assert Invoice.correction?(%Invoice{invoice_kind: :correction})
    end

    test "returns true for advance_correction invoices" do
      assert Invoice.correction?(%Invoice{invoice_kind: :advance_correction})
    end

    test "returns true for settlement_correction invoices" do
      assert Invoice.correction?(%Invoice{invoice_kind: :settlement_correction})
    end

    test "returns false for vat invoices" do
      refute Invoice.correction?(%Invoice{invoice_kind: :vat})
    end

    test "returns false for advance invoices" do
      refute Invoice.correction?(%Invoice{invoice_kind: :advance})
    end

    test "returns false for default (nil becomes :vat)" do
      refute Invoice.correction?(%Invoice{})
    end
  end

  describe "invoice_kind_label/1" do
    test "returns labels for all kinds" do
      assert Invoice.invoice_kind_label(:vat) == "VAT"
      assert Invoice.invoice_kind_label(:correction) == "correction"
      assert Invoice.invoice_kind_label(:advance) == "advance"
      assert Invoice.invoice_kind_label(:advance_settlement) == "advance settlement"
      assert Invoice.invoice_kind_label(:simplified) == "simplified"
      assert Invoice.invoice_kind_label(:advance_correction) == "advance correction"
      assert Invoice.invoice_kind_label(:settlement_correction) == "settlement correction"
    end
  end

  describe "correction_type_label/1" do
    test "returns labels for valid types" do
      assert Invoice.correction_type_label(1) == "Skutek na dacie faktury pierwotnej"
      assert Invoice.correction_type_label(2) == "Skutek na dacie faktury korygującej"
      assert Invoice.correction_type_label(3) == "Skutek na innej dacie"
    end

    test "returns empty string for nil" do
      assert Invoice.correction_type_label(nil) == ""
    end
  end

  describe "correction_kinds/0" do
    test "returns all correction kinds" do
      kinds = Invoice.correction_kinds()
      assert :correction in kinds
      assert :advance_correction in kinds
      assert :settlement_correction in kinds
      refute :vat in kinds
      refute :advance in kinds
    end
  end

  describe "changeset/2 correction field validation" do
    test "rejects correction-only fields on non-correction invoices" do
      cs =
        %Invoice{type: :expense, company_id: Ecto.UUID.generate()}
        |> Invoice.changeset(%{
          invoice_kind: :vat,
          corrected_invoice_number: "FV/2026/001",
          corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          corrected_invoice_date: ~D[2026-04-02],
          correction_reason: "Błąd",
          correction_type: 1,
          correction_period_from: ~D[2026-04-01],
          correction_period_to: ~D[2026-04-30]
        })

      errors = changeset_errors(cs)
      assert "only allowed on correction invoices" in errors[:corrected_invoice_number]
      assert "only allowed on correction invoices" in errors[:corrected_invoice_ksef_number]
      assert "only allowed on correction invoices" in errors[:corrected_invoice_date]
      assert "only allowed on correction invoices" in errors[:correction_reason]
      assert "only allowed on correction invoices" in errors[:correction_type]
      assert "only allowed on correction invoices" in errors[:correction_period_from]
      assert "only allowed on correction invoices" in errors[:correction_period_to]
    end

    test "allows correction fields on correction invoices" do
      cs =
        %Invoice{type: :expense, company_id: Ecto.UUID.generate()}
        |> Invoice.changeset(%{
          invoice_kind: :correction,
          corrected_invoice_number: "FV/2026/001",
          corrected_invoice_ksef_number: "7831812112-20260407-5B69FA00002B-9D",
          corrected_invoice_date: ~D[2026-04-02],
          correction_reason: "Błąd",
          correction_type: 1,
          correction_period_from: ~D[2026-04-01],
          correction_period_to: ~D[2026-04-30]
        })

      errors = changeset_errors(cs)
      refute Map.has_key?(errors, :corrected_invoice_number)
      refute Map.has_key?(errors, :corrected_invoice_ksef_number)
      refute Map.has_key?(errors, :corrected_invoice_date)
      refute Map.has_key?(errors, :correction_reason)
      refute Map.has_key?(errors, :correction_type)
      refute Map.has_key?(errors, :correction_period_from)
      refute Map.has_key?(errors, :correction_period_to)
    end
  end

  @spec changeset_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
