defmodule KsefHub.InboundEmail.NipVerifierTest do
  use ExUnit.Case, async: true

  alias KsefHub.InboundEmail.NipVerifier

  @company_nip "1234567890"

  describe "verify_expense/2" do
    test "returns {:ok, :expense} when buyer_nip matches company NIP" do
      extracted = %{buyer_nip: @company_nip, seller_nip: "9999999999"}
      assert {:ok, :expense} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "returns {:error, :income_not_allowed} when seller_nip matches company NIP" do
      extracted = %{buyer_nip: "9999999999", seller_nip: @company_nip}

      assert {:error, :income_not_allowed} =
               NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "returns {:error, :nip_mismatch} when neither NIP matches" do
      extracted = %{buyer_nip: "1111111111", seller_nip: "2222222222"}
      assert {:error, :nip_mismatch} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "returns {:undetermined, :needs_review} when buyer_nip is nil" do
      extracted = %{buyer_nip: nil, seller_nip: "9999999999"}
      assert {:undetermined, :needs_review} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "returns {:undetermined, :needs_review} when both NIPs are nil" do
      extracted = %{buyer_nip: nil, seller_nip: nil}
      assert {:undetermined, :needs_review} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "handles string keys in extracted map" do
      extracted = %{"buyer_nip" => @company_nip, "seller_nip" => "9999999999"}
      assert {:ok, :expense} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "handles empty string buyer_nip as missing" do
      extracted = %{buyer_nip: "", seller_nip: "9999999999"}
      assert {:undetermined, :needs_review} = NipVerifier.verify_expense(extracted, @company_nip)
    end

    test "seller_nip match takes priority over missing buyer_nip" do
      extracted = %{buyer_nip: nil, seller_nip: @company_nip}

      assert {:error, :income_not_allowed} =
               NipVerifier.verify_expense(extracted, @company_nip)
    end
  end
end
