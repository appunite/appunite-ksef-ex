defmodule KsefHub.InvoiceExtractor.ContextBuilderTest do
  @moduledoc "Tests for ContextBuilder: company context string generation for extraction."

  use ExUnit.Case, async: true

  alias KsefHub.Companies.Company
  alias KsefHub.InvoiceExtractor.ContextBuilder

  doctest KsefHub.InvoiceExtractor.ContextBuilder

  @company %Company{
    name: "AppUnite S.A.",
    nip: "5261040828",
    address: "ul. Piaskowa 3, Poznań"
  }

  describe "build/1 without type" do
    test "builds context with full company (name, nip, address)" do
      result = ContextBuilder.build(@company)

      assert result =~ "AppUnite S.A., NIP 5261040828, ul. Piaskowa 3, Poznań"
      assert result =~ "Polish VAT invoice (Faktura VAT)"
      assert result =~ "PLN, USD, EUR, GBP"
      refute result =~ "unsure which NIP"
    end

    test "builds context without address when address is nil" do
      company = %Company{name: "Test Company Sp. z o.o.", nip: "1234567890", address: nil}
      result = ContextBuilder.build(company)

      assert result =~ "Test Company Sp. z o.o., NIP 1234567890."
      refute result =~ "nil"
    end

    test "builds context without address when address is empty string" do
      company = %Company{name: "Test Company Sp. z o.o.", nip: "1234567890", address: ""}
      result = ContextBuilder.build(company)

      assert result =~ "Test Company Sp. z o.o., NIP 1234567890."
      refute result =~ ", ."
    end
  end

  describe "build/2 with type" do
    test "expense type adds buyer NIP hint" do
      result = ContextBuilder.build(@company, :expense)

      assert result =~ "expense (cost) invoice"
      assert result =~ "the company is the buyer"
      assert result =~ "if you're unsure which NIP is the buyer's, it's likely 5261040828"
    end

    test "income type adds seller NIP hint" do
      result = ContextBuilder.build(@company, :income)

      assert result =~ "income (sales) invoice"
      assert result =~ "the company is the seller"
      assert result =~ "if you're unsure which NIP is the seller's, it's likely 5261040828"
    end

    test "nil type falls back to generic invoice type hint" do
      result = ContextBuilder.build(@company, nil)

      assert result =~ "income (the company sells) and expense (the company buys)"
      refute result =~ "unsure which NIP"
    end

    test "handles string type" do
      result = ContextBuilder.build(@company, "expense")

      assert result =~ "the company is the buyer"
    end
  end
end
