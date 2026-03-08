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
end
