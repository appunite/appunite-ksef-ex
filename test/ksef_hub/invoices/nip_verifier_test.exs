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

    test "returns :ok for unknown type" do
      extracted = %{"buyer_nip" => "9999999999"}
      assert :ok = NipVerifier.verify_for_type(extracted, @company_nip, :other)
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
  end
end
