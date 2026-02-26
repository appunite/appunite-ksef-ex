defmodule KsefHub.InvoiceExtractor.ContextBuilderTest do
  @moduledoc "Tests for ContextBuilder: company context string generation for extraction."

  use ExUnit.Case, async: true

  alias KsefHub.Companies.Company
  alias KsefHub.InvoiceExtractor.ContextBuilder

  doctest KsefHub.InvoiceExtractor.ContextBuilder

  describe "build/1" do
    test "builds context with full company (name, nip, address)" do
      company = %Company{
        name: "AppUnite S.A.",
        nip: "5261040828",
        address: "ul. Piaskowa 3, Poznań"
      }

      result = ContextBuilder.build(company)

      assert result =~ "income (the company sells) and expense (the company buys)"
      assert result =~ "AppUnite S.A., NIP 5261040828, ul. Piaskowa 3, Poznań"
      assert result =~ "Polish VAT invoice (Faktura VAT)"
      assert result =~ "PLN, USD, EUR, GBP"
    end

    test "builds context without address when address is nil" do
      company = %Company{
        name: "Test Company Sp. z o.o.",
        nip: "1234567890",
        address: nil
      }

      result = ContextBuilder.build(company)

      assert result =~ "Test Company Sp. z o.o., NIP 1234567890."
      refute result =~ "nil"
    end

    test "builds context without address when address is empty string" do
      company = %Company{
        name: "Test Company Sp. z o.o.",
        nip: "1234567890",
        address: ""
      }

      result = ContextBuilder.build(company)

      assert result =~ "Test Company Sp. z o.o., NIP 1234567890."
      # Should not have a trailing comma before the period
      refute result =~ ", ."
    end
  end
end
