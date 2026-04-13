defmodule KsefHub.IbanTest do
  use ExUnit.Case, async: true

  alias KsefHub.Iban

  describe "normalize/1" do
    test "returns nil for nil" do
      assert Iban.normalize(nil) == nil
    end

    test "returns nil for empty string" do
      assert Iban.normalize("") == nil
    end

    test "strips spaces and upcases" do
      assert Iban.normalize("PL 61 1090 1014 0000 0712 1981 2874") ==
               "PL61109010140000071219812874"
    end

    test "strips dashes and upcases" do
      assert Iban.normalize("PL61-1090-1014-0000-0712-1981-2874") ==
               "PL61109010140000071219812874"
    end

    test "strips mixed spaces and dashes" do
      assert Iban.normalize("PL 61-1090 1014-0000 0712-1981 2874") ==
               "PL61109010140000071219812874"
    end

    test "upcases lowercase country prefix" do
      assert Iban.normalize("pl61109010140000071219812874") ==
               "PL61109010140000071219812874"
    end

    test "returns nil for value shorter than 15 chars" do
      assert Iban.normalize("PL12345") == nil
    end

    test "passes through already-clean IBAN unchanged" do
      assert Iban.normalize("PL61109010140000071219812874") ==
               "PL61109010140000071219812874"
    end

    test "handles non-standard account numbers (no country prefix) >= 15 chars" do
      assert Iban.normalize("123456789012345") == "123456789012345"
    end

    test "trims leading and trailing whitespace" do
      assert Iban.normalize("  PL61109010140000071219812874  ") ==
               "PL61109010140000071219812874"
    end
  end
end
