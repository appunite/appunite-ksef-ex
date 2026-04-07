defmodule KsefHub.Invoices.NipVerifierTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.NipVerifier

  @company_nip "1234567890"

  describe "verify_for_type/3" do
    test "returns :ok when buyer NIP matches company for expense" do
      extracted = %{"buyer_nip" => @company_nip}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "returns :ok when seller NIP matches company for income" do
      extracted = %{"seller_nip" => @company_nip}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :income)
    end

    test "returns error when buyer NIP doesn't match for expense" do
      extracted = %{"buyer_nip" => "9999999999"}

      assert {:error, :buyer_nip_mismatch} =
               NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "returns error when seller NIP doesn't match for income" do
      extracted = %{"seller_nip" => "9999999999"}

      assert {:error, :seller_nip_mismatch} =
               NipVerifier.verify_for_type(extracted, @company_nip, :income)
    end

    test "returns :ok when NIP not extracted (nil)" do
      extracted = %{"seller_name" => "Some Seller"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "returns :ok when NIP is empty string" do
      extracted = %{"buyer_nip" => ""}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "returns :ok when company NIP is nil" do
      extracted = %{"buyer_nip" => "9999999999"}
      assert :ok = NipVerifier.verify_for_type(extracted, nil, :expense)
    end

    test "normalizes PL prefix before comparing" do
      extracted = %{"buyer_nip" => "PL#{@company_nip}"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "normalizes dashes before comparing" do
      extracted = %{"buyer_nip" => "123-456-78-90"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "returns error for unknown type" do
      extracted = %{"buyer_nip" => "9999999999"}

      assert {:error, :unknown_invoice_type} =
               NipVerifier.verify_for_type(extracted, @company_nip, :other)
    end

    test "handles atom keys in extracted map" do
      extracted = %{buyer_nip: @company_nip}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "handles string type for expense" do
      extracted = %{"buyer_nip" => "9999999999"}

      assert {:error, :buyer_nip_mismatch} =
               NipVerifier.verify_for_type(extracted, @company_nip, "expense")
    end

    test "handles string type for income" do
      extracted = %{"seller_nip" => "9999999999"}

      assert {:error, :seller_nip_mismatch} =
               NipVerifier.verify_for_type(extracted, @company_nip, "income")
    end

    test "treats newline-null placeholder as not extracted" do
      extracted = %{"buyer_nip" => "\nnull"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "treats null string as not extracted" do
      extracted = %{"buyer_nip" => "null"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "treats N/A as not extracted" do
      extracted = %{"buyer_nip" => "N/A"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "treats dash placeholder as not extracted" do
      extracted = %{"buyer_nip" => "-"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end

    test "treats double-dash placeholder as not extracted" do
      extracted = %{"buyer_nip" => "--"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :expense)
    end
  end

  describe "verify_expense/2" do
    test "treats null placeholder as not extracted (needs review)" do
      extracted = %{"buyer_nip" => "null", "seller_nip" => "5555555555"}
      assert {:undetermined, :needs_review} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "treats newline-null placeholder as not extracted (needs review)" do
      extracted = %{"buyer_nip" => "\nnull", "seller_nip" => "5555555555"}
      assert {:undetermined, :needs_review} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "detects matching buyer NIP through PL prefix" do
      extracted = %{"buyer_nip" => "PL#{@company_nip}", "seller_nip" => "5555555555"}
      assert {:ok, :expense} = NipVerifier.verify_expense(extracted, @company_nip)
    end
  end
end
