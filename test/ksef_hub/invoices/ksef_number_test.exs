defmodule KsefHub.Invoices.KsefNumberTest do
  use ExUnit.Case, async: true

  alias KsefHub.Invoices.KsefNumber

  describe "validate/1" do
    test "accepts valid KSeF numbers" do
      assert "5555555555-20250828-010080615740-E4" =
               KsefNumber.validate("5555555555-20250828-010080615740-E4")

      assert "5265877635-20250626-010080DD2B5E-26" =
               KsefNumber.validate("5265877635-20250626-010080DD2B5E-26")

      assert "8992736090-20260409-65A0D2000021-5E" =
               KsefNumber.validate("8992736090-20260409-65A0D2000021-5E")

      assert "1234567890-20240101-ABC123DEF456-78" =
               KsefNumber.validate("1234567890-20240101-ABC123DEF456-78")
    end

    test "rejects QR code URL path segments" do
      refute KsefNumber.validate(
               "8992736090/09-04-2026/U-J8M5W6XHhnxCnk_ovXNb8I6YS002Rx04QpDHJEMCA"
             )
    end

    test "rejects lowercase hex" do
      refute KsefNumber.validate("5555555555-20250828-010080615740-e4")
    end

    test "rejects short NIP (less than 10 digits)" do
      refute KsefNumber.validate("555555555-20250828-010080615740-E4")
    end

    test "rejects missing segments" do
      refute KsefNumber.validate("5555555555-20250828-E4")
    end

    test "rejects technical part with wrong length" do
      refute KsefNumber.validate("5555555555-20250828-AB12C-E4")
      refute KsefNumber.validate("5555555555-20250828-0100806157400A-E4")
    end

    test "returns nil for nil" do
      refute KsefNumber.validate(nil)
    end

    test "rejects plain strings" do
      refute KsefNumber.validate("pdf-dup-123")
      refute KsefNumber.validate("KSEF-SELF")
      refute KsefNumber.validate("manual-ksef-123")
    end

    test "rejects invalid calendar dates" do
      # month 13, day 40
      refute KsefNumber.validate("5555555555-20251340-010080615740-E4")
      # Feb 30
      refute KsefNumber.validate("5555555555-20250230-010080615740-E4")
      # month 00
      refute KsefNumber.validate("5555555555-20250015-010080615740-E4")
    end

    test "rejects empty string" do
      refute KsefNumber.validate("")
    end
  end

  describe "validate/2 (NIP cross-check)" do
    @valid "5555555555-20250828-010080615740-E4"

    test "accepts when NIP prefix matches seller_nip" do
      assert @valid == KsefNumber.validate(@valid, "5555555555")
    end

    test "rejects when NIP prefix does not match seller_nip" do
      refute KsefNumber.validate(@valid, "9999999999")
    end

    test "falls back to format-only when seller_nip is nil" do
      assert @valid == KsefNumber.validate(@valid, nil)
    end

    test "returns nil for nil value regardless of seller_nip" do
      refute KsefNumber.validate(nil, "5555555555")
    end

    test "rejects invalid format even if NIP would match" do
      refute KsefNumber.validate("5555555555-bad-format", "5555555555")
    end
  end
end
