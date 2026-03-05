defmodule KsefHub.NipTest do
  use ExUnit.Case, async: true

  doctest KsefHub.Nip

  alias KsefHub.Nip

  describe "normalize/1" do
    test "returns nil for nil" do
      assert Nip.normalize(nil) == nil
    end

    test "returns empty string for empty string" do
      assert Nip.normalize("") == ""
    end

    test "strips PL prefix" do
      assert Nip.normalize("PL1234567890") == "1234567890"
    end

    test "strips lowercase pl prefix" do
      assert Nip.normalize("pl1234567890") == "1234567890"
    end

    test "strips PL prefix with space" do
      assert Nip.normalize("PL 1234567890") == "1234567890"
    end

    test "strips dashes" do
      assert Nip.normalize("123-456-78-90") == "1234567890"
    end

    test "strips spaces" do
      assert Nip.normalize("123 456 78 90") == "1234567890"
    end

    test "trims whitespace" do
      assert Nip.normalize("  1234567890  ") == "1234567890"
    end

    test "preserves foreign tax IDs unchanged" do
      assert Nip.normalize("DE123456789") == "DE123456789"
    end

    test "preserves non-10-digit values unchanged" do
      assert Nip.normalize("12345") == "12345"
    end
  end
end
